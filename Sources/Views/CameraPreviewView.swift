import MetalKit
import SwiftUI

struct CameraPreviewView: NSViewRepresentable {
    let frameStore: PixelBufferStore
    let maskStore: PixelBufferStore
    let flowStore: PixelBufferStore
    let depthStore: PixelBufferStore
    let signalTextureStore: SignalTextureStore
    let signalBus: SignalBus
    let pipelineStore: ShaderPipelineStore
    let renderControl: RenderControl
    let renderMetrics: RenderMetrics

    func makeCoordinator() -> Coordinator {
        Coordinator(
            frameStore: frameStore,
            maskStore: maskStore,
            flowStore: flowStore,
            depthStore: depthStore,
            signalTextureStore: signalTextureStore,
            signalBus: signalBus,
            pipelineStore: pipelineStore,
            renderControl: renderControl,
            renderMetrics: renderMetrics
        )
    }

    func makeNSView(context: Context) -> MTKView {
        let view = ShaderMTKView(
            frame: .zero,
            device: context.coordinator.renderer.device,
            renderControl: renderControl,
            signalBus: signalBus
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
            flowStore: PixelBufferStore,
            depthStore: PixelBufferStore,
            signalTextureStore: SignalTextureStore,
            signalBus: SignalBus,
            pipelineStore: ShaderPipelineStore,
            renderControl: RenderControl,
            renderMetrics: RenderMetrics
        ) {
            renderer = ShadeCamRenderer(
                frameStore: frameStore,
                maskStore: maskStore,
                flowStore: flowStore,
                depthStore: depthStore,
                signalTextureStore: signalTextureStore,
                signalBus: signalBus,
                pipelineStore: pipelineStore,
                renderControl: renderControl,
                renderMetrics: renderMetrics
            )
        }
    }
}

private final class ShaderMTKView: MTKView {
    private let renderControl: RenderControl
    private let signalBus: SignalBus

    init(frame: CGRect, device: MTLDevice, renderControl: RenderControl, signalBus: SignalBus) {
        self.renderControl = renderControl
        self.signalBus = signalBus
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
        let point = shaderPoint(for: event)
        renderControl.beginDrag(at: point)
        signalBus.trigger(
            SignalNames.debugEvent,
            at: event.timestamp,
            position: normalizedPoint(point)
        )
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

    private func normalizedPoint(_ point: SIMD2<Float>) -> SIMD2<Float> {
        let width = Float(max(drawableSize.width, 1))
        let height = Float(max(drawableSize.height, 1))
        return SIMD2(
            min(max(point.x / width, 0), 1),
            min(max(point.y / height, 0), 1)
        )
    }
}
