import Foundation

final class FaceRectStore: @unchecked Sendable {
    private let lock = NSLock()
    private var faceRect = SIMD4<Float>.zero

    func update(_ faceRect: SIMD4<Float>) {
        lock.withLock {
            self.faceRect = faceRect
        }
    }

    func current() -> SIMD4<Float> {
        lock.withLock {
            faceRect
        }
    }
}
