import CoreVideo
import Foundation
import Vision

actor BodyPoseService {
    private let signalBus: SignalBus
    private var request = DetectHumanBodyPoseRequest()
    private var isProcessing = false

    init(signalBus: SignalBus) {
        self.signalBus = signalBus
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
        write(pose(from: observations.first), at: timestamp)
    }

    func clear(at timestamp: TimeInterval) {
        write(BodyPose(), at: timestamp)
    }

    private func pose(from observation: HumanBodyPoseObservation?) -> BodyPose {
        guard let observation else {
            return BodyPose()
        }

        var pose = BodyPose()
        for joint in BodyJoint.allCases {
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

    private func write(_ pose: BodyPose, at timestamp: TimeInterval) {
        for joint in BodyJoint.allCases {
            signalBus.write(
                pose[joint],
                to: SignalNames.body(joint.rawValue),
                at: timestamp
            )
        }
    }
}
