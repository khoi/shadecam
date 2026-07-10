import CoreVideo
import Foundation

struct SendablePixelBuffer: @unchecked Sendable {
    let value: CVPixelBuffer
}

final class PixelBufferStore: @unchecked Sendable {
    private let lock = NSLock()
    private var pixelBuffer: CVPixelBuffer?

    func update(_ pixelBuffer: CVPixelBuffer) {
        lock.withLock {
            self.pixelBuffer = pixelBuffer
        }
    }

    func current() -> CVPixelBuffer? {
        lock.withLock {
            pixelBuffer
        }
    }
}
