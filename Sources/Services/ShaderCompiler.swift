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
        let library = try device.makeLibrary(source: composer.compose(initialSource), options: nil)
        let initial = try Self.makePipeline(device: device, vertexFunction: vertexFunction, library: library)
        pipelineStore = ShaderPipelineStore(device: device, initial: initial)
    }

    func compile(_ source: String) async throws -> MTLRenderPipelineState {
        let library = try await device.makeLibrary(source: composer.compose(source), options: nil)
        return try Self.makePipeline(device: device, vertexFunction: vertexFunction, library: library)
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
