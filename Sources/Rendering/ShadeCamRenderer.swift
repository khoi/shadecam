import CoreVideo
import MetalKit

final class ShadeCamRenderer: NSObject, MTKViewDelegate, @unchecked Sendable {
    let device: MTLDevice

    private let frameStore: CameraFrameStore
    private let commandQueue: MTLCommandQueue
    private let conversionPipeline: MTLRenderPipelineState
    private let displayPipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private let textureCache: CVMetalTextureCache
    private var cameraTexture: MTLTexture?

    init(frameStore: CameraFrameStore) {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            let commandQueue = device.makeCommandQueue(),
            let library = device.makeDefaultLibrary(),
            let vertexFunction = library.makeFunction(name: "fullscreenVertex"),
            let conversionFunction = library.makeFunction(name: "cameraConversionFragment"),
            let displayFunction = library.makeFunction(name: "cameraDisplayFragment")
        else {
            fatalError("Metal is unavailable")
        }

        self.device = device
        self.frameStore = frameStore
        self.commandQueue = commandQueue

        let conversionDescriptor = MTLRenderPipelineDescriptor()
        conversionDescriptor.vertexFunction = vertexFunction
        conversionDescriptor.fragmentFunction = conversionFunction
        conversionDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        let displayDescriptor = MTLRenderPipelineDescriptor()
        displayDescriptor.vertexFunction = vertexFunction
        displayDescriptor.fragmentFunction = displayFunction
        displayDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        guard
            let conversionPipeline = try? device.makeRenderPipelineState(descriptor: conversionDescriptor),
            let displayPipeline = try? device.makeRenderPipelineState(descriptor: displayDescriptor)
        else {
            fatalError("Metal pipelines could not be created")
        }

        self.conversionPipeline = conversionPipeline
        self.displayPipeline = displayPipeline

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge

        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
            fatalError("Metal sampler could not be created")
        }
        self.sampler = sampler

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
            let frame = frameStore.currentFrame(),
            CVPixelBufferGetPlaneCount(frame) == 2,
            let drawable = view.currentDrawable,
            let renderPassDescriptor = view.currentRenderPassDescriptor,
            let luma = makeTexture(from: frame, plane: 0, format: .r8Unorm),
            let chroma = makeTexture(from: frame, plane: 1, format: .rg8Unorm),
            let commandBuffer = commandQueue.makeCommandBuffer()
        else {
            return
        }

        let width = CVPixelBufferGetWidth(frame)
        let height = CVPixelBufferGetHeight(frame)
        let cameraTexture = cameraTexture(width: width, height: height)

        let conversionPass = MTLRenderPassDescriptor()
        conversionPass.colorAttachments[0].texture = cameraTexture
        conversionPass.colorAttachments[0].loadAction = .dontCare
        conversionPass.colorAttachments[0].storeAction = .store

        guard let conversionEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: conversionPass) else {
            return
        }
        conversionEncoder.setRenderPipelineState(conversionPipeline)
        conversionEncoder.setFragmentTexture(CVMetalTextureGetTexture(luma), index: 0)
        conversionEncoder.setFragmentTexture(CVMetalTextureGetTexture(chroma), index: 1)
        conversionEncoder.setFragmentSamplerState(sampler, index: 0)
        conversionEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        conversionEncoder.endEncoding()

        guard let displayEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        var uniforms = DisplayUniforms(
            viewSize: SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height)),
            cameraSize: SIMD2(Float(width), Float(height))
        )
        displayEncoder.setRenderPipelineState(displayPipeline)
        displayEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<DisplayUniforms>.stride, index: 0)
        displayEncoder.setFragmentTexture(cameraTexture, index: 0)
        displayEncoder.setFragmentSamplerState(sampler, index: 0)
        displayEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        displayEncoder.endEncoding()

        let lease = MetalTextureLease(textures: [luma, chroma])
        commandBuffer.addCompletedHandler { _ in
            lease.release()
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func makeTexture(
        from frame: CVPixelBuffer,
        plane: Int,
        format: MTLPixelFormat
    ) -> CVMetalTexture? {
        let width = CVPixelBufferGetWidthOfPlane(frame, plane)
        let height = CVPixelBufferGetHeightOfPlane(frame, plane)
        var texture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil,
            textureCache,
            frame,
            nil,
            format,
            width,
            height,
            plane,
            &texture
        )
        return status == kCVReturnSuccess ? texture : nil
    }

    private func cameraTexture(width: Int, height: Int) -> MTLTexture {
        if let cameraTexture,
           cameraTexture.width == width,
           cameraTexture.height == height
        {
            return cameraTexture
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .private
        descriptor.usage = [.renderTarget, .shaderRead]

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            fatalError("Camera texture could not be created")
        }
        cameraTexture = texture
        return texture
    }
}

private struct DisplayUniforms {
    var viewSize: SIMD2<Float>
    var cameraSize: SIMD2<Float>
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
