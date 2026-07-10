import XCTest
@testable import ShadeCam

final class DepthTests: XCTestCase {
    func testFirstRangeInitializesWithoutSmoothing() {
        var normalizer = DepthNormalizer()

        normalizer.update(with: DepthRange(minimum: 2, maximum: 8))

        XCTAssertEqual(normalizer.range, DepthRange(minimum: 2, maximum: 8))
    }

    func testRangeEndpointsUseExponentialMovingAverage() throws {
        var normalizer = DepthNormalizer()
        normalizer.update(with: DepthRange(minimum: 0, maximum: 10))

        normalizer.update(with: DepthRange(minimum: 10, maximum: 30))

        let range = try XCTUnwrap(normalizer.range)
        XCTAssertEqual(range.minimum, 1, accuracy: 0.0001)
        XCTAssertEqual(range.maximum, 12, accuracy: 0.0001)
    }

    func testFlatRangeNormalizesToFiniteZero() {
        let value = DepthRange(minimum: 4, maximum: 4).normalize(4)

        XCTAssertEqual(value, 0)
        XCTAssertTrue(value.isFinite)
    }

    func testNormalizedDepthClampsToUnitRange() {
        let range = DepthRange(minimum: 2, maximum: 6)

        XCTAssertEqual(range.normalize(0), 0)
        XCTAssertEqual(range.normalize(4), 0.5)
        XCTAssertEqual(range.normalize(8), 1)
    }

    func testDepthNeedGatesProducer() {
        XCTAssertTrue(DepthService.isEnabled(for: [.depth]))
        XCTAssertFalse(DepthService.isEnabled(for: []))
        XCTAssertFalse(DepthService.isEnabled(for: [.body, .mask]))
    }
}
