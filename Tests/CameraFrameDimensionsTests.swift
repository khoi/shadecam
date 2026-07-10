import XCTest
@testable import ShadeCam

final class CameraFrameDimensionsTests: XCTestCase {
    @MainActor
    func testAspectRatioDerivesFromCapturedDimensions() {
        let dimensions = CameraFrameDimensions()

        XCTAssertNil(dimensions.aspectRatio)

        dimensions.update(width: 1920, height: 1080)

        XCTAssertEqual(dimensions.size, CGSize(width: 1920, height: 1080))
        XCTAssertEqual(dimensions.aspectRatio, 16.0 / 9.0)
    }
}
