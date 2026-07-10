import Foundation

enum ShaderDiagnosticParser {
    private static let expression = try! NSRegularExpression(
        pattern: #"program_source:(\d+):(\d+):\s*error:\s*([^\r\n]+)"#
    )

    static func parse(_ text: String) -> [ShaderDiagnostic] {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            guard
                let lineRange = Range(match.range(at: 1), in: text),
                let columnRange = Range(match.range(at: 2), in: text),
                let messageRange = Range(match.range(at: 3), in: text),
                let line = Int(text[lineRange]),
                let column = Int(text[columnRange])
            else {
                return nil
            }
            return ShaderDiagnostic(
                line: line,
                column: column,
                message: String(text[messageRange]).trimmingCharacters(in: .whitespaces)
            )
        }
    }
}
