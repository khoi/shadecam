import Foundation

enum HandGestureThresholds {
    static let minimumConfidence: Float = 0.5
    static let pinchOnDistance: Float = 0.25
    static let pinchOffDistance: Float = 0.4
    static let pinchHoldDuration: TimeInterval = 0.15
    static let waveSwingAmplitude: Float = 0.04
    static let waveReversalCount = 3
    static let waveWindowDuration: TimeInterval = 1.2
    static let pushGrowth: Float = 0.35
    static let pushWindowDuration: TimeInterval = 0.4
    static let refractoryDuration: TimeInterval = 1
}

enum HandGesture: Equatable, Sendable {
    case wave(SIMD2<Float>)
    case pinch(SIMD2<Float>)
    case push(SIMD2<Float>)

    var signalName: String {
        switch self {
        case .wave: SignalNames.events[0]
        case .pinch: SignalNames.events[2]
        case .push: SignalNames.events[3]
        }
    }

    var position: SIMD2<Float> {
        switch self {
        case let .wave(position), let .pinch(position), let .push(position): position
        }
    }
}

struct HandGestureRecognizer: Sendable {
    private var pinch = PinchGestureRecognizer()
    private var wave = WaveGestureRecognizer()
    private var push = PushGestureRecognizer()

    mutating func update(_ pose: HandPose, at timestamp: TimeInterval) -> [HandGesture] {
        var gestures: [HandGesture] = []
        if let position = wave.update(pose, at: timestamp) {
            gestures.append(.wave(position))
        }
        if let position = pinch.update(pose, at: timestamp) {
            gestures.append(.pinch(position))
        }
        if let position = push.update(pose, at: timestamp) {
            gestures.append(.push(position))
        }
        return gestures
    }
}

struct PinchGestureRecognizer: Sendable {
    private var latch = HysteresisLatch(
        configuration: .init(
            onThreshold: -HandGestureThresholds.pinchOnDistance,
            offThreshold: -HandGestureThresholds.pinchOffDistance,
            minimumHoldDuration: HandGestureThresholds.pinchHoldDuration
        )
    )

    mutating func update(_ pose: HandPose, at timestamp: TimeInterval) -> SIMD2<Float>? {
        let wasOn = latch.isOn
        let wrist = pose[.wrist]
        let middleMCP = pose[.middleMCP]
        let thumbTip = pose[.thumbTip]
        let indexTip = pose[.indexTip]
        let required = [wrist, middleMCP, thumbTip, indexTip]
        guard required.allSatisfy({ $0.z >= HandGestureThresholds.minimumConfidence }) else {
            _ = latch.update(-Float.greatestFiniteMagnitude, at: timestamp)
            return nil
        }

        let handSpan = distance(point(wrist), point(middleMCP))
        guard handSpan > .leastNonzeroMagnitude else {
            _ = latch.update(-Float.greatestFiniteMagnitude, at: timestamp)
            return nil
        }

        let pinchDistance = distance(point(thumbTip), point(indexTip)) / handSpan
        let isOn = latch.update(-pinchDistance, at: timestamp)
        guard isOn, !wasOn else {
            return nil
        }
        return (point(thumbTip) + point(indexTip)) / 2
    }
}

struct WaveGestureRecognizer: Sendable {
    private struct Sample: Sendable {
        let timestamp: TimeInterval
        let x: Float
    }

    private var previousSample: Sample?
    private var direction: FloatingPointSign?
    private var swingStartX: Float?
    private var reversals: [TimeInterval] = []
    private var lastTriggerTimestamp: TimeInterval?

