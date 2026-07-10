import Foundation
import Metal

final class ShaderPipelineStore: @unchecked Sendable {
    let device: MTLDevice

    private let lock = NSLock()
    private var active: MTLRenderPipelineState
    private var lastGood: MTLRenderPipelineState
    private var faultHandler: (@Sendable (String) -> Void)?

    init(device: MTLDevice, initial: MTLRenderPipelineState) {
        self.device = device
        active = initial
        lastGood = initial
    }

    func pipeline() -> MTLRenderPipelineState {
        lock.withLock {
            active
        }
    }

    func install(_ pipeline: MTLRenderPipelineState) {
        lock.withLock {
            active = pipeline
        }
    }

    func markSucceeded(_ pipeline: MTLRenderPipelineState) {
        lock.withLock {
            guard active === pipeline else {
                return
            }
            lastGood = pipeline
        }
    }

    func reportFault(_ pipeline: MTLRenderPipelineState, message: String) {
        let handler = lock.withLock { () -> (@Sendable (String) -> Void)? in
            guard active === pipeline, active !== lastGood else {
                return nil
            }
            active = lastGood
            return faultHandler
        }
        handler?(message)
    }

    func setFaultHandler(_ handler: @escaping @Sendable (String) -> Void) {
        lock.withLock {
            faultHandler = handler
        }
    }
}
