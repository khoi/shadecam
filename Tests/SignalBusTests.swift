import XCTest
@testable import ShadeCam

final class SignalBusTests: XCTestCase {
    func testRoutesFilteredValuesAndEventsIntoOneSnapshot() {
        let bus = SignalBus.standard

        bus.write(SIMD4(0, 0, 0, 0), to: SignalNames.faceRect, at: 0)
        bus.write(SIMD4(1, 1, 1, 1), to: SignalNames.faceRect, at: 0.01)
        bus.write(SIMD4(0.1, 0.2, 0.3, 0.4), to: SignalNames.expression, at: 0)
        bus.trigger(SignalNames.smileEvent, at: 1, position: SIMD2(0.6, 0.4))
        bus.trigger(SignalNames.debugEvent, at: 1, position: SIMD2(0.25, 0.75))

        let snapshot = bus.snapshot(at: 1.05)

        XCTAssertGreaterThan(snapshot.faceRect.x, 0)
        XCTAssertLessThan(snapshot.faceRect.x, 1)
        XCTAssertEqual(snapshot.expression, SIMD4(0.1, 0.2, 0.3, 0.4))
        XCTAssertEqual(snapshot.audio, .zero)
        XCTAssertEqual(snapshot.events[4].x, 1, accuracy: 0.001)
        XCTAssertEqual(snapshot.events[4].y, 0.05, accuracy: 0.001)
        XCTAssertEqual(snapshot.events[4].z, 0.6)
        XCTAssertEqual(snapshot.events[4].w, 0.4)
        XCTAssertEqual(snapshot.events[7].x, 1, accuracy: 0.001)
        XCTAssertEqual(snapshot.events[7].y, 0.05, accuracy: 0.001)
        XCTAssertEqual(snapshot.events[7].z, 0.25)
        XCTAssertEqual(snapshot.events[7].w, 0.75)
        XCTAssertEqual(snapshot.values.count, 53)
        XCTAssertEqual(snapshot.values[SignalNames.debugEvent], snapshot.events[7])
    }

    func testRoutesHandJoints() {
        let bus = SignalBus.standard
        let value = SIMD4<Float>(0.2, 0.3, 0.9, 0)

        bus.write(value, to: SignalNames.hand(1, HandJoint.indexMCP.rawValue), at: 0)

        let snapshot = bus.snapshot(at: 0)
        XCTAssertEqual(snapshot.hands[1, HandJoint.indexMCP.rawValue], value)
    }
}
