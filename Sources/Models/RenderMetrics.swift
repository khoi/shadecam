import Foundation

final class RenderMetrics: @unchecked Sendable {
    private let lock = NSLock()
    private var intervalStart = ProcessInfo.processInfo.systemUptime
    private var lastFrameTime = ProcessInfo.processInfo.systemUptime
    private var frameCount = 0
    private var framesPerSecond = 0.0

    func recordFrame() {
        lock.withLock {
            let now = ProcessInfo.processInfo.systemUptime
            lastFrameTime = now
            frameCount += 1
            let duration = now - intervalStart
            if duration >= 0.5 {
                framesPerSecond = Double(frameCount) / duration
                frameCount = 0
                intervalStart = now
            }
        }
    }

    func currentFramesPerSecond() -> Double {
        lock.withLock {
            ProcessInfo.processInfo.systemUptime - lastFrameTime > 1 ? 0 : framesPerSecond
        }
    }
}
