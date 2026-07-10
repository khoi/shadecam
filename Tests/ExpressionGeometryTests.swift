import XCTest
@testable import ShadeCam

final class ExpressionGeometryTests: XCTestCase {
    func testConvertsFaceLocalLandmarksIntoImageSpace() {
        let points = ExpressionLandmarkGeometry.points(
            [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)],
            in: CGRect(x: 0.25, y: 0.2, width: 0.5, height: 0.4),
            imageSize: CGSize(width: 200, height: 100)
        )

        XCTAssertEqual(points, [SIMD2(50, 80), SIMD2(150, 40)])
    }

    func testNeutralScoresAreZero() throws {
        let scores = try scores(for: landmarks())

        XCTAssertEqual(scores, ExpressionScores(smile: 0, frown: 0, surprise: 0, mouthOpen: 0))
    }

    func testMouthOpenScoreIsMonotonic() throws {
        XCTAssertEqual(try scores(for: landmarks(innerLipGap: 0.08)).mouthOpen, 0, accuracy: 0.001)
        XCTAssertEqual(try scores(for: landmarks(innerLipGap: 0.24)).mouthOpen, 0.5, accuracy: 0.001)
        XCTAssertEqual(try scores(for: landmarks(innerLipGap: 0.4)).mouthOpen, 1, accuracy: 0.001)
    }

    func testSmileScoreIsMonotonic() throws {
        XCTAssertEqual(try scores(for: landmarks()).smile, 0, accuracy: 0.001)
        XCTAssertEqual(
            try scores(for: landmarks(mouthWidth: 0.925, cornerOffset: -0.06)).smile,
            0.5,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try scores(for: landmarks(mouthWidth: 1.05, cornerOffset: -0.12)).smile,
            1,
            accuracy: 0.001
        )
    }

    func testFrownScoreIsMonotonic() throws {
        XCTAssertEqual(try scores(for: landmarks()).frown, 0, accuracy: 0.001)
        XCTAssertEqual(try scores(for: landmarks(cornerOffset: 0.06)).frown, 0.5, accuracy: 0.001)
        XCTAssertEqual(try scores(for: landmarks(cornerOffset: 0.12)).frown, 1, accuracy: 0.001)
    }

    func testSurpriseScoreIsMonotonic() throws {
        XCTAssertEqual(try scores(for: landmarks()).surprise, 0, accuracy: 0.001)
        XCTAssertEqual(
            try scores(for: landmarks(innerLipGap: 0.24, eyeHeight: 0.16, browRaise: 0.45)).surprise,
            0.5,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try scores(for: landmarks(innerLipGap: 0.4, eyeHeight: 0.2, browRaise: 0.55)).surprise,
            1,
            accuracy: 0.001
        )
    }

    func testInterocularNormalizationIsScaleInvariant() throws {
        let source = landmarks(
            mouthWidth: 0.9,
            cornerOffset: -0.04,
            innerLipGap: 0.2,
            eyeHeight: 0.15,
            browRaise: 0.42
        )
        let original = try XCTUnwrap(ExpressionGeometry.measure(source))
        let doubled = try XCTUnwrap(ExpressionGeometry.measure(source.scaled(by: 2)))

        XCTAssertEqual(original.mouthAspectRatio, doubled.mouthAspectRatio, accuracy: 0.001)
        XCTAssertEqual(original.mouthWidthRatio, doubled.mouthWidthRatio, accuracy: 0.001)
        XCTAssertEqual(original.mouthCornerLiftRatio, doubled.mouthCornerLiftRatio, accuracy: 0.001)
        XCTAssertEqual(original.browRaiseRatio, doubled.browRaiseRatio, accuracy: 0.001)
        XCTAssertEqual(original.eyeAspectRatio, doubled.eyeAspectRatio, accuracy: 0.001)
        XCTAssertEqual(ExpressionScorer().scores(for: original), ExpressionScorer().scores(for: doubled))
    }

    private func scores(for landmarks: ExpressionLandmarks) throws -> ExpressionScores {
        ExpressionScorer().scores(for: try XCTUnwrap(ExpressionGeometry.measure(landmarks)))
    }

    private func landmarks(
        mouthWidth: Float = 0.8,
        cornerOffset: Float = 0,
        innerLipGap: Float = 0.08,
        eyeHeight: Float = 0.12,
        browRaise: Float = 0.35
    ) -> ExpressionLandmarks {
        let eyeWidth: Float = 0.4
        let leftEyeCenter = SIMD2<Float>(-0.5, 0)
        let rightEyeCenter = SIMD2<Float>(0.5, 0)
        let mouthCenterY: Float = 0.7
        return ExpressionLandmarks(
            leftEye: ring(center: leftEyeCenter, width: eyeWidth, height: eyeHeight),
            rightEye: ring(center: rightEyeCenter, width: eyeWidth, height: eyeHeight),
            leftEyebrow: [SIMD2(leftEyeCenter.x, leftEyeCenter.y - browRaise)],
            rightEyebrow: [SIMD2(rightEyeCenter.x, rightEyeCenter.y - browRaise)],
            outerLips: [
                SIMD2(-mouthWidth / 2, mouthCenterY + cornerOffset),
                SIMD2(0, mouthCenterY - 0.1),
                SIMD2(mouthWidth / 2, mouthCenterY + cornerOffset),
                SIMD2(0, mouthCenterY + 0.1),
            ],
            innerLips: [
                SIMD2(-mouthWidth * 0.25, mouthCenterY),
                SIMD2(0, mouthCenterY - innerLipGap / 2),
                SIMD2(mouthWidth * 0.25, mouthCenterY),
                SIMD2(0, mouthCenterY + innerLipGap / 2),
            ]
        )
    }

    private func ring(
        center: SIMD2<Float>,
        width: Float,
        height: Float
    ) -> [SIMD2<Float>] {
        [
            SIMD2(center.x - width / 2, center.y),
            SIMD2(center.x, center.y - height / 2),
            SIMD2(center.x + width / 2, center.y),
            SIMD2(center.x, center.y + height / 2),
        ]
    }
}
