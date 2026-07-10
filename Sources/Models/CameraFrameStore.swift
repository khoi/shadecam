import CoreVideo
import Foundation

final class CameraFrameStore: @unchecked Sendable {
    private let lock = NSLock()
    private var frame: CVPixelBuffer?

    func update(_ frame: CVPixelBuffer) {
        lock.withLock {
            self.frame = frame
        }
    }

    func currentFrame() -> CVPixelBuffer? {
        lock.withLock {
            frame
        }
    }
}
