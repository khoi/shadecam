import XCTest
@testable import ShadeCam

final class ShaderPresetTests: XCTestCase {
    func testLoadsEveryBundledPreset() throws {
        let bundle = Bundle(for: ShaderPresetTests.self)
        let presets = ShaderPresetLibrary.load(in: bundle)

        XCTAssertTrue(presets.contains(where: { $0.resourceName == "passthrough" }))
        for preset in presets {
            XCTAssertTrue(try preset.source(in: bundle).contains("float4 mainImage"))
        }
    }
}
