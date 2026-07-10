import Foundation

struct ShaderRenderFrame: Equatable, Sendable {
    let generation: UInt64
    let timestamp: TimeInterval
    let effectTime: TimeInterval
    let timeDelta: TimeInterval
    let frameIndex: UInt32
    let feedbackReadIndex: Int
    let feedbackWriteIndex: Int
    let shouldClearFeedback: Bool
}

struct ShaderRenderSession: Sendable {
    private var generation: UInt64?
    private var effectStartTime: TimeInterval = 0
    private var previousFrameTime: TimeInterval?
    private var frameIndex: UInt32 = 0
    private var feedbackReadIndex = 0

    mutating func beginFrame(generation: UInt64, at timestamp: TimeInterval) -> ShaderRenderFrame {
        let shouldReset = self.generation != generation
        if shouldReset {
            self.generation = generation
            effectStartTime = timestamp
            previousFrameTime = nil
            frameIndex = 0
            feedbackReadIndex = 0
        }
        return ShaderRenderFrame(
            generation: generation,
            timestamp: timestamp,
            effectTime: max(timestamp - effectStartTime, 0),
            timeDelta: max(previousFrameTime.map { timestamp - $0 } ?? 0, 0),
            frameIndex: frameIndex,
            feedbackReadIndex: feedbackReadIndex,
            feedbackWriteIndex: 1 - feedbackReadIndex,
            shouldClearFeedback: shouldReset
        )
    }

    mutating func completeFrame(_ frame: ShaderRenderFrame) {
        precondition(generation == frame.generation)
        precondition(frameIndex == frame.frameIndex)
        previousFrameTime = frame.timestamp
        frameIndex &+= 1
        feedbackReadIndex = frame.feedbackWriteIndex
    }

    mutating func resetFeedback() {
        feedbackReadIndex = 0
    }
}
