import XCTest
@testable import ShadeCam

final class SignalFiltersTests: XCTestCase {
    func testOneEuroSmoothsAndConverges() {
        var filter = OneEuroFilter(
            configuration: .init(minimumCutoff: 1, speedCoefficient: 0, derivativeCutoff: 1)
        )

        XCTAssertEqual(filter.filter(0, at: 0), 0)
        let firstStep = filter.filter(1, at: 0.01)
        XCTAssertGreaterThan(firstStep, 0)
        XCTAssertLessThan(firstStep, 1)

        var value = firstStep
        for frame in 2...300 {
            value = filter.filter(1, at: Double(frame) / 100)
        }
        XCTAssertEqual(value, 1, accuracy: 0.001)
    }

    func testHysteresisRespectsThresholdsAndHoldDuration() {
        var latch = HysteresisLatch(
            configuration: .init(onThreshold: 0.7, offThreshold: 0.3, minimumHoldDuration: 0.5)
        )

        XCTAssertTrue(latch.update(0.8, at: 0))
        XCTAssertTrue(latch.update(0.1, at: 0.49))
        XCTAssertFalse(latch.update(0.1, at: 0.5))
        XCTAssertFalse(latch.update(0.9, at: 0.99))
        XCTAssertTrue(latch.update(0.9, at: 1))
    }

    func testEventEnvelopeAttackAndRelease() {
        var envelope = EventEnvelope(
            configuration: .init(attackDuration: 0.05, releaseDuration: 2)
        )

        XCTAssertEqual(envelope.value(at: 1), 0)
        XCTAssertEqual(envelope.timeSinceTrigger(at: 1), -1)

        envelope.trigger(at: 1, position: SIMD2(0.25, 0.75))

        XCTAssertEqual(envelope.value(at: 1), 0)
        XCTAssertEqual(envelope.value(at: 1.025), 0.5, accuracy: 0.001)
        XCTAssertEqual(envelope.value(at: 1.05), 1, accuracy: 0.001)
        XCTAssertEqual(envelope.value(at: 3.05), 0.01, accuracy: 0.001)
        XCTAssertEqual(envelope.timeSinceTrigger(at: 3.05), 2.05, accuracy: 0.001)
        XCTAssertEqual(envelope.triggerPosition, SIMD2(0.25, 0.75))
    }
}
