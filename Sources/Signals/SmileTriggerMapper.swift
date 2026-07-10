import Foundation

struct SmileTriggerMapper: Sendable {
    private var latch = HysteresisLatch(
        configuration: .init(
            onThreshold: 0.55,
            offThreshold: 0.35,
            minimumHoldDuration: 0.3
        )
    )

    mutating func shouldTrigger(smile: Float, at timestamp: TimeInterval) -> Bool {
        let wasOn = latch.isOn
        let isOn = latch.update(smile, at: timestamp)
        return isOn && !wasOn
    }
}
