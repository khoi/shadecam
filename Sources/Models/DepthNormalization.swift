import Foundation

struct DepthRange: Equatable, Sendable {
    let minimum: Float
    let maximum: Float

    func smoothed(toward next: Self, alpha: Float) -> Self {
        let weight = min(max(alpha, 0), 1)
        return Self(
            minimum: minimum + (next.minimum - minimum) * weight,
            maximum: maximum + (next.maximum - maximum) * weight
        )
    }

    func normalize(_ value: Float) -> Float {
        let width = maximum - minimum
        guard value.isFinite, minimum.isFinite, maximum.isFinite, width > Float.ulpOfOne else {
            return 0
        }
        return min(max((value - minimum) / width, 0), 1)
    }
}

struct DepthNormalizer: Sendable {
    private static let smoothingAlpha: Float = 0.1
    private(set) var range: DepthRange?

    mutating func update(with current: DepthRange) {
        range = range?.smoothed(toward: current, alpha: Self.smoothingAlpha) ?? current
    }

    mutating func reset() {
        range = nil
    }
}
