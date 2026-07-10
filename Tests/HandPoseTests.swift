import Vision
import XCTest
@testable import ShadeCam

final class HandPoseTests: XCTestCase {
    func testCanonicalJointIndexMapping() {
        let expected: [HumanHandPoseObservation.JointName] = [
            .wrist,
            .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
            .indexMCP, .indexPIP, .indexDIP, .indexTip,
            .middleMCP, .middlePIP, .middleDIP, .middleTip,
            .ringMCP, .ringPIP, .ringDIP, .ringTip,
            .littleMCP, .littlePIP, .littleDIP, .littleTip,
        ]

        XCTAssertEqual(HandJoint.allCases.map(\.rawValue), Array(0...20))
        XCTAssertEqual(HandJoint.allCases.map(\.visionName), expected)
    }
}
