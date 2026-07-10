import Foundation

struct ShaderPreset: Hashable, Identifiable {
    let resourceName: String

    var id: String {
        resourceName
    }

    var name: String {
        resourceName
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    func source(in bundle: Bundle = .main) throws -> String {
        let url = bundle.url(
            forResource: resourceName,
            withExtension: "shade",
            subdirectory: "Presets"
        ) ?? bundle.url(forResource: resourceName, withExtension: "shade")

        guard let url else {
            throw ShaderPresetError.missingResource(resourceName)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}

enum ShaderPresetLibrary {
    static func load(in bundle: Bundle = .main) -> [ShaderPreset] {
        let nested = bundle.urls(forResourcesWithExtension: "shade", subdirectory: "Presets") ?? []
        let root = bundle.urls(forResourcesWithExtension: "shade", subdirectory: nil) ?? []
        return Set((nested + root).map { $0.deletingPathExtension().lastPathComponent })
            .map(ShaderPreset.init(resourceName:))
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

enum ShaderPresetError: LocalizedError {
    case missingResource(String)

    var errorDescription: String? {
        switch self {
        case let .missingResource(name):
            "Missing shader preset: \(name)"
        }
    }
}
