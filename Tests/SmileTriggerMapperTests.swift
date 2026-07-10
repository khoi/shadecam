import XCTest
@testable import ShadeCam

final class SmileTriggerMapperTests: XCTestCase {
    func testTriggersOnlyOnRisingEdge() {
        var mapper = SmileTriggerMapper()

        XCTAssertFalse(mapper.shouldTrigger(smile: 0.54, at: 0))
        XCTAssertTrue(mapper.shouldTrigger(smile: 0.55, at: 0.1))
        XCTAssertFalse(mapper.shouldTrigger(smile: 0.9, at: 0.2))
        XCTAssertFalse(mapper.shouldTrigger(smile: 0.4, at: 0.4))
    }

    func testRespectsHoldAndRefractoryDuration() {
        var mapper = SmileTriggerMapper()

        XCTAssertTrue(mapper.shouldTrigger(smile: 0.8, at: 0))
        XCTAssertFalse(mapper.shouldTrigger(smile: 0.2, at: 0.29))
        XCTAssertFalse(mapper.shouldTrigger(smile: 0.2, at: 0.3))
        XCTAssertFalse(mapper.shouldTrigger(smile: 0.8, at: 0.59))
        XCTAssertTrue(mapper.shouldTrigger(smile: 0.8, at: 0.6))
    }
}
