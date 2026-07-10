import Metal
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

    func testEveryBundledPresetCompiles() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            XCTFail("Metal is unavailable")
            return
        }
        let bundle = Bundle(for: Self.self)
        let composer = try ShaderSourceComposer(bundle: bundle)

        for preset in ShaderPresetLibrary.load(in: bundle) {
            let source = try preset.source(in: bundle)
            do {
                _ = try await device.makeLibrary(source: composer.compose(source), options: nil)
            } catch {
                XCTFail("\(preset.resourceName): \(error.localizedDescription)")
            }
        }
    }
}
