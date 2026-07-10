import Metal
import XCTest
@testable import ShadeCam

final class ShaderPresetTests: XCTestCase {
    func testLoadsEveryBundledPreset() throws {
        let bundle = Bundle(for: ShaderPresetTests.self)
        let presets = ShaderPresetLibrary.load(in: bundle)

        XCTAssertEqual(presets.count, 20)
        XCTAssertTrue(presets.contains(where: { $0.resourceName == "passthrough" }))
        XCTAssertTrue(presets.contains(where: { $0.resourceName == "hand-fire" }))
        XCTAssertTrue(presets.contains(where: { $0.resourceName == "gesture-playground" }))
        XCTAssertTrue(presets.contains(where: { $0.resourceName == "spectrum-bars" }))
        XCTAssertTrue(presets.contains(where: { $0.resourceName == "bass-aura" }))
        XCTAssertTrue(presets.contains(where: { $0.resourceName == "mood-weather" }))
        XCTAssertTrue(presets.contains(where: { $0.resourceName == "flow-smear" }))
        XCTAssertTrue(presets.contains(where: { $0.resourceName == "elemental-avatar" }))
        XCTAssertTrue(presets.contains(where: { $0.resourceName == "depth-fog" }))
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
        {"needs": ["mask", "audio"]}
        SHADE*/
        float4 mainImage() {}
        """

        let parsed = try ShaderMetadataParser.parse(source)

        XCTAssertEqual(parsed.metadata.needs, [.mask, .audio])
        XCTAssertEqual(parsed.body, "float4 mainImage() {}")
        XCTAssertEqual(parsed.bodyStartLine, 4)
    }

    func testSourceWithoutMetadataNeedsOnlyCamera() throws {
        let parsed = try ShaderMetadataParser.parse("float4 mainImage() {}")

        XCTAssertEqual(parsed.metadata.needs, [])
        XCTAssertEqual(parsed.bodyStartLine, 1)
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

    func testBundledPresetNeedsMatchMaskUsage() throws {
        let bundle = Bundle(for: Self.self)

        for preset in ShaderPresetLibrary.load(in: bundle) {
            let parsed = try ShaderMetadataParser.parse(preset.source(in: bundle))
            let expected: Set<ShaderNeed> = switch preset.resourceName {
            case "event-pulse", "passthrough": []
            case "gesture-playground", "hand-fire": [.hands]
            case "bass-aura", "spectrum-bars": [.audio, .mask]
            case "mood-weather": [.expression, .mask]
            case "flow-smear": [.flow]
            case "depth-fog": [.depth]
            case "elemental-avatar": [.audio, .body, .expression, .hands, .mask]
            default: [.mask]
            }
            XCTAssertEqual(parsed.metadata.needs, expected, preset.resourceName)
        }
    }
}
