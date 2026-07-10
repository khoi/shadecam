import Foundation

final class RenderControl: @unchecked Sendable {
    private let lock = NSLock()
    private var mouse = SIMD4<Float>.zero
    private var shouldCapturePlate = false

    func beginDrag(at point: SIMD2<Float>) {
        lock.withLock {
            mouse = SIMD4(point.x, point.y, point.x, point.y)
        }
    }

    func drag(to point: SIMD2<Float>) {
        lock.withLock {
            mouse.x = point.x
            mouse.y = point.y
        }
    }

    func currentMouse() -> SIMD4<Float> {
        lock.withLock {
            mouse
        }
    }

    func requestPlateCapture() {
        lock.withLock {
            shouldCapturePlate = true
        }
    }

    func consumePlateCaptureRequest() -> Bool {
        lock.withLock {
            defer {
                shouldCapturePlate = false
            }
            return shouldCapturePlate
        }
    }
}
