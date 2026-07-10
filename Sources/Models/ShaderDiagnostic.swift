import Foundation

struct ShaderDiagnostic: Equatable, Identifiable {
    let line: Int
    let column: Int
    let message: String

    var id: String {
        "\(line):\(column):\(message)"
    }
}
