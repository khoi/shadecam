import CoreVideo
import Foundation
import Vision

actor HandPoseService {
    private let signalBus: SignalBus
    private var request: DetectHumanHandPoseRequest
    private var isProcessing = false

    init(signalBus: SignalBus) {
        self.signalBus = signalBus
        var request = DetectHumanHandPoseRequest()
        request.maximumHandCount = 2
        self.request = request
    }

    func process(_ frame: SendablePixelBuffer, at timestamp: TimeInterval) async {
        guard !isProcessing else {
            return
        }
        isProcessing = true
        defer {
            isProcessing = false
        }

        guard let observations = try? await request.perform(on: frame.value) else {
            return
        }

        let hands = assignedHands(from: observations)
        for slot in hands.indices {
            write(pose(from: hands[slot]), to: slot, at: timestamp)
        }
    }

    func clear(at timestamp: TimeInterval) {
        for slot in 0..<2 {
            write(HandPose(), to: slot, at: timestamp)
        }
    }

    private func assignedHands(
        from observations: [HumanHandPoseObservation]
    ) -> [HumanHandPoseObservation?] {
        var slots = [HumanHandPoseObservation?](repeating: nil, count: 2)
        var unassigned: [HumanHandPoseObservation] = []

        for observation in observations {
            let preferredSlot: Int? = if observation.chirality == .left {
                0
            } else if observation.chirality == .right {
                1
            } else {
                nil
            }
            if let preferredSlot, slots[preferredSlot] == nil {
                slots[preferredSlot] = observation
            } else {
                unassigned.append(observation)
            }
        }

        let sorted = unassigned.sorted { wristX(for: $0) < wristX(for: $1) }
        for (slot, observation) in zip(slots.indices.filter { slots[$0] == nil }, sorted) {
            slots[slot] = observation
        }
        return slots
    }

    private func wristX(for observation: HumanHandPoseObservation) -> CGFloat {
        observation.joint(for: .wrist)?.location.x ?? 0.5
    }

    private func pose(from observation: HumanHandPoseObservation?) -> HandPose {
        guard let observation else {
            return HandPose()
        }

        var pose = HandPose()
        for joint in HandJoint.allCases {
            guard let value = observation.joint(for: joint.visionName) else {
                continue
            }
            pose[joint] = SIMD4(
                Float(value.location.x),
                1 - Float(value.location.y),
                value.confidence,
                0
            )
        }
        return pose
    }

    private func write(_ pose: HandPose, to slot: Int, at timestamp: TimeInterval) {
        for joint in HandJoint.allCases {
            signalBus.write(
                pose[joint],
                to: SignalNames.hand(slot, joint.rawValue),
                at: timestamp
            )
        }
    }
}
