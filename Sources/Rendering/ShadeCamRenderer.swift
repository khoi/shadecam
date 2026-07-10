import CoreVideo
import Foundation
import MetalKit

final class ShadeCamRenderer: NSObject, MTKViewDelegate, @unchecked Sendable {
    let device: MTLDevice

    private let frameStore: PixelBufferStore
    private let maskStore: PixelBufferStore
    private let flowStore: PixelBufferStore
    private let depthStore: PixelBufferStore
    private let signalTextureStore: SignalTextureStore
    private let signalBus: SignalBus
    private let pipelineStore: ShaderPipelineStore
    private let renderControl: RenderControl
    private let renderMetrics: RenderMetrics
    private let commandQueue: MTLCommandQueue
    private let conversionPipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private let textureCache: CVMetalTextureCache
    private let emptyMaskTexture: MTLTexture
    private let signalsTexture: MTLTexture
    private let emptyFlowTexture: MTLTexture
    private let emptyDepthTexture: MTLTexture
    private var renderSession = ShaderRenderSession()
    private var cameraTexture: MTLTexture?
    private var plateTexture: MTLTexture?
    private var plateNeedsClear = true
    private var feedbackTextures: [MTLTexture] = []
    private var feedbackNeedsClear = true
    private var signalTextureRevision: UInt64 = 0

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
        let device = pipelineStore.device
        guard
            let commandQueue = device.makeCommandQueue(),
            let library = device.makeDefaultLibrary(),
            let vertexFunction = library.makeFunction(name: "fullscreenVertex"),
            let conversionFunction = library.makeFunction(name: "cameraConversionFragment")
        else {
            fatalError("Metal is unavailable")
        }

        self.device = device
        self.frameStore = frameStore
        self.maskStore = maskStore
        self.flowStore = flowStore
        self.depthStore = depthStore
        self.signalTextureStore = signalTextureStore
        self.signalBus = signalBus
        self.pipelineStore = pipelineStore
        self.renderControl = renderControl
        self.renderMetrics = renderMetrics
        self.commandQueue = commandQueue

