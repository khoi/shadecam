import Vision

enum BodyJoint: Int, CaseIterable, Sendable {
    case nose
    case leftEye
    case rightEye
    case leftEar
    case rightEar
    case neck
    case leftShoulder
    case rightShoulder
    case leftElbow
    case rightElbow
    case leftWrist
    case rightWrist
    case root
    case leftHip
    case rightHip
    case leftKnee
    case rightKnee
    case leftAnkle
    case rightAnkle

    init?(visionName: HumanBodyPoseObservation.JointName) {
        switch visionName {
        case .nose: self = .nose
        case .leftEye: self = .leftEye
        case .rightEye: self = .rightEye
        case .leftEar: self = .leftEar
        case .rightEar: self = .rightEar
        case .neck: self = .neck
        case .leftShoulder: self = .leftShoulder
        case .rightShoulder: self = .rightShoulder
        case .leftElbow: self = .leftElbow
        case .rightElbow: self = .rightElbow
        case .leftWrist: self = .leftWrist
        case .rightWrist: self = .rightWrist
        case .root: self = .root
        case .leftHip: self = .leftHip
        case .rightHip: self = .rightHip
        case .leftKnee: self = .leftKnee
        case .rightKnee: self = .rightKnee
        case .leftAnkle: self = .leftAnkle
        case .rightAnkle: self = .rightAnkle
        @unknown default: return nil
        }
    }

    var visionName: HumanBodyPoseObservation.JointName {
        switch self {
        case .nose: .nose
        case .leftEye: .leftEye
        case .rightEye: .rightEye
        case .leftEar: .leftEar
        case .rightEar: .rightEar
        case .neck: .neck
        case .leftShoulder: .leftShoulder
        case .rightShoulder: .rightShoulder
        case .leftElbow: .leftElbow
        case .rightElbow: .rightElbow
        case .leftWrist: .leftWrist
        case .rightWrist: .rightWrist
        case .root: .root
        case .leftHip: .leftHip
        case .rightHip: .rightHip
        case .leftKnee: .leftKnee
        case .rightKnee: .rightKnee
        case .leftAnkle: .leftAnkle
        case .rightAnkle: .rightAnkle
        }
    }
}

struct BodyPose: Equatable, Sendable {
    private var joints: [SIMD4<Float>]

    init(joints: [SIMD4<Float>] = Array(repeating: .zero, count: BodyJoint.allCases.count)) {
        precondition(joints.count == BodyJoint.allCases.count)
        self.joints = joints
    }

    subscript(joint: BodyJoint) -> SIMD4<Float> {
        get {
            joints[joint.rawValue]
        }
        set {
            joints[joint.rawValue] = newValue
        }
    }
}
