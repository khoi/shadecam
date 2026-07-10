import Metal

final class ShaderCompiler: @unchecked Sendable {
    let pipelineStore: ShaderPipelineStore

    private let composer: ShaderSourceComposer
    private let device: MTLDevice
    private let vertexFunction: MTLFunction

    init(initialSource: String, composer: ShaderSourceComposer) throws {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            let vertexFunction = device.makeDefaultLibrary()?.makeFunction(name: "fullscreenVertex")
        else {
            throw ShaderCompilerError.metalUnavailable
        }
        self.composer = composer
        self.device = device
        self.vertexFunction = vertexFunction
        let metadata = try ShaderMetadataParser.parse(initialSource).metadata
        let library = try device.makeLibrary(source: composer.compose(initialSource), options: nil)
        let pipeline = try Self.makePipeline(device: device, vertexFunction: vertexFunction, library: library)
        let initial = ShaderPipelineArtifact(pipeline: pipeline, metadata: metadata)
        pipelineStore = ShaderPipelineStore(device: device, initial: initial)
    }

    func compile(_ source: String) async throws -> ShaderPipelineArtifact {
        let metadata = try ShaderMetadataParser.parse(source).metadata
        let library = try await device.makeLibrary(source: composer.compose(source), options: nil)
        let pipeline = try Self.makePipeline(device: device, vertexFunction: vertexFunction, library: library)
        return ShaderPipelineArtifact(pipeline: pipeline, metadata: metadata)
    }

    private static func makePipeline(
        device: MTLDevice,
        vertexFunction: MTLFunction,
        library: MTLLibrary
    ) throws -> MTLRenderPipelineState {
        guard let fragmentFunction = library.makeFunction(name: "shade_fragment") else {
            throw ShaderCompilerError.entryPointsUnavailable
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }
}

enum ShaderCompilerError: Error {
    case metalUnavailable
    case entryPointsUnavailable
}
