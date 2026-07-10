import XCTest
@testable import ShadeCam

final class ShaderUniformsTests: XCTestCase {
    func testABIFieldOffsets() {
        XCTAssertEqual(MemoryLayout<ShaderUniforms>.offset(of: \ShaderUniforms.iMouse), 0)
        XCTAssertEqual(MemoryLayout<ShaderUniforms>.offset(of: \ShaderUniforms.iFaceRect), 16)
        XCTAssertEqual(MemoryLayout<ShaderUniforms>.offset(of: \ShaderUniforms.iResolution), 32)
        XCTAssertEqual(MemoryLayout<ShaderUniforms>.offset(of: \ShaderUniforms.iTime), 40)
        XCTAssertEqual(MemoryLayout<ShaderUniforms>.offset(of: \ShaderUniforms.iTimeDelta), 44)
        XCTAssertEqual(MemoryLayout<ShaderUniforms>.offset(of: \ShaderUniforms.iFrame), 48)
        XCTAssertEqual(MemoryLayout<ShaderUniforms>.stride, 64)
    }
}
