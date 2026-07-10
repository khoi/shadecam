import Metal
import XCTest
@testable import ShadeCam

final class ShaderPresetTests: XCTestCase {
    func testLoadsEveryBundledPreset() throws {
        let bundle = Bundle(for: ShaderPresetTests.self)
        let presets = ShaderPresetLibrary.load(in: bundle)

        XCTAssertEqual(Set(presets.map(\.resourceName)).count, presets.count)
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

    func testParsesMetadataAndStripsItFromSource() throws {
        let source = """
        /*SHADE
        {"needs": ["mask", "audio"], "instructions": "Clap to pulse."}
        SHADE*/
        float4 mainImage() {}
        """

        let parsed = try ShaderMetadataParser.parse(source)

        XCTAssertEqual(parsed.metadata.needs, [.mask, .audio])
        XCTAssertEqual(parsed.metadata.instructions, "Clap to pulse.")
        XCTAssertEqual(parsed.body, "float4 mainImage() {}")
        XCTAssertEqual(parsed.bodyStartLine, 4)
    }

    func testSourceWithoutMetadataNeedsOnlyCamera() throws {
        let parsed = try ShaderMetadataParser.parse("float4 mainImage() {}")

        XCTAssertEqual(parsed.metadata.needs, [])
        XCTAssertNil(parsed.metadata.instructions)
        XCTAssertEqual(parsed.bodyStartLine, 1)
    }

    func testEmptyInstructionsAreOmitted() throws {
        let source = """
        /*SHADE
        {"needs": [], "instructions": "  "}
        SHADE*/
        float4 mainImage() {}
        """

        XCTAssertNil(try ShaderMetadataParser.parse(source).metadata.instructions)
    }

    func testRejectsUnknownNeed() {
        let source = """
        /*SHADE
        {"needs": ["motion"]}
        SHADE*/
        float4 mainImage() {}
        """

        XCTAssertThrowsError(try ShaderMetadataParser.parse(source))
    }

    func testBundledPresetNeedsMatchSourceUsage() throws {
        let bundle = Bundle(for: Self.self)

        for preset in ShaderPresetLibrary.load(in: bundle) {
            let source = try preset.source(in: bundle)
            let parsed = try ShaderMetadataParser.parse(source)
            XCTAssertEqual(parsed.metadata.needs, detectedNeeds(in: parsed.body), preset.resourceName)
        }
    }

    private func detectedNeeds(in source: String) -> Set<ShaderNeed> {
        var needs: Set<ShaderNeed> = []
        if source.contains("mask.sample") {
            needs.insert(.mask)
        }
        if source.contains("u.iHands")
            || source.contains("u.iEvents[0]")
            || source.contains("u.iEvents[2]")
            || source.contains("u.iEvents[3]")
        {
            needs.insert(.hands)
        }
        if source.contains("u.iBody") {
            needs.insert(.body)
        }
        if source.contains("u.iAudio")
            || source.contains("signals.sample")
            || source.contains("u.iEvents[1]")
        {
            needs.insert(.audio)
        }
        if source.contains("u.iExpression") || source.contains("u.iEvents[4]") {
            needs.insert(.expression)
        }
        if source.contains("flow.sample") || source.contains("flow.get_") {
            needs.insert(.flow)
        }
        if source.contains("depth.sample") || source.contains("depth.get_") {
            needs.insert(.depth)
        }
        return needs
    }
}
