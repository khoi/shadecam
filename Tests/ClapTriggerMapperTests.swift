import XCTest
@testable import ShadeCam

final class ClapTriggerMapperTests: XCTestCase {
    func testTriggersOnlyForConfidentClapping() {
        var mapper = ClapTriggerMapper()

        XCTAssertFalse(mapper.shouldTrigger(
            classifications: [SoundClassification(identifier: "applause", confidence: 1)],
            at: 0
        ))
        XCTAssertFalse(mapper.shouldTrigger(
            classifications: [SoundClassification(identifier: "clapping", confidence: 0.69)],
            at: 0
        ))
        XCTAssertTrue(mapper.shouldTrigger(
            classifications: [SoundClassification(identifier: "clapping", confidence: 0.7)],
            at: 0
        ))
    }

    func testSuppressesTriggersDuringRefractoryPeriod() {
        var mapper = ClapTriggerMapper(refractoryDuration: 0.5)
        let clap = [SoundClassification(identifier: "clapping", confidence: 1)]

        XCTAssertTrue(mapper.shouldTrigger(classifications: clap, at: 1))
        XCTAssertFalse(mapper.shouldTrigger(classifications: clap, at: 1.49))
        XCTAssertTrue(mapper.shouldTrigger(classifications: clap, at: 1.5))
    }
}
