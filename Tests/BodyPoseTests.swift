import Vision
import XCTest
@testable import ShadeCam

final class BodyPoseTests: XCTestCase {
    func testCanonicalJointIndexMappingRoundTrips() {
        let expected: [HumanBodyPoseObservation.JointName] = [
            .nose,
            .leftEye,
            .rightEye,
            .leftEar,
            .rightEar,
            .neck,
            .leftShoulder,
            .rightShoulder,
            .leftElbow,
            .rightElbow,
            .leftWrist,
            .rightWrist,
            .root,
            .leftHip,
            .rightHip,
            .leftKnee,
            .rightKnee,
            .leftAnkle,
            .rightAnkle,
        ]

        XCTAssertEqual(BodyJoint.allCases.map(\.rawValue), Array(0...18))
        XCTAssertEqual(BodyJoint.allCases.map(\.visionName), expected)
        XCTAssertEqual(Set(expected).count, expected.count)
        XCTAssertEqual(expected.compactMap(BodyJoint.init(visionName:)), BodyJoint.allCases)
    }
}
