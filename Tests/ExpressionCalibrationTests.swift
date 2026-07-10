import Foundation
import XCTest
@testable import ShadeCam

final class ExpressionCalibrationTests: XCTestCase {
    func testCalibrationMakesCurrentGeometryNeutralAndMeasuresDeltas() throws {
        var tracker = ExpressionScoreTracker()
        let neutral = geometry(
            mouthAspectRatio: 0.2,
            mouthWidthRatio: 0.9,
            mouthCornerLiftRatio: 0.05,
            browRaiseRatio: 0.4,
            eyeAspectRatio: 0.35
        )

        XCTAssertGreaterThan(tracker.update(neutral, yawDegrees: 0, pitchDegrees: 0).smile, 0)
        XCTAssertEqual(tracker.calibrate(), ExpressionBaseline(neutral))
        XCTAssertEqual(
            tracker.update(neutral, yawDegrees: 0, pitchDegrees: 0),
            ExpressionScores(smile: 0, frown: 0, surprise: 0, mouthOpen: 0)
        )

        let expressive = geometry(
            mouthAspectRatio: 0.4,
            mouthWidthRatio: 1,
            mouthCornerLiftRatio: 0.11,
            browRaiseRatio: 0.5,
            eyeAspectRatio: 0.45
        )
        let scores = tracker.update(expressive, yawDegrees: 0, pitchDegrees: 0)

        XCTAssertGreaterThan(scores.smile, 0)
        XCTAssertGreaterThan(scores.surprise, 0)
        XCTAssertGreaterThan(scores.mouthOpen, 0)
    }

    func testCalibrationPersists() throws {
        let suiteName = "ExpressionCalibrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let baseline = ExpressionBaseline(
            geometry(
                mouthAspectRatio: 0.2,
                mouthWidthRatio: 0.9,
                mouthCornerLiftRatio: 0.05,
                browRaiseRatio: 0.4,
                eyeAspectRatio: 0.35
            )
        )

        ExpressionCalibrationStore(defaults: defaults).save(baseline)

        XCTAssertEqual(ExpressionCalibrationStore(defaults: defaults).load(), baseline)
    }

    func testPoseGatingHoldsLastValidScores() {
        var tracker = ExpressionScoreTracker()
        let expressive = geometry(
            mouthAspectRatio: 0.5,
            mouthWidthRatio: 1.05,
            mouthCornerLiftRatio: 0.12,
            browRaiseRatio: 0.55,
            eyeAspectRatio: 0.5
        )
        let held = tracker.update(expressive, yawDegrees: 0, pitchDegrees: 0)

        XCTAssertEqual(tracker.update(.neutral, yawDegrees: 26, pitchDegrees: 0), held)
        XCTAssertEqual(tracker.update(.neutral, yawDegrees: 0, pitchDegrees: -26), held)
        XCTAssertEqual(
            tracker.update(.neutral, yawDegrees: 25, pitchDegrees: -25),
            ExpressionScores(smile: 0, frown: 0, surprise: 0, mouthOpen: 0)
        )
    }

    private func geometry(
        mouthAspectRatio: Float,
        mouthWidthRatio: Float,
        mouthCornerLiftRatio: Float,
        browRaiseRatio: Float,
        eyeAspectRatio: Float
    ) -> ExpressionRawGeometry {
        ExpressionRawGeometry(
            mouthAspectRatio: mouthAspectRatio,
            mouthWidthRatio: mouthWidthRatio,
            mouthCornerLiftRatio: mouthCornerLiftRatio,
            browRaiseRatio: browRaiseRatio,
            eyeAspectRatio: eyeAspectRatio
        )
    }
}

private extension ExpressionRawGeometry {
    static let neutral = Self(
        mouthAspectRatio: 0.1,
        mouthWidthRatio: 0.8,
        mouthCornerLiftRatio: 0,
        browRaiseRatio: 0.35,
        eyeAspectRatio: 0.3
    )
}
