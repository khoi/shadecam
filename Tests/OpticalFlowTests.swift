import CoreVideo
import Metal
import XCTest
@testable import ShadeCam

final class OpticalFlowTests: XCTestCase {
    func testPixelFormatsMapToMetal() {
        XCTAssertEqual(
            OpticalFlowPixelFormat(cvPixelFormat: kCVPixelFormatType_TwoComponent16Half)?.metalPixelFormat,
            .rg16Float
        )
        XCTAssertEqual(
            OpticalFlowPixelFormat(cvPixelFormat: kCVPixelFormatType_TwoComponent32Float)?.metalPixelFormat,
            .rg32Float
        )
        XCTAssertNil(OpticalFlowPixelFormat(cvPixelFormat: kCVPixelFormatType_32BGRA))
    }

    func testFlowNeedGatesProducer() {
        XCTAssertTrue(OpticalFlowService.isEnabled(for: [.flow]))
        XCTAssertFalse(OpticalFlowService.isEnabled(for: []))
        XCTAssertFalse(OpticalFlowService.isEnabled(for: [.body, .mask]))
    }
}
