import Foundation

struct ExpressionCalibrationStore {
    private static let key = "expression.neutralBaseline"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> ExpressionBaseline? {
        guard let data = defaults.data(forKey: Self.key) else {
            return nil
        }
        return try? JSONDecoder().decode(ExpressionBaseline.self, from: data)
    }

    func save(_ baseline: ExpressionBaseline) {
        defaults.set(try? JSONEncoder().encode(baseline), forKey: Self.key)
    }
}

struct ExpressionScoreTracker: Sendable {
    static let maximumPoseAngle = 25.0

    private(set) var baseline: ExpressionBaseline
    private(set) var scores = ExpressionScores(smile: 0, frown: 0, surprise: 0, mouthOpen: 0)
    private var latestGeometry: ExpressionRawGeometry?

    init(baseline: ExpressionBaseline = .default) {
        self.baseline = baseline
    }

    mutating func update(
        _ geometry: ExpressionRawGeometry,
        yawDegrees: Double,
        pitchDegrees: Double
    ) -> ExpressionScores {
        guard
            abs(yawDegrees) <= Self.maximumPoseAngle,
            abs(pitchDegrees) <= Self.maximumPoseAngle
        else {
            return scores
        }
        latestGeometry = geometry
        scores = ExpressionScorer(baseline: baseline).scores(for: geometry)
        return scores
    }

    mutating func calibrate() -> ExpressionBaseline? {
        guard let latestGeometry else {
            return nil
        }
        let baseline = ExpressionBaseline(latestGeometry)
        self.baseline = baseline
        scores = ExpressionScorer(baseline: baseline).scores(for: latestGeometry)
        return baseline
    }
}
