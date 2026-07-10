import Foundation
import Metal

final class ShaderPipelineStore: @unchecked Sendable {
    let device: MTLDevice

    private let lock = NSLock()
    private var active: ShaderPipelineArtifact
    private var lastGood: ShaderPipelineArtifact
    private var generation: UInt64 = 0
    private var faultHandler: (@Sendable (ShaderPipelineSnapshot, String) -> Void)?

    init(device: MTLDevice, initial: ShaderPipelineArtifact) {
        self.device = device
        active = initial
        lastGood = initial
    }

    func snapshot() -> ShaderPipelineSnapshot {
        lock.withLock {
            ShaderPipelineSnapshot(artifact: active, generation: generation)
        }
    }

    func install(_ artifact: ShaderPipelineArtifact) {
        lock.withLock {
            active = artifact
            generation &+= 1
        }
    }

    func markSucceeded(_ artifact: ShaderPipelineArtifact) {
        lock.withLock {
            guard active.pipeline === artifact.pipeline else {
                return
            }
            lastGood = artifact
        }
    }

    func reportFault(_ artifact: ShaderPipelineArtifact, message: String) {
        let fallback = lock.withLock {
            () -> (ShaderPipelineSnapshot, (@Sendable (ShaderPipelineSnapshot, String) -> Void)?)? in
            guard active.pipeline === artifact.pipeline,
                  active.pipeline !== lastGood.pipeline
            else {
                return nil
            }
            active = lastGood
            generation &+= 1
            return (ShaderPipelineSnapshot(artifact: active, generation: generation), faultHandler)
        }
        guard let (snapshot, handler) = fallback else {
            return
        }
        handler?(snapshot, message)
    }

    func setFaultHandler(_ handler: @escaping @Sendable (ShaderPipelineSnapshot, String) -> Void) {
        lock.withLock {
            faultHandler = handler
        }
    }
}

struct ShaderPipelineArtifact: @unchecked Sendable {
    let pipeline: MTLRenderPipelineState
    let metadata: ShaderMetadata
}

struct ShaderPipelineSnapshot: @unchecked Sendable {
    let artifact: ShaderPipelineArtifact
    let generation: UInt64
}
