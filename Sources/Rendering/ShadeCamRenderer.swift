import CoreVideo
import Foundation
import MetalKit

final class ShadeCamRenderer: NSObject, MTKViewDelegate, @unchecked Sendable {
    let device: MTLDevice

    private let frameStore: PixelBufferStore
    private let maskStore: PixelBufferStore
    private let faceRectStore: FaceRectStore
    private let pipelineStore: ShaderPipelineStore
    private let renderControl: RenderControl
    private let commandQueue: MTLCommandQueue
    private let conversionPipeline: MTLRenderPipelineState
    private let maskAlignmentPipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private let textureCache: CVMetalTextureCache
    private let emptyMaskTexture: MTLTexture
    private let startTime = ProcessInfo.processInfo.systemUptime
    private var previousFrameTime: TimeInterval?
    private var frameIndex: UInt32 = 0
    private var cameraTexture: MTLTexture?
    private var alignedMaskTexture: MTLTexture?
    private var plateTexture: MTLTexture?
    private var plateNeedsClear = true
    private var feedbackTextures: [MTLTexture] = []
    private var feedbackReadIndex = 0
    private var feedbackNeedsClear = true

    init(
        frameStore: PixelBufferStore,
        maskStore: PixelBufferStore,
        faceRectStore: FaceRectStore,
        pipelineStore: ShaderPipelineStore,
        renderControl: RenderControl
    ) {
        let device = pipelineStore.device
        guard
            let commandQueue = device.makeCommandQueue(),
            let library = device.makeDefaultLibrary(),
            let vertexFunction = library.makeFunction(name: "fullscreenVertex"),
            let conversionFunction = library.makeFunction(name: "cameraConversionFragment"),
            let maskAlignmentFunction = library.makeFunction(name: "maskAlignmentFragment")
        else {
            fatalError("Metal is unavailable")
        }

        self.device = device
        self.frameStore = frameStore
        self.maskStore = maskStore
        self.faceRectStore = faceRectStore
        self.pipelineStore = pipelineStore
        self.renderControl = renderControl
        self.commandQueue = commandQueue

        let conversionDescriptor = MTLRenderPipelineDescriptor()
        conversionDescriptor.vertexFunction = vertexFunction
        conversionDescriptor.fragmentFunction = conversionFunction
        conversionDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        let maskAlignmentDescriptor = MTLRenderPipelineDescriptor()
        maskAlignmentDescriptor.vertexFunction = vertexFunction
        maskAlignmentDescriptor.fragmentFunction = maskAlignmentFunction
        maskAlignmentDescriptor.colorAttachments[0].pixelFormat = .r16Float

        guard
            let conversionPipeline = try? device.makeRenderPipelineState(descriptor: conversionDescriptor),
            let maskAlignmentPipeline = try? device.makeRenderPipelineState(descriptor: maskAlignmentDescriptor)
        else {
            fatalError("Metal pipelines could not be created")
        }
        self.conversionPipeline = conversionPipeline
        self.maskAlignmentPipeline = maskAlignmentPipeline

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
            fatalError("Metal sampler could not be created")
        }
        self.sampler = sampler

