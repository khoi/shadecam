import Foundation

struct ShaderSourceComposer: Sendable {
    let header: String
    let common: String
    let wrapper: String

    init(bundle: Bundle = .main) throws {
        header = try Self.load(name: "header", bundle: bundle)
        common = try Self.load(name: "common", bundle: bundle)
        wrapper = try Self.load(name: "wrapper", bundle: bundle)
    }

    func compose(_ userSource: String) throws -> String {
        let parsed = try ShaderMetadataParser.parse(userSource)
        return header + "\n" + common + "\n#line \(parsed.bodyStartLine)\n" + parsed.body + "\n" + wrapper
    }

    private static func load(name: String, bundle: Bundle) throws -> String {
        let url = bundle.url(
            forResource: name,
            withExtension: "shaderpart",
            subdirectory: "Shader"
        ) ?? bundle.url(forResource: name, withExtension: "shaderpart")

        guard let url else {
            throw ShaderSourceComposerError.missingResource(name)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}

enum ShaderSourceComposerError: LocalizedError {
    case missingResource(String)

    var errorDescription: String? {
        switch self {
        case let .missingResource(name):
            "Missing shader source component: \(name)"
        }
    }
}