    mutating func update(_ pose: HandPose, at timestamp: TimeInterval) -> SIMD2<Float>? {
        let wrist = pose[.wrist]
        guard wrist.z >= HandGestureThresholds.minimumConfidence else {
            resetMotion()
            reversals.removeAll()
            return nil
        }

        guard let previousSample else {
            self.previousSample = Sample(timestamp: timestamp, x: wrist.x)
            return nil
        }
        guard timestamp > previousSample.timestamp else {
            return nil
        }

        let delta = wrist.x - previousSample.x
        guard delta != 0 else {
            self.previousSample = Sample(timestamp: timestamp, x: wrist.x)
            return nil
        }

        let nextDirection = delta.sign
        if let direction, nextDirection != direction, let swingStartX {
            let amplitude = abs(previousSample.x - swingStartX)
            self.direction = nextDirection
            self.swingStartX = previousSample.x
            if amplitude > HandGestureThresholds.waveSwingAmplitude {
                reversals.append(timestamp)
            } else {
                reversals.removeAll()
            }
        } else if direction == nil {
            direction = nextDirection
            swingStartX = previousSample.x
        }
        self.previousSample = Sample(timestamp: timestamp, x: wrist.x)
        reversals.removeAll { timestamp - $0 > HandGestureThresholds.waveWindowDuration }

        guard reversals.count >= HandGestureThresholds.waveReversalCount else {
            return nil
        }
        reversals.removeAll()
        guard canTrigger(at: timestamp) else {
            return nil
        }
        lastTriggerTimestamp = timestamp
        return point(wrist)
    }

    private func canTrigger(at timestamp: TimeInterval) -> Bool {
        lastTriggerTimestamp.map {
            timestamp - $0 >= HandGestureThresholds.refractoryDuration
        } ?? true
    }

    private mutating func resetMotion() {
        previousSample = nil
        direction = nil
        swingStartX = nil
    }
}

struct PushGestureRecognizer: Sendable {
    private struct Sample: Sendable {
        let timestamp: TimeInterval
        let span: Float
    }

    private var samples: [Sample] = []
    private var lastTriggerTimestamp: TimeInterval?

    mutating func update(_ pose: HandPose, at timestamp: TimeInterval) -> SIMD2<Float>? {
        let confidentPoints = HandJoint.allCases.compactMap { joint -> SIMD2<Float>? in
            let value = pose[joint]
            return value.z >= HandGestureThresholds.minimumConfidence ? point(value) : nil
        }
        guard confidentPoints.count >= 2 else {
            samples.removeAll()
            return nil
        }

        samples.removeAll { timestamp - $0.timestamp > HandGestureThresholds.pushWindowDuration }
        let span = maximumDistance(in: confidentPoints)
        let grew = samples.contains {
            span > $0.span * (1 + HandGestureThresholds.pushGrowth)
        }
        samples.append(Sample(timestamp: timestamp, span: span))

        guard grew, canTrigger(at: timestamp), let palmCenter = palmCenter(of: pose) else {
            return nil
        }
        lastTriggerTimestamp = timestamp
        samples = [Sample(timestamp: timestamp, span: span)]
        return palmCenter
    }

    private func palmCenter(of pose: HandPose) -> SIMD2<Float>? {
        let joints: [HandJoint] = [.indexMCP, .middleMCP, .ringMCP, .littleMCP]
        let values = joints.map { pose[$0] }
        guard values.allSatisfy({ $0.z >= HandGestureThresholds.minimumConfidence }) else {
            return nil
        }
        return values.reduce(SIMD2<Float>.zero) { $0 + point($1) } / Float(values.count)
    }

    private func canTrigger(at timestamp: TimeInterval) -> Bool {
        lastTriggerTimestamp.map {
            timestamp - $0 >= HandGestureThresholds.refractoryDuration
        } ?? true
    }

    private func maximumDistance(in points: [SIMD2<Float>]) -> Float {
        var maximum: Float = 0
        for first in points.indices {
            for second in points.indices where second > first {
                maximum = max(maximum, distance(points[first], points[second]))
            }
        }
        return maximum
    }
}

private func point(_ value: SIMD4<Float>) -> SIMD2<Float> {
    SIMD2(value.x, value.y)
}

private func distance(_ first: SIMD2<Float>, _ second: SIMD2<Float>) -> Float {
    let delta = first - second
    return sqrt(delta.x * delta.x + delta.y * delta.y)
}
