import Foundation

struct OneEuroFilter: Sendable {
    struct Configuration: Equatable, Sendable {
        var minimumCutoff: Float = 1
        var speedCoefficient: Float = 0
        var derivativeCutoff: Float = 1
    }

    private let configuration: Configuration
    private var previousTimestamp: TimeInterval?
    private var previousRawValue: Float?
    private(set) var value: Float?
    private var derivative: Float?

    init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    mutating func filter(_ rawValue: Float, at timestamp: TimeInterval) -> Float {
        guard
            let previousTimestamp,
            let previousRawValue,
            let value
        else {
            self.previousTimestamp = timestamp
            self.previousRawValue = rawValue
            value = rawValue
            derivative = 0
            return rawValue
        }

        let interval = timestamp - previousTimestamp
        guard interval > 0 else {
            return value
        }

        let rawDerivative = (rawValue - previousRawValue) / Float(interval)
        let derivativeAlpha = alpha(cutoff: configuration.derivativeCutoff, interval: interval)
        let filteredDerivative = lowPass(rawDerivative, previous: derivative, alpha: derivativeAlpha)
        let cutoff = configuration.minimumCutoff
            + configuration.speedCoefficient * abs(filteredDerivative)
        let filteredValue = lowPass(rawValue, previous: value, alpha: alpha(cutoff: cutoff, interval: interval))

        self.previousTimestamp = timestamp
        self.previousRawValue = rawValue
        self.value = filteredValue
        derivative = filteredDerivative
        return filteredValue
    }

    private func alpha(cutoff: Float, interval: TimeInterval) -> Float {
        let timeConstant = 1 / (2 * Float.pi * max(cutoff, .leastNonzeroMagnitude))
        return 1 / (1 + timeConstant / Float(interval))
    }

    private func lowPass(_ value: Float, previous: Float?, alpha: Float) -> Float {
        guard let previous else {
            return value
        }
        return alpha * value + (1 - alpha) * previous
    }
}

struct HysteresisLatch: Sendable {
    struct Configuration: Equatable, Sendable {
        var onThreshold: Float
        var offThreshold: Float
        var minimumHoldDuration: TimeInterval

        init(onThreshold: Float, offThreshold: Float, minimumHoldDuration: TimeInterval) {
            precondition(onThreshold > offThreshold)
            precondition(minimumHoldDuration >= 0)
            self.onThreshold = onThreshold
            self.offThreshold = offThreshold
            self.minimumHoldDuration = minimumHoldDuration
        }
    }

    private let configuration: Configuration
    private var lastTransitionTimestamp: TimeInterval?
    private(set) var isOn = false

    init(configuration: Configuration) {
        self.configuration = configuration
    }

    mutating func update(_ value: Float, at timestamp: TimeInterval) -> Bool {
        let canTransition = lastTransitionTimestamp.map {
            timestamp - $0 >= configuration.minimumHoldDuration
        } ?? true

        if isOn, value <= configuration.offThreshold, canTransition {
            isOn = false
            lastTransitionTimestamp = timestamp
        } else if !isOn, value >= configuration.onThreshold, canTransition {
            isOn = true
            lastTransitionTimestamp = timestamp
        }
        return isOn
    }
}

struct EventEnvelope: Sendable {
    struct Configuration: Equatable, Sendable {
        var attackDuration: TimeInterval = 0.05
        var releaseDuration: TimeInterval = 2

        init(attackDuration: TimeInterval = 0.05, releaseDuration: TimeInterval = 2) {
            precondition(attackDuration > 0)
            precondition(releaseDuration > 0)
            self.attackDuration = attackDuration
            self.releaseDuration = releaseDuration
        }
    }

    private let configuration: Configuration
    private(set) var triggerTimestamp: TimeInterval?
    private(set) var triggerPosition = SIMD2<Float>.zero

    init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    mutating func trigger(at timestamp: TimeInterval, position: SIMD2<Float>) {
        triggerTimestamp = timestamp
        triggerPosition = position
    }

    func value(at timestamp: TimeInterval) -> Float {
        guard let triggerTimestamp else {
            return 0
        }
        let elapsed = max(timestamp - triggerTimestamp, 0)
        if elapsed < configuration.attackDuration {
            return Float(elapsed / configuration.attackDuration)
        }
        let releaseProgress = (elapsed - configuration.attackDuration) / configuration.releaseDuration
        return Float(exp(-4.605_170_186 * releaseProgress))
    }

    func timeSinceTrigger(at timestamp: TimeInterval) -> Float {
        guard let triggerTimestamp else {
            return -1
        }
        return Float(max(timestamp - triggerTimestamp, 0))
    }
}
