import XCTest
@testable import ShadeCam

final class ShaderDiagnosticParserTests: XCTestCase {
    func testParsesCompilerDiagnostics() {
        let text = "program_source:12:7: error: use of undeclared identifier 'shade'"

        XCTAssertEqual(
            ShaderDiagnosticParser.parse(text),
            [ShaderDiagnostic(line: 12, column: 7, message: "use of undeclared identifier 'shade'")]
        )
    }
}
