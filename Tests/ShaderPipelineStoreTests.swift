import Foundation
import XCTest
@testable import ShadeCam

final class ShaderPipelineStoreTests: XCTestCase {
    func testFaultRestoresLastGoodArtifactAndMetadata() async throws {
        let bundle = Bundle(for: Self.self)
        let composer = try ShaderSourceComposer(bundle: bundle)
        let compiler = try ShaderCompiler(
            initialSource: try ShaderPreset(resourceName: "passthrough").source(in: bundle),
            composer: composer
        )
        let store = compiler.pipelineStore
        let lastGood = try await compiler.compile(
            ShaderPreset(resourceName: "hand-fire").source(in: bundle)
        )
        let candidate = try await compiler.compile(
            ShaderPreset(resourceName: "depth-fog").source(in: bundle)
        )
        let recorder = ShaderFaultRecorder()
        store.setFaultHandler { snapshot, message in
            recorder.record(snapshot: snapshot, message: message)
        }

        XCTAssertEqual(store.snapshot().generation, 0)
        store.install(lastGood)
        store.markSucceeded(lastGood)
        XCTAssertEqual(store.snapshot().generation, 1)
        store.install(candidate)
        XCTAssertEqual(store.snapshot().generation, 2)

        store.reportFault(candidate, message: "failed")

        let fallback = store.snapshot()
        XCTAssertEqual(fallback.generation, 3)
        XCTAssertTrue(fallback.artifact.pipeline === lastGood.pipeline)
        XCTAssertEqual(fallback.artifact.metadata, lastGood.metadata)
        let fault = try XCTUnwrap(recorder.current())
        XCTAssertEqual(fault.snapshot.generation, 3)
        XCTAssertEqual(fault.snapshot.artifact.metadata, lastGood.metadata)
        XCTAssertEqual(fault.message, "failed")
    }
}

private struct RecordedShaderFault {
    let snapshot: ShaderPipelineSnapshot
    let message: String
}

private final class ShaderFaultRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var fault: RecordedShaderFault?

    func record(snapshot: ShaderPipelineSnapshot, message: String) {
        lock.withLock {
            fault = RecordedShaderFault(snapshot: snapshot, message: message)
        }
    }

    func current() -> RecordedShaderFault? {
        lock.withLock {
            fault
        }
    }
}
