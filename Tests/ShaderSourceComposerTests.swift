import Metal
import XCTest
@testable import ShadeCam

final class ShaderSourceComposerTests: XCTestCase {
    func testLineDirectivePrecedesUserSource() throws {
        let composer = try ShaderSourceComposer(bundle: Bundle(for: Self.self))

        XCTAssertTrue(composer.compose("user source").contains("\n#line 1\nuser source\n"))
    }

    func testCompilerDiagnosticsUseUserRelativeLines() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            XCTFail("Metal is unavailable")
            return
        }
        let source = """
        float4 mainImage(float2 fragCoord, constant Uniforms& u,
                         texture2d<float> camera, texture2d<float> mask,
                         texture2d<float> feedback, texture2d<float> plate,
                         sampler s) {
            return float4(unknownValue);
        }
        """
        let composer = try ShaderSourceComposer(bundle: Bundle(for: Self.self))

        do {
            _ = try await device.makeLibrary(source: composer.compose(source), options: nil)
            XCTFail("Compilation unexpectedly succeeded")
        } catch {
            let diagnostics = ShaderDiagnosticParser.parse(error.localizedDescription)
            XCTAssertEqual(diagnostics.first?.line, 5)
        }
    }
}