        let conversionDescriptor = MTLRenderPipelineDescriptor()
        conversionDescriptor.vertexFunction = vertexFunction
        conversionDescriptor.fragmentFunction = conversionFunction
        conversionDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        guard let conversionPipeline = try? device.makeRenderPipelineState(descriptor: conversionDescriptor) else {
            fatalError("Metal pipelines could not be created")
        }
        self.conversionPipeline = conversionPipeline

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
            fatalError("Metal sampler could not be created")
        }
        self.sampler = sampler

        emptyMaskTexture = Self.makeZeroTexture(device: device, width: 1, height: 1)
        signalsTexture = Self.makeZeroTexture(device: device, width: 256, height: 4)
        emptyFlowTexture = Self.makeZeroTexture(device: device, width: 1, height: 1)
        emptyDepthTexture = Self.makeZeroTexture(device: device, width: 1, height: 1)

        var textureCache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache) == kCVReturnSuccess,
              let textureCache
        else {
            fatalError("Metal texture cache could not be created")
        }
        self.textureCache = textureCache
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard
            let frame = frameStore.current(),
            CVPixelBufferGetPlaneCount(frame) == 2,
            let drawable = view.currentDrawable,
            view.drawableSize.width > 0,
            view.drawableSize.height > 0,
            let luma = makeTexture(from: frame, plane: 0, format: .r8Unorm),
            let chroma = makeTexture(from: frame, plane: 1, format: .rg8Unorm),
            let commandBuffer = commandQueue.makeCommandBuffer()
        else {
            return
        }

        let cameraWidth = CVPixelBufferGetWidth(frame)
        let cameraHeight = CVPixelBufferGetHeight(frame)
        let camera = makeCameraTexture(width: cameraWidth, height: cameraHeight)
        let maskReference = maskStore.current().flatMap {
            makeTexture(from: $0, plane: 0, format: .r16Float)
        }
        let sourceMask = maskReference.flatMap(CVMetalTextureGetTexture) ?? emptyMaskTexture
        let flowReference = flowStore.current().flatMap { pixelBuffer in
            OpticalFlowPixelFormat(cvPixelFormat: CVPixelBufferGetPixelFormatType(pixelBuffer))
                .flatMap { makeTexture(from: pixelBuffer, plane: 0, format: $0.metalPixelFormat) }
        }
        let sourceFlow = flowReference.flatMap(CVMetalTextureGetTexture) ?? emptyFlowTexture
        let depthReference: CVMetalTexture? = depthStore.current().flatMap { pixelBuffer in
            guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_OneComponent16Half else {
                return nil
            }
            return makeTexture(from: pixelBuffer, plane: 0, format: .r16Float)
        }
        let sourceDepth = depthReference.flatMap(CVMetalTextureGetTexture) ?? emptyDepthTexture
        let plate = makePlateTexture(width: cameraWidth, height: cameraHeight)
        let drawableWidth = Int(view.drawableSize.width)
        let drawableHeight = Int(view.drawableSize.height)
        let feedback = makeFeedbackTextures(width: drawableWidth, height: drawableHeight)
        let now = ProcessInfo.processInfo.systemUptime
        let pipelineSnapshot = pipelineStore.snapshot()
        let renderFrame = renderSession.beginFrame(generation: pipelineSnapshot.generation, at: now)
        if renderFrame.shouldClearFeedback {
            feedbackNeedsClear = true
        }
        let output = feedback[renderFrame.feedbackWriteIndex]
        let artifact = pipelineSnapshot.artifact
        let pipeline = artifact.pipeline

        encodeCameraConversion(
            commandBuffer: commandBuffer,
            target: camera,
            luma: luma,
            chroma: chroma
        )
        preparePlate(commandBuffer: commandBuffer, camera: camera, plate: plate)
        prepareFeedback(commandBuffer: commandBuffer)
        uploadSignalTextureIfNeeded()

        guard let shaderEncoder = makeEncoder(commandBuffer: commandBuffer, target: output) else {
            return
        }
        let signalSnapshot = signalBus.snapshot(at: now)
        var uniforms = ShaderUniforms(
            iMouse: renderControl.currentMouse(),
            iFaceRect: signalSnapshot.faceRect,
            iExpression: signalSnapshot.expression,
            iAudio: signalSnapshot.audio,
            iEvents: signalSnapshot.events,
            iHands: signalSnapshot.hands,
            iBody: signalSnapshot.body,
            iResolution: SIMD2(Float(drawableWidth), Float(drawableHeight)),
            iTime: Float(renderFrame.effectTime),
            iTimeDelta: Float(renderFrame.timeDelta),
            iFrame: renderFrame.frameIndex
        )
        shaderEncoder.setRenderPipelineState(pipeline)
        shaderEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.stride, index: 0)
        shaderEncoder.setFragmentTexture(camera, index: 0)
        shaderEncoder.setFragmentTexture(sourceMask, index: 1)
        shaderEncoder.setFragmentTexture(feedback[renderFrame.feedbackReadIndex], index: 2)
        shaderEncoder.setFragmentTexture(plate, index: 3)
        shaderEncoder.setFragmentTexture(signalsTexture, index: 4)
        shaderEncoder.setFragmentTexture(sourceFlow, index: 5)
        shaderEncoder.setFragmentTexture(sourceDepth, index: 6)
        shaderEncoder.setFragmentSamplerState(sampler, index: 0)
        shaderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        shaderEncoder.endEncoding()

        guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
            return
        }
        blitEncoder.copy(
            from: output,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: .init(x: 0, y: 0, z: 0),
            sourceSize: .init(width: drawableWidth, height: drawableHeight, depth: 1),
            to: drawable.texture,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: .init(x: 0, y: 0, z: 0)
        )
        blitEncoder.endEncoding()

        let lease = MetalTextureLease(
            textures: [luma, chroma] + [maskReference, flowReference, depthReference].compactMap { $0 }
        )
        commandBuffer.addCompletedHandler { [pipelineStore, renderMetrics] commandBuffer in
            lease.release()
            if let error = commandBuffer.error {
                pipelineStore.reportFault(
                    artifact,
                    message: "GPU shader failed: \(error.localizedDescription)"
                )
            } else {
                pipelineStore.markSucceeded(artifact)
                renderMetrics.recordFrame()
            }
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()

        renderSession.completeFrame(renderFrame)
    }

    private func encodeCameraConversion(
        commandBuffer: MTLCommandBuffer,
        target: MTLTexture,
        luma: CVMetalTexture,
        chroma: CVMetalTexture
    ) {
        guard let encoder = makeEncoder(commandBuffer: commandBuffer, target: target) else {
            return
        }
        encoder.setRenderPipelineState(conversionPipeline)
        encoder.setFragmentTexture(CVMetalTextureGetTexture(luma), index: 0)
        encoder.setFragmentTexture(CVMetalTextureGetTexture(chroma), index: 1)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    private func preparePlate(
        commandBuffer: MTLCommandBuffer,
        camera: MTLTexture,
        plate: MTLTexture
    ) {
        if renderControl.consumePlateCaptureRequest(),
           let encoder = commandBuffer.makeBlitCommandEncoder()
        {
            encoder.copy(from: camera, to: plate)
            encoder.endEncoding()
            plateNeedsClear = false
        } else if plateNeedsClear {
            clear(plate, alpha: 0, commandBuffer: commandBuffer)
            plateNeedsClear = false
        }
    }

    private func prepareFeedback(commandBuffer: MTLCommandBuffer) {
        guard feedbackNeedsClear else {
            return
        }
        for texture in feedbackTextures {
            clear(texture, alpha: 1, commandBuffer: commandBuffer)
        }
        feedbackNeedsClear = false
    }

    private func uploadSignalTextureIfNeeded() {
        guard let snapshot = signalTextureStore.current(after: signalTextureRevision) else {
            return
        }
        let values = snapshot.frame.values.map { Float16($0).bitPattern }
        values.withUnsafeBytes {
            signalsTexture.replace(
                region: MTLRegionMake2D(0, 0, SignalTextureFrame.width, SignalTextureFrame.height),
                mipmapLevel: 0,
                withBytes: $0.baseAddress!,
                bytesPerRow: SignalTextureFrame.width * MemoryLayout<Float16>.stride
            )
        }
        signalTextureRevision = snapshot.revision
    }

    private func clear(_ texture: MTLTexture, alpha: Double, commandBuffer: MTLCommandBuffer) {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = texture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, alpha)
        commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)?.endEncoding()
    }

    private func makeEncoder(
        commandBuffer: MTLCommandBuffer,
        target: MTLTexture
    ) -> MTLRenderCommandEncoder? {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target
        descriptor.colorAttachments[0].loadAction = .dontCare
        descriptor.colorAttachments[0].storeAction = .store
        return commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
    }

    private func makeTexture(
        from pixelBuffer: CVPixelBuffer,
        plane: Int,
        format: MTLPixelFormat
    ) -> CVMetalTexture? {
        let isPlanar = CVPixelBufferGetPlaneCount(pixelBuffer) > 0
        let width = isPlanar
            ? CVPixelBufferGetWidthOfPlane(pixelBuffer, plane)
            : CVPixelBufferGetWidth(pixelBuffer)
        let height = isPlanar
            ? CVPixelBufferGetHeightOfPlane(pixelBuffer, plane)
            : CVPixelBufferGetHeight(pixelBuffer)
        var texture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil,
            textureCache,
            pixelBuffer,
            nil,
            format,
            width,
            height,
            plane,
            &texture
        )
        return status == kCVReturnSuccess ? texture : nil
    }

    private func makeCameraTexture(width: Int, height: Int) -> MTLTexture {
        if let cameraTexture,
           cameraTexture.width == width,
           cameraTexture.height == height
        {
            return cameraTexture
        }
        cameraTexture = makeTexture(
            format: .bgra8Unorm,
            width: width,
            height: height,
            usage: [.renderTarget, .shaderRead]
        )
        return cameraTexture!
    }

    private func makePlateTexture(width: Int, height: Int) -> MTLTexture {
        if let plateTexture,
           plateTexture.width == width,
           plateTexture.height == height
        {
            return plateTexture
        }
        plateTexture = makeTexture(
            format: .bgra8Unorm,
            width: width,
            height: height,
            usage: [.renderTarget, .shaderRead]
        )
        plateNeedsClear = true
        return plateTexture!
    }

    private func makeFeedbackTextures(width: Int, height: Int) -> [MTLTexture] {
        if feedbackTextures.first?.width == width,
           feedbackTextures.first?.height == height
        {
            return feedbackTextures
        }
        feedbackTextures = (0..<2).map { _ in
            makeTexture(
                format: .bgra8Unorm,
                width: width,
                height: height,
                usage: [.renderTarget, .shaderRead]
            )
        }
        renderSession.resetFeedback()
        feedbackNeedsClear = true
        return feedbackTextures
    }

    private func makeTexture(
        format: MTLPixelFormat,
        width: Int,
        height: Int,
        usage: MTLTextureUsage
    ) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .private
        descriptor.usage = usage
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            fatalError("Metal texture could not be created")
        }
        return texture
    }

    private static func makeZeroTexture(device: MTLDevice, width: Int, height: Int) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r16Float,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            fatalError("Zero texture could not be created")
        }
        let zeros = [UInt16](repeating: 0, count: width * height)
        zeros.withUnsafeBytes {
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0,
                withBytes: $0.baseAddress!,
                bytesPerRow: width * MemoryLayout<UInt16>.stride
            )
        }
        return texture
    }
}

private final class MetalTextureLease: @unchecked Sendable {
    private var textures: [CVMetalTexture]?

    init(textures: [CVMetalTexture]) {
        self.textures = textures
    }

    func release() {
        textures = nil
    }
}
