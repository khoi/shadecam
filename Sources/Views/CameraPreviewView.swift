import MetalKit
import SwiftUI

struct CameraPreviewView: NSViewRepresentable {
    let frameStore: PixelBufferStore
    let maskStore: PixelBufferStore

    func makeCoordinator() -> Coordinator {
        Coordinator(frameStore: frameStore, maskStore: maskStore)
    }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.renderer.device)
        view.delegate = context.coordinator.renderer
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColorMake(0, 0, 0, 1)
        view.framebufferOnly = true
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 60
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {}

    final class Coordinator {
        let renderer: ShadeCamRenderer

        init(frameStore: PixelBufferStore, maskStore: PixelBufferStore) {
            renderer = ShadeCamRenderer(frameStore: frameStore, maskStore: maskStore)
        }
    }
}
