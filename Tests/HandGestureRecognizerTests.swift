import XCTest
@testable import ShadeCam

final class HandGestureRecognizerTests: XCTestCase {
    func testPinchTriggersOnRisingEdgeAtMidpoint() {
        var recognizer = PinchGestureRecognizer()

        XCTAssertNil(recognizer.update(pinchPose(distance: 0.5), at: 0))
        XCTAssertEqual(
            recognizer.update(pinchPose(distance: 0.2), at: 0.1),
            SIMD2<Float>(0.5, 0.5)
        )
        XCTAssertNil(recognizer.update(pinchPose(distance: 0.5), at: 0.2))
        XCTAssertNil(recognizer.update(pinchPose(distance: 0.2), at: 0.3))
        XCTAssertNil(recognizer.update(pinchPose(distance: 0.5), at: 0.31))
        XCTAssertNil(recognizer.update(pinchPose(distance: 0.2), at: 0.4))
        XCTAssertEqual(
            recognizer.update(pinchPose(distance: 0.2), at: 0.47),
            SIMD2<Float>(0.5, 0.5)
        )
    }

    func testPinchRejectsAmbiguousDistanceAndLowConfidence() {
        var recognizer = PinchGestureRecognizer()

        XCTAssertNil(recognizer.update(pinchPose(distance: 0.3), at: 0))
        XCTAssertNil(recognizer.update(pinchPose(distance: 0.2, confidence: 0.4), at: 0.2))
    }

    func testWaveTriggersAfterThreeQualifiedReversals() {
        var recognizer = WaveGestureRecognizer()
        let samples: [(TimeInterval, Float)] = [
            (0, 0.3),
            (0.1, 0.36),
            (0.2, 0.29),
            (0.3, 0.36),
            (0.4, 0.29),
            (0.5, 0.36),
            (0.6, 0.29),
            (0.7, 0.36),
        ]

        let results = samples.map { timestamp, x in
            recognizer.update(wavePose(x: x), at: timestamp)
        }

        XCTAssertEqual(results.compactMap { $0 }, [SIMD2<Float>(0.29, 0.6)])
    }

    func testWaveRejectsSmallAndSlowReversals() {
        var recognizer = WaveGestureRecognizer()
        let samples: [(TimeInterval, Float)] = [
            (0, 0.3),
            (0.5, 0.33),
            (1, 0.3),
            (1.5, 0.36),
            (2, 0.29),
            (2.5, 0.36),
        ]

        XCTAssertTrue(samples.allSatisfy { timestamp, x in
            recognizer.update(wavePose(x: x), at: timestamp) == nil
        })
    }

    func testPushTriggersOnRapidSpanGrowthAtPalmCenter() {
        var recognizer = PushGestureRecognizer()

        XCTAssertNil(recognizer.update(pushPose(span: 0.2), at: 0))
        XCTAssertEqual(
            recognizer.update(pushPose(span: 0.28), at: 0.3),
            SIMD2<Float>(0.5, 0.55)
        )
        XCTAssertNil(recognizer.update(pushPose(span: 0.2), at: 0.4))
        XCTAssertNil(recognizer.update(pushPose(span: 0.3), at: 0.6))
    }

    func testPushRejectsInsufficientAndSlowGrowth() {
        var recognizer = PushGestureRecognizer()

        XCTAssertNil(recognizer.update(pushPose(span: 0.2), at: 0))
        XCTAssertNil(recognizer.update(pushPose(span: 0.26), at: 0.3))
        XCTAssertNil(recognizer.update(pushPose(span: 0.36), at: 0.8))
    }

    private func pinchPose(distance: Float, confidence: Float = 1) -> HandPose {
        let span: Float = 0.2
        var pose = HandPose()
        pose[.wrist] = joint(x: 0.5, y: 0.7, confidence: confidence)
        pose[.middleMCP] = joint(x: 0.5, y: 0.5, confidence: confidence)
        pose[.thumbTip] = joint(
            x: 0.5 - distance * span / 2,
            y: 0.5,
            confidence: confidence
        )
        pose[.indexTip] = joint(
            x: 0.5 + distance * span / 2,
            y: 0.5,
            confidence: confidence
        )
        return pose
    }

    private func wavePose(x: Float) -> HandPose {
        var pose = HandPose()
        pose[.wrist] = joint(x: x, y: 0.6)
        return pose
    }

    private func pushPose(span: Float) -> HandPose {
        var pose = HandPose()
        pose[.indexTip] = joint(x: 0.5 - span / 2, y: 0.5)
        pose[.littleTip] = joint(x: 0.5 + span / 2, y: 0.5)
        pose[.indexMCP] = joint(x: 0.44, y: 0.55)
        pose[.middleMCP] = joint(x: 0.48, y: 0.55)
        pose[.ringMCP] = joint(x: 0.52, y: 0.55)
        pose[.littleMCP] = joint(x: 0.56, y: 0.55)
        return pose
    }

    private func joint(x: Float, y: Float, confidence: Float = 1) -> SIMD4<Float> {
        SIMD4(x, y, confidence, 0)
    }
}