        let emptyMaskDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r16Float,
            width: 1,
            height: 1,
            mipmapped: false
        )
        emptyMaskDescriptor.storageMode = .shared
        emptyMaskDescriptor.usage = .shaderRead
        guard let emptyMaskTexture = device.makeTexture(descriptor: emptyMaskDescriptor) else {
            fatalError("Empty mask texture could not be created")
        }
        var emptyMask: UInt16 = 0
        emptyMaskTexture.replace(
            region: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0,
            withBytes: &emptyMask,
            bytesPerRow: MemoryLayout<UInt16>.stride
        )
        self.emptyMaskTexture = emptyMaskTexture

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
        let alignedMask = makeAlignedMaskTexture(width: cameraWidth, height: cameraHeight)
        let plate = makePlateTexture(width: cameraWidth, height: cameraHeight)
        let drawableWidth = Int(view.drawableSize.width)
        let drawableHeight = Int(view.drawableSize.height)
        let feedback = makeFeedbackTextures(width: drawableWidth, height: drawableHeight)
        let outputIndex = 1 - feedbackReadIndex
        let output = feedback[outputIndex]
        let pipeline = pipelineStore.pipeline()

        encodeCameraConversion(
            commandBuffer: commandBuffer,
            target: camera,
            luma: luma,
            chroma: chroma
        )
        encodeMaskAlignment(
            commandBuffer: commandBuffer,
            target: alignedMask,
            source: sourceMask,
            cameraSize: SIMD2(Float(cameraWidth), Float(cameraHeight))
        )
        preparePlate(commandBuffer: commandBuffer, camera: camera, plate: plate)
        prepareFeedback(commandBuffer: commandBuffer)

        guard let shaderEncoder = makeEncoder(commandBuffer: commandBuffer, target: output) else {
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        var uniforms = ShaderUniforms(
            iMouse: renderControl.currentMouse(),
            iFaceRect: faceRectStore.current(),
            iResolution: SIMD2(Float(drawableWidth), Float(drawableHeight)),
            iTime: Float(now - startTime),
            iTimeDelta: Float(previousFrameTime.map { now - $0 } ?? 0),
            iFrame: frameIndex
        )
        shaderEncoder.setRenderPipelineState(pipeline)
        shaderEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.stride, index: 0)
        shaderEncoder.setFragmentTexture(camera, index: 0)
        shaderEncoder.setFragmentTexture(alignedMask, index: 1)
        shaderEncoder.setFragmentTexture(feedback[feedbackReadIndex], index: 2)
        shaderEncoder.setFragmentTexture(plate, index: 3)
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

        let lease = MetalTextureLease(textures: [luma, chroma] + [maskReference].compactMap { $0 })
        commandBuffer.addCompletedHandler { [pipelineStore] commandBuffer in
            lease.release()
            if let error = commandBuffer.error {
                pipelineStore.reportFault(
                    pipeline,
                    message: "GPU shader failed: \(error.localizedDescription)"
                )
            } else {
                pipelineStore.markSucceeded(pipeline)
            }
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()

        previousFrameTime = now
        frameIndex &+= 1
        feedbackReadIndex = outputIndex
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

    private func encodeMaskAlignment(
        commandBuffer: MTLCommandBuffer,
        target: MTLTexture,
        source: MTLTexture,
        cameraSize: SIMD2<Float>
    ) {
        guard let encoder = makeEncoder(commandBuffer: commandBuffer, target: target) else {
            return
        }
        var uniforms = MaskAlignmentUniforms(
            cameraSize: cameraSize,
            maskSize: SIMD2(Float(source.width), Float(source.height))
        )
        encoder.setRenderPipelineState(maskAlignmentPipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<MaskAlignmentUniforms>.stride, index: 0)
        encoder.setFragmentTexture(source, index: 0)
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
            clear(plate, commandBuffer: commandBuffer)
            plateNeedsClear = false
        }
    }

    private func prepareFeedback(commandBuffer: MTLCommandBuffer) {
        guard feedbackNeedsClear else {
            return
        }
        for texture in feedbackTextures {
            clear(texture, commandBuffer: commandBuffer)
        }
        feedbackNeedsClear = false
    }

    private func clear(_ texture: MTLTexture, commandBuffer: MTLCommandBuffer) {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = texture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
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

    private func makeAlignedMaskTexture(width: Int, height: Int) -> MTLTexture {
        if let alignedMaskTexture,
           alignedMaskTexture.width == width,
           alignedMaskTexture.height == height
        {
            return alignedMaskTexture
        }
        alignedMaskTexture = makeTexture(
            format: .r16Float,
            width: width,
            height: height,
            usage: [.renderTarget, .shaderRead]
        )
        return alignedMaskTexture!
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
        feedbackReadIndex = 0
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
}

private struct MaskAlignmentUniforms {
    var cameraSize: SIMD2<Float>
    var maskSize: SIMD2<Float>
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
