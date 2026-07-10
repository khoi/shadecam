import CoreGraphics
import Observation

@Observable
final class CameraFrameDimensions: @unchecked Sendable {
    private(set) var size: CGSize?

    var aspectRatio: CGFloat? {
        guard let size, size.height > 0 else {
            return nil
        }
        return size.width / size.height
    }

    @MainActor
    func update(width: Int, height: Int) {
        size = CGSize(width: CGFloat(width), height: CGFloat(height))
    }
}
