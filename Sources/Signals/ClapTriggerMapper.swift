import Foundation

struct SoundClassification: Equatable, Sendable {
    let identifier: String
    let confidence: Double
}

struct ClapTriggerMapper: Sendable {
    let confidenceThreshold: Double
    let refractoryDuration: TimeInterval
    private var lastTriggerTimestamp: TimeInterval?

    init(confidenceThreshold: Double = 0.7, refractoryDuration: TimeInterval = 0.5) {
        precondition((0...1).contains(confidenceThreshold))
        precondition(refractoryDuration >= 0)
        self.confidenceThreshold = confidenceThreshold
        self.refractoryDuration = refractoryDuration
    }

    mutating func shouldTrigger(
        classifications: [SoundClassification],
        at timestamp: TimeInterval
    ) -> Bool {
        guard classifications.contains(where: {
            $0.identifier == "clapping" && $0.confidence >= confidenceThreshold
        }) else {
            return false
        }
        guard lastTriggerTimestamp.map({ timestamp - $0 >= refractoryDuration }) ?? true else {
            return false
        }
        lastTriggerTimestamp = timestamp
        return true
    }
}
