import MetalKit
import SwiftUI

struct CameraPreviewView: NSViewRepresentable {
    let frameStore: PixelBufferStore
    let maskStore: PixelBufferStore
    let faceRectStore: FaceRectStore
    let pipelineStore: ShaderPipelineStore
    let renderControl: RenderControl

    func makeCoordinator() -> Coordinator {
        Coordinator(
            frameStore: frameStore,
            maskStore: maskStore,
            faceRectStore: faceRectStore,
            pipelineStore: pipelineStore,
            renderControl: renderControl
        )
    }

    func makeNSView(context: Context) -> MTKView {
        let view = ShaderMTKView(
            frame: .zero,
            device: context.coordinator.renderer.device,
            renderControl: renderControl
        )
        view.delegate = context.coordinator.renderer
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColorMake(0, 0, 0, 1)
        view.framebufferOnly = false
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 60
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {}

    final class Coordinator {
        let renderer: ShadeCamRenderer

        init(
            frameStore: PixelBufferStore,
            maskStore: PixelBufferStore,
            faceRectStore: FaceRectStore,
            pipelineStore: ShaderPipelineStore,
            renderControl: RenderControl
        ) {
            renderer = ShadeCamRenderer(
                frameStore: frameStore,
                maskStore: maskStore,
                faceRectStore: faceRectStore,
                pipelineStore: pipelineStore,
                renderControl: renderControl
            )
        }
    }
}

private final class ShaderMTKView: MTKView {
    private let renderControl: RenderControl

    init(frame: CGRect, device: MTLDevice, renderControl: RenderControl) {
        self.renderControl = renderControl
        super.init(frame: frame, device: device)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        renderControl.beginDrag(at: shaderPoint(for: event))
    }

    override func mouseDragged(with event: NSEvent) {
        renderControl.drag(to: shaderPoint(for: event))
    }

    private func shaderPoint(for event: NSEvent) -> SIMD2<Float> {
        let point = convert(event.locationInWindow, from: nil)
        let scaleX = drawableSize.width / max(bounds.width, 1)
        let scaleY = drawableSize.height / max(bounds.height, 1)
        return SIMD2(Float(point.x * scaleX), Float((bounds.height - point.y) * scaleY))
    }
}
