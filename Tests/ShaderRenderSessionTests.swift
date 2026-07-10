import XCTest
@testable import ShadeCam

final class ShaderRenderSessionTests: XCTestCase {
    func testGenerationChangeResetsClockFrameAndFeedback() {
        var session = ShaderRenderSession()

        let first = session.beginFrame(generation: 4, at: 10)

        XCTAssertTrue(first.shouldClearFeedback)
        XCTAssertEqual(first.effectTime, 0)
        XCTAssertEqual(first.timeDelta, 0)
        XCTAssertEqual(first.frameIndex, 0)
        XCTAssertEqual(first.feedbackReadIndex, 0)
        XCTAssertEqual(first.feedbackWriteIndex, 1)
        session.completeFrame(first)

        let second = session.beginFrame(generation: 4, at: 10.25)

        XCTAssertFalse(second.shouldClearFeedback)
        XCTAssertEqual(second.effectTime, 0.25, accuracy: 0.0001)
        XCTAssertEqual(second.timeDelta, 0.25, accuracy: 0.0001)
        XCTAssertEqual(second.frameIndex, 1)
        XCTAssertEqual(second.feedbackReadIndex, 1)
        XCTAssertEqual(second.feedbackWriteIndex, 0)
        session.completeFrame(second)

        let replacement = session.beginFrame(generation: 5, at: 12)

        XCTAssertTrue(replacement.shouldClearFeedback)
        XCTAssertEqual(replacement.effectTime, 0)
        XCTAssertEqual(replacement.timeDelta, 0)
        XCTAssertEqual(replacement.frameIndex, 0)
        XCTAssertEqual(replacement.feedbackReadIndex, 0)
        XCTAssertEqual(replacement.feedbackWriteIndex, 1)
    }

    func testFeedbackResetPreservesClockAndFrame() {
        var session = ShaderRenderSession()
        let first = session.beginFrame(generation: 2, at: 8)
        session.completeFrame(first)
        session.resetFeedback()

        let resized = session.beginFrame(generation: 2, at: 8.5)

        XCTAssertFalse(resized.shouldClearFeedback)
        XCTAssertEqual(resized.effectTime, 0.5, accuracy: 0.0001)
        XCTAssertEqual(resized.timeDelta, 0.5, accuracy: 0.0001)
        XCTAssertEqual(resized.frameIndex, 1)
        XCTAssertEqual(resized.feedbackReadIndex, 0)
        XCTAssertEqual(resized.feedbackWriteIndex, 1)
    }
}
