import CoreGraphics
import simd

struct ExpressionLandmarks: Equatable, Sendable {
    let leftEye: [SIMD2<Float>]
    let rightEye: [SIMD2<Float>]
    let leftEyebrow: [SIMD2<Float>]
    let rightEyebrow: [SIMD2<Float>]
    let outerLips: [SIMD2<Float>]
    let innerLips: [SIMD2<Float>]

    func scaled(by scale: Float) -> Self {
        Self(
            leftEye: leftEye.map { $0 * scale },
            rightEye: rightEye.map { $0 * scale },
            leftEyebrow: leftEyebrow.map { $0 * scale },
            rightEyebrow: rightEyebrow.map { $0 * scale },
            outerLips: outerLips.map { $0 * scale },
            innerLips: innerLips.map { $0 * scale }
        )
    }
}

enum ExpressionLandmarkGeometry {
    static func points(
        _ points: [CGPoint],
        in faceBoundingBox: CGRect,
        imageSize: CGSize
    ) -> [SIMD2<Float>] {
        points.map { point in
            SIMD2(
                Float((faceBoundingBox.minX + point.x * faceBoundingBox.width) * imageSize.width),
                Float((1 - faceBoundingBox.minY - point.y * faceBoundingBox.height) * imageSize.height)
            )
        }
    }
}

struct ExpressionRawGeometry: Codable, Equatable, Sendable {
    let mouthAspectRatio: Float
    let mouthWidthRatio: Float
    let mouthCornerLiftRatio: Float
    let browRaiseRatio: Float
    let eyeAspectRatio: Float
}

struct ExpressionScores: Equatable, Sendable {
    let smile: Float
    let frown: Float
    let surprise: Float
    let mouthOpen: Float

    var vector: SIMD4<Float> {
        SIMD4(smile, frown, surprise, mouthOpen)
    }
}

struct ExpressionBaseline: Codable, Equatable, Sendable {
    static let `default` = Self(
        mouthAspectRatio: 0.1,
        mouthWidthRatio: 0.8,
        mouthCornerLiftRatio: 0,
        browRaiseRatio: 0.35,
        eyeAspectRatio: 0.3
    )

    let mouthAspectRatio: Float
    let mouthWidthRatio: Float
    let mouthCornerLiftRatio: Float
    let browRaiseRatio: Float
    let eyeAspectRatio: Float

    init(_ geometry: ExpressionRawGeometry) {
        self.init(
            mouthAspectRatio: geometry.mouthAspectRatio,
            mouthWidthRatio: geometry.mouthWidthRatio,
            mouthCornerLiftRatio: geometry.mouthCornerLiftRatio,
            browRaiseRatio: geometry.browRaiseRatio,
            eyeAspectRatio: geometry.eyeAspectRatio
        )
    }

    init(
        mouthAspectRatio: Float,
        mouthWidthRatio: Float,
        mouthCornerLiftRatio: Float,
        browRaiseRatio: Float,
        eyeAspectRatio: Float
    ) {
        self.mouthAspectRatio = mouthAspectRatio
        self.mouthWidthRatio = mouthWidthRatio
        self.mouthCornerLiftRatio = mouthCornerLiftRatio
        self.browRaiseRatio = browRaiseRatio
        self.eyeAspectRatio = eyeAspectRatio
    }
}

enum ExpressionGeometry {
    static func measure(_ landmarks: ExpressionLandmarks) -> ExpressionRawGeometry? {
        guard
            landmarks.leftEye.count >= 2,
            landmarks.rightEye.count >= 2,
            !landmarks.leftEyebrow.isEmpty,
            !landmarks.rightEyebrow.isEmpty,
            landmarks.outerLips.count >= 4,
            landmarks.innerLips.count >= 2
        else {
            return nil
        }

        let leftEyeCenter = center(of: landmarks.leftEye)
        let rightEyeCenter = center(of: landmarks.rightEye)
        let interocularDistance = distance(leftEyeCenter, rightEyeCenter)
        guard interocularDistance > .leastNonzeroMagnitude else {
            return nil
        }

        let leftCorner = landmarks.outerLips.min { $0.x < $1.x }!
        let rightCorner = landmarks.outerLips.max { $0.x < $1.x }!
        let mouthWidth = distance(leftCorner, rightCorner)
        guard mouthWidth > .leastNonzeroMagnitude else {
            return nil
        }

        let mouthCenterX = (leftCorner.x + rightCorner.x) / 2
        let lipCenterY = landmarks.outerLips
            .sorted { abs($0.x - mouthCenterX) < abs($1.x - mouthCenterX) }
            .prefix(2)
            .reduce(0) { $0 + $1.y } / 2
        let cornerY = (leftCorner.y + rightCorner.y) / 2
        let innerLipGap = verticalSpan(of: landmarks.innerLips)
        let browRaise = (
            distance(center(of: landmarks.leftEyebrow), leftEyeCenter)
                + distance(center(of: landmarks.rightEyebrow), rightEyeCenter)
        ) / 2
        let eyeAspectRatio = (
            aspectRatio(of: landmarks.leftEye) + aspectRatio(of: landmarks.rightEye)
        ) / 2

        return ExpressionRawGeometry(
            mouthAspectRatio: innerLipGap / mouthWidth,
            mouthWidthRatio: mouthWidth / interocularDistance,
            mouthCornerLiftRatio: (lipCenterY - cornerY) / interocularDistance,
            browRaiseRatio: browRaise / interocularDistance,
            eyeAspectRatio: eyeAspectRatio
        )
    }

    private static func center(of points: [SIMD2<Float>]) -> SIMD2<Float> {
        points.reduce(.zero, +) / Float(points.count)
    }

    private static func verticalSpan(of points: [SIMD2<Float>]) -> Float {
        points.map(\.y).max()! - points.map(\.y).min()!
    }

    private static func aspectRatio(of points: [SIMD2<Float>]) -> Float {
        let horizontal = points.map(\.x).max()! - points.map(\.x).min()!
        guard horizontal > .leastNonzeroMagnitude else {
            return 0
        }
        return verticalSpan(of: points) / horizontal
    }
}

struct ExpressionScorer: Sendable {
    let baseline: ExpressionBaseline

    init(baseline: ExpressionBaseline = .default) {
        self.baseline = baseline
    }

    func scores(for geometry: ExpressionRawGeometry) -> ExpressionScores {
        let mouthOpen = normalizedDelta(
            geometry.mouthAspectRatio - baseline.mouthAspectRatio,
            range: 0.4
        )
        let widthIncrease = normalizedDelta(
            geometry.mouthWidthRatio - baseline.mouthWidthRatio,
            range: 0.25
        )
        let cornerLift = normalizedDelta(
            geometry.mouthCornerLiftRatio - baseline.mouthCornerLiftRatio,
            range: 0.12
        )
        let frown = normalizedDelta(
            baseline.mouthCornerLiftRatio - geometry.mouthCornerLiftRatio,
            range: 0.12
        )
        let browRaise = normalizedDelta(
            geometry.browRaiseRatio - baseline.browRaiseRatio,
            range: 0.2
        )
        let wideEyes = normalizedDelta(
            geometry.eyeAspectRatio - baseline.eyeAspectRatio,
            range: 0.2
        )

        return ExpressionScores(
            smile: (widthIncrease + cornerLift) / 2,
            frown: frown,
            surprise: (browRaise + wideEyes + mouthOpen) / 3,
            mouthOpen: mouthOpen
        )
    }

    private func normalizedDelta(_ delta: Float, range: Float) -> Float {
        guard delta > 0.001 else {
            return 0
        }
        return min(max(delta / range, 0), 1)
    }
}
