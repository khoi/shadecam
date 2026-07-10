import Foundation

enum ShaderNeed: String, CaseIterable, Codable, Sendable {
    case mask
    case hands
    case body
    case audio
    case expression
    case flow
    case depth
}

struct ShaderMetadata: Equatable, Sendable {
    var needs: Set<ShaderNeed> = []
}

struct ParsedShaderSource: Equatable, Sendable {
    let metadata: ShaderMetadata
    let body: String
    let bodyStartLine: Int
}

enum ShaderMetadataParser {
    private static let prefix = "/*SHADE"
    private static let suffix = "SHADE*/"

    static func parse(_ source: String) throws -> ParsedShaderSource {
        guard source.hasPrefix(prefix) else {
            return ParsedShaderSource(metadata: .init(), body: source, bodyStartLine: 1)
        }
        let metadataStart = source.index(source.startIndex, offsetBy: prefix.count)
        guard let suffixRange = source.range(of: suffix, range: metadataStart..<source.endIndex) else {
            throw ShaderMetadataError.unterminatedBlock
        }
        let metadataSource = String(source[metadataStart..<suffixRange.lowerBound])
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: Data(metadataSource.utf8))
        } catch {
            throw ShaderMetadataError.invalidBlock(error.localizedDescription)
        }

        var bodyStart = suffixRange.upperBound
        if bodyStart < source.endIndex, source[bodyStart] == "\r" {
            bodyStart = source.index(after: bodyStart)
        }
        if bodyStart < source.endIndex, source[bodyStart] == "\n" {
            bodyStart = source.index(after: bodyStart)
        }
        let precedingSource = source[..<bodyStart]
        let bodyStartLine = precedingSource.reduce(1) { line, character in
            character == "\n" ? line + 1 : line
        }
        return ParsedShaderSource(
            metadata: ShaderMetadata(needs: Set(payload.needs)),
            body: String(source[bodyStart...]),
            bodyStartLine: bodyStartLine
        )
    }

    private struct Payload: Decodable {
        let needs: [ShaderNeed]
    }
}

enum ShaderMetadataError: LocalizedError {
    case unterminatedBlock
    case invalidBlock(String)

    var errorDescription: String? {
        switch self {
        case .unterminatedBlock:
            "Unterminated SHADE metadata block"
        case let .invalidBlock(message):
            "Invalid SHADE metadata: \(message)"
        }
    }
}
