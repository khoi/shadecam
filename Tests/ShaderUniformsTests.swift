import XCTest
@testable import ShadeCam

final class ShaderUniformsTests: XCTestCase {
    func testABIFieldOffsets() {
        XCTAssertEqual(MemoryLayout<ShaderUniforms>.offset(of: \ShaderUniforms.iMouse), 0)
        XCTAssertEqual(MemoryLayout<ShaderUniforms>.offset(of: \ShaderUniforms.iFaceRect), 16)
        XCTAssertEqual(MemoryLayout<ShaderUniforms>.offset(of: \ShaderUniforms.iExpression), 32)
        XCTAssertEqual(MemoryLayout<ShaderUniforms>.offset(of: \ShaderUniforms.iAudio), 48)
        XCTAssertEqual(MemoryLayout<ShaderUniforms>.offset(of: \ShaderUniforms.iEvents), 64)
        XCTAssertEqual(MemoryLayout<ShaderUniforms>.offset(of: \ShaderUniforms.iHands), 192)
        XCTAssertEqual(MemoryLayout<ShaderUniforms>.offset(of: \ShaderUniforms.iBody), 864)
        XCTAssertEqual(MemoryLayout<ShaderUniforms>.offset(of: \ShaderUniforms.iResolution), 1_168)
        XCTAssertEqual(MemoryLayout<ShaderUniforms>.offset(of: \ShaderUniforms.iTime), 1_176)
        XCTAssertEqual(MemoryLayout<ShaderUniforms>.offset(of: \ShaderUniforms.iTimeDelta), 1_180)
        XCTAssertEqual(MemoryLayout<ShaderUniforms>.offset(of: \ShaderUniforms.iFrame), 1_184)
        XCTAssertEqual(MemoryLayout<ShaderUniforms>.stride, 1_200)
    }

    func testFixedArrayStorageMatchesMetalLayout() {
        XCTAssertEqual(MemoryLayout<ShaderEventUniforms>.stride, 8 * 16)
        XCTAssertEqual(MemoryLayout<ShaderHandUniforms>.stride, 2 * 21 * 16)
        XCTAssertEqual(MemoryLayout<ShaderBodyUniforms>.stride, 19 * 16)
    }
}
