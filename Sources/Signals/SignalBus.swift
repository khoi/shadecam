import Foundation

enum SignalNames {
    static let faceRect = "face.rect"
    static let expression = "expression"
    static let audio = "audio"
    static let events = [
        "event.wave",
        "event.clap",
        "event.pinch",
        "event.push",
        "event.smile",
        "event.reserved.5",
        "event.reserved.6",
        "event.debug",
    ]
    static let clapEvent = events[1]
    static let smileEvent = events[4]
    static let debugEvent = events[7]

    static func hand(_ hand: Int, _ joint: Int) -> String {
        precondition((0..<2).contains(hand) && (0..<21).contains(joint))
        return "hand.\(hand).joint.\(joint)"
    }
}

enum SignalFilterKind: Equatable, Sendable {
    case continuous(components: Int, configuration: OneEuroFilter.Configuration)
    case latch(HysteresisLatch.Configuration)
    case event(EventEnvelope.Configuration)
}

enum SignalUniformDestination: Equatable, Hashable, Sendable {
    case faceRect
    case expression
    case expressionComponent(Int)
    case audio
    case audioComponent(Int)
    case event(Int)
    case hand(Int, Int)
    case body(Int)
}

struct SignalDescriptor: Equatable, Sendable {
    let name: String
    let kind: SignalFilterKind
    let destination: SignalUniformDestination
}

struct SignalSnapshot: Sendable {
    var faceRect = SIMD4<Float>.zero
    var expression = SIMD4<Float>.zero
    var audio = SIMD4<Float>.zero
    var events = ShaderEventUniforms()
    var hands = ShaderHandUniforms()
    var body = ShaderBodyUniforms()
    var values: [String: SIMD4<Float>] = [:]

    mutating func apply(_ value: SIMD4<Float>, to destination: SignalUniformDestination) {
        switch destination {
        case .faceRect:
            faceRect = value
        case .expression:
            expression = value
        case let .expressionComponent(component):
            expression[component] = value.x
        case .audio:
            audio = value
        case let .audioComponent(component):
            audio[component] = value.x
        case let .event(slot):
            events[slot] = value
        case let .hand(hand, joint):
            hands[hand, joint] = value
        case let .body(joint):
            body[joint] = value
        }
    }
}

final class SignalBus: @unchecked Sendable {
    private let lock = NSLock()
    private var descriptors: [String: SignalDescriptor] = [:]
    private var states: [String: SignalState] = [:]

    static var standard: SignalBus {
        let continuous = OneEuroFilter.Configuration(
            minimumCutoff: 1,
            speedCoefficient: 0.02,
            derivativeCutoff: 1
        )
        let descriptors = [
            SignalDescriptor(
                name: SignalNames.faceRect,
                kind: .continuous(components: 4, configuration: continuous),
                destination: .faceRect
            ),
            SignalDescriptor(
                name: SignalNames.expression,
                kind: .continuous(components: 4, configuration: continuous),
                destination: .expression
            ),
            SignalDescriptor(
                name: SignalNames.audio,
                kind: .continuous(components: 4, configuration: continuous),
                destination: .audio
            ),
        ] + SignalNames.events.enumerated().map { slot, name in
            SignalDescriptor(
                name: name,
                kind: .event(.init()),
                destination: .event(slot)
            )
        } + (0..<2).flatMap { hand in
            (0..<21).map { joint in
                SignalDescriptor(
                    name: SignalNames.hand(hand, joint),
                    kind: .continuous(components: 4, configuration: continuous),
                    destination: .hand(hand, joint)
                )
            }
        }
        return SignalBus(descriptors: descriptors)
    }

    init(descriptors: [SignalDescriptor] = []) {
        for descriptor in descriptors {
            register(descriptor)
        }
    }

    func register(_ descriptor: SignalDescriptor) {
        lock.withLock {
            if let existing = descriptors[descriptor.name] {
                precondition(existing == descriptor)
                return
            }
            descriptors[descriptor.name] = descriptor
            states[descriptor.name] = SignalState(kind: descriptor.kind)
        }
    }

    func write(_ value: SIMD4<Float>, to name: String, at timestamp: TimeInterval) {
        lock.withLock {
            guard var state = states[name] else {
                preconditionFailure("Unregistered signal: \(name)")
            }
            state.write(value, at: timestamp)
            states[name] = state
        }
    }

    func trigger(_ name: String, at timestamp: TimeInterval, position: SIMD2<Float>) {
        lock.withLock {
            guard var state = states[name] else {
                preconditionFailure("Unregistered signal: \(name)")
            }
            state.trigger(at: timestamp, position: position)
            states[name] = state
        }
    }

    func snapshot(at timestamp: TimeInterval) -> SignalSnapshot {
        lock.withLock {
            var snapshot = SignalSnapshot()
            for (name, descriptor) in descriptors {
                let value = states[name]!.value(at: timestamp)
                snapshot.values[name] = value
                snapshot.apply(value, to: descriptor.destination)
            }
            return snapshot
        }
    }
}

private enum SignalState {
    case continuous(ContinuousSignalState)
    case latch(HysteresisLatch)
    case event(EventEnvelope)

    init(kind: SignalFilterKind) {
        switch kind {
        case let .continuous(components, configuration):
            precondition((1...4).contains(components))
            self = .continuous(ContinuousSignalState(components: components, configuration: configuration))
        case let .latch(configuration):
            self = .latch(HysteresisLatch(configuration: configuration))
        case let .event(configuration):
            self = .event(EventEnvelope(configuration: configuration))
        }
    }

    mutating func write(_ value: SIMD4<Float>, at timestamp: TimeInterval) {
        switch self {
        case var .continuous(state):
            state.write(value, at: timestamp)
            self = .continuous(state)
        case var .latch(latch):
            _ = latch.update(value.x, at: timestamp)
            self = .latch(latch)
        case .event:
            preconditionFailure("Event signals must be triggered")
        }
    }

    mutating func trigger(at timestamp: TimeInterval, position: SIMD2<Float>) {
        guard case var .event(envelope) = self else {
            preconditionFailure("Only event signals can be triggered")
        }
        envelope.trigger(at: timestamp, position: position)
        self = .event(envelope)
    }

    func value(at timestamp: TimeInterval) -> SIMD4<Float> {
        switch self {
        case let .continuous(state):
            state.value
        case let .latch(latch):
            SIMD4(latch.isOn ? 1 : 0, 0, 0, 0)
        case let .event(envelope):
            SIMD4(
                envelope.value(at: timestamp),
                envelope.timeSinceTrigger(at: timestamp),
                envelope.triggerPosition.x,
                envelope.triggerPosition.y
            )
        }
    }
}

private struct ContinuousSignalState {
    private var filters: [OneEuroFilter]
    private(set) var value = SIMD4<Float>.zero

    init(components: Int, configuration: OneEuroFilter.Configuration) {
        filters = (0..<components).map { _ in OneEuroFilter(configuration: configuration) }
    }

    mutating func write(_ value: SIMD4<Float>, at timestamp: TimeInterval) {
        for index in filters.indices {
            self.value[index] = filters[index].filter(value[index], at: timestamp)
        }
    }
}
