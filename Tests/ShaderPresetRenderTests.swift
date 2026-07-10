import CoreGraphics
import Foundation
import ImageIO
import Metal
import XCTest
@testable import ShadeCam

final class ShaderPresetRenderTests: XCTestCase {
    func testEveryBundledPresetRendersOffscreen() async throws {
        let bundle = Bundle(for: Self.self)
        let presets = ShaderPresetLibrary.load(in: bundle)
        let passthrough = try XCTUnwrap(presets.first { $0.resourceName == "passthrough" })
        let composer = try ShaderSourceComposer(bundle: bundle)
        let compiler = try ShaderCompiler(
            initialSource: passthrough.source(in: bundle),
            composer: composer
        )
        let environment = ProcessInfo.processInfo.environment
        let injectedFixture = bundle.url(forResource: "shader-fixture", withExtension: "jpg")
        let fixtureURL = environment["SHADECAM_RENDER_FIXTURE"].map { URL(filePath: $0) }
            ?? injectedFixture
        let renderer = try ShaderPresetFixtureRenderer(
            device: compiler.pipelineStore.device,
            fixtureURL: fixtureURL
        )
        let outputDirectory = environment["SHADECAM_RENDER_OUTPUT_DIR"].map { URL(filePath: $0) }
            ?? injectedFixture.map { _ in URL(filePath: "/tmp/shadecam-renders") }

        if let outputDirectory {
            try FileManager.default.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true
            )
        }

        let passthroughOutput = try renderer.render(
            pipeline: compiler.pipelineStore.snapshot().artifact.pipeline
        )

        for preset in presets {
            let artifact = try await compiler.compile(preset.source(in: bundle))
            let output = try renderer.render(pipeline: artifact.pipeline)
            XCTAssertGreaterThan(output.dynamicRange, 24, preset.resourceName)
            if preset != passthrough {
                XCTAssertGreaterThan(
                    output.meanAbsoluteDifference(from: passthroughOutput),
                    2,
                    preset.resourceName
                )
            }
            if let outputDirectory {
                try output.writePNG(to: outputDirectory.appending(path: "\(preset.resourceName).png"))
            }
        }

        for resourceName in ["disintegrate", "invisible"] {
            let preset = ShaderPreset(resourceName: resourceName)
            let artifact = try await compiler.compile(preset.source(in: bundle))
            let output = try renderer.render(
                pipeline: artifact.pipeline,
                hasCapturedPlate: false
            )
            XCTAssertGreaterThan(output.dynamicRange, 24, resourceName)
            XCTAssertGreaterThan(
                output.meanAbsoluteDifference(from: passthroughOutput),
                2,
                resourceName
            )
        }
    }
}

private final class ShaderPresetFixtureRenderer {
    private let width = 512
    private let height = 640
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let sampler: MTLSamplerState
    private let camera: MTLTexture
    private let mask: MTLTexture
    private let plate: MTLTexture
    private let uncapturedPlate: MTLTexture
    private let signals: MTLTexture
    private let flow: MTLTexture
    private let depth: MTLTexture

    init(device: MTLDevice, fixtureURL: URL?) throws {
        self.device = device
        commandQueue = try XCTUnwrap(device.makeCommandQueue())

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        sampler = try XCTUnwrap(device.makeSamplerState(descriptor: samplerDescriptor))

        let fixture = try Self.makeFixture(at: fixtureURL, width: width, height: height)
        let cameraTexture = try Self.makeTexture(
            device: device,
            format: .rgba8Unorm,
            width: width,
            height: height,
            bytes: fixture.color,
            bytesPerRow: width * 4
        )
        camera = cameraTexture
        mask = try Self.makeTexture(
            device: device,
            format: .r16Float,
            width: width,
            height: height,
            bytes: fixture.mask.map { Float16($0).bitPattern },
            bytesPerRow: width * MemoryLayout<UInt16>.stride
        )
        plate = try Self.makeTexture(
            device: device,
            format: .rgba8Unorm,
            width: width,
            height: height,
            bytes: fixture.plate,
            bytesPerRow: width * 4
        )
        uncapturedPlate = try Self.makeTexture(
            device: device,
            format: .rgba8Unorm,
            width: width,
            height: height,
            bytes: [UInt8](repeating: 0, count: width * height * 4),
            bytesPerRow: width * 4
        )
        signals = try Self.makeSignals(device: device)
        flow = try Self.makeFlow(device: device, width: width, height: height)
        depth = try Self.makeDepth(
            device: device,
            width: width,
            height: height,
            mask: fixture.mask
        )
    }

    func render(
        pipeline: MTLRenderPipelineState,
        hasCapturedPlate: Bool = true
    ) throws -> ShaderFixtureOutput {
        let feedback = try (0..<2).map { _ in
            try Self.makeTexture(
                device: device,
                format: .bgra8Unorm,
                width: width,
                height: height,
                bytes: [UInt8](repeating: 0, count: width * height * 4),
                bytesPerRow: width * 4,
                usage: [.renderTarget, .shaderRead]
            )
        }
        var readIndex = 0

        for frame in 0..<4 {
            let writeIndex = 1 - readIndex
            let commandBuffer = try XCTUnwrap(commandQueue.makeCommandBuffer())
            let descriptor = MTLRenderPassDescriptor()
            descriptor.colorAttachments[0].texture = feedback[writeIndex]
            descriptor.colorAttachments[0].loadAction = .clear
            descriptor.colorAttachments[0].storeAction = .store
            descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
            let encoder = try XCTUnwrap(commandBuffer.makeRenderCommandEncoder(descriptor: descriptor))
            var uniforms = makeUniforms(frame: frame)
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.stride, index: 0)
            encoder.setFragmentTexture(camera, index: 0)
            encoder.setFragmentTexture(mask, index: 1)
            encoder.setFragmentTexture(feedback[readIndex], index: 2)
            encoder.setFragmentTexture(hasCapturedPlate ? plate : uncapturedPlate, index: 3)
            encoder.setFragmentTexture(signals, index: 4)
            encoder.setFragmentTexture(flow, index: 5)
            encoder.setFragmentTexture(depth, index: 6)
            encoder.setFragmentSamplerState(sampler, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            if let error = commandBuffer.error {
                throw error
            }
            readIndex = writeIndex
        }

        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        feedback[readIndex].getBytes(
            &bytes,
            bytesPerRow: width * 4,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0
        )
        return ShaderFixtureOutput(width: width, height: height, bgra: bytes)
    }

    private func makeUniforms(frame: Int) -> ShaderUniforms {
        var events = ShaderEventUniforms()
        events[0] = SIMD4(0.72, 0.38 + Float(frame) * 0.04, 0.28, 0.38)
        events[1] = SIMD4(0.58, 0.22, 0.58, 0.42)
        events[2] = SIMD4(0.88, 0.24, 0.68, 0.38)
        events[3] = SIMD4(0.64, 0.31, 0.52, 0.5)
        events[4] = SIMD4(0.46, 0.18, 0.5, 0.36)
        events[7] = SIMD4(0.74, 0.95, 0.62, 0.46)

        var hands = ShaderHandUniforms()
        let leftHand = [
            SIMD2<Float>(0.29, 0.72), SIMD2(0.24, 0.68), SIMD2(0.21, 0.62), SIMD2(0.19, 0.56), SIMD2(0.17, 0.5),
            SIMD2(0.26, 0.62), SIMD2(0.25, 0.53), SIMD2(0.24, 0.45), SIMD2(0.23, 0.37),
            SIMD2(0.3, 0.61), SIMD2(0.3, 0.51), SIMD2(0.3, 0.42), SIMD2(0.3, 0.33),
            SIMD2(0.34, 0.63), SIMD2(0.35, 0.54), SIMD2(0.36, 0.46), SIMD2(0.37, 0.39),
            SIMD2(0.38, 0.66), SIMD2(0.4, 0.59), SIMD2(0.42, 0.53), SIMD2(0.44, 0.47),
        ]
        for joint in 0..<21 {
            let left = leftHand[joint]
            let right = SIMD2<Float>(1 - left.x, left.y)
            hands[0, joint] = SIMD4(left.x, left.y, 0.96, 0)
            hands[1, joint] = SIMD4(right.x, right.y, 0.96, 0)
        }

        var body = ShaderBodyUniforms()
        let points: [SIMD2<Float>] = [
            SIMD2(0.5, 0.24), SIMD2(0.47, 0.22), SIMD2(0.53, 0.22), SIMD2(0.44, 0.24), SIMD2(0.56, 0.24),
            SIMD2(0.5, 0.38), SIMD2(0.38, 0.42), SIMD2(0.62, 0.42), SIMD2(0.31, 0.56), SIMD2(0.69, 0.56),
            SIMD2(0.26, 0.7), SIMD2(0.74, 0.7), SIMD2(0.5, 0.65), SIMD2(0.43, 0.66), SIMD2(0.57, 0.66),
            SIMD2(0.41, 0.82), SIMD2(0.59, 0.82), SIMD2(0.39, 0.96), SIMD2(0.61, 0.96),
        ]
        for joint in 0..<ShaderBodyUniforms.count {
            body[joint] = SIMD4(points[joint].x, points[joint].y, 0.96, 0)
        }

        return ShaderUniforms(
            iMouse: SIMD4(Float(width) * 0.66, Float(height) * 0.4, Float(width) * 0.66, Float(height) * 0.4),
            iFaceRect: SIMD4(0.33, 0.13, 0.34, 0.36),
            iExpression: SIMD4(0.48, 0.16, 0.72, 0.58),
            iAudio: SIMD4(0.62, 0.84, 0.58, 0.72),
            iEvents: events,
            iHands: hands,
            iBody: body,
            iResolution: SIMD2(Float(width), Float(height)),
            iTime: 1.8 + Float(frame) * 0.12,
            iTimeDelta: 0.12,
            iFrame: UInt32(frame)
        )
    }

    private static func makeFixture(
        at url: URL?,
        width: Int,
        height: Int
    ) throws -> ShaderFixture {
        if let url {
            return try loadFixture(at: url, width: width, height: height)
        }

        var color = [UInt8](repeating: 0, count: width * height * 4)
        var plate = [UInt8](repeating: 0, count: width * height * 4)
        var mask = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let uv = SIMD2(Float(x) / Float(width), Float(y) / Float(height))
                let head = pow((uv.x - 0.5) / 0.18, 2) + pow((uv.y - 0.3) / 0.21, 2) < 1
                let torso = pow((uv.x - 0.5) / 0.34, 2) + pow((uv.y - 0.76) / 0.42, 2) < 1
                let person = head || torso
                let index = (y * width + x) * 4
                let glow = max(0, 1 - hypot(uv.x - 0.22, uv.y - 0.28) * 2.4)
                let background = SIMD3<Float>(0.015 + glow * 0.08, 0.025 + glow * 0.14, 0.07 + glow * 0.2)
                let skin = SIMD3<Float>(0.72, 0.39, 0.28) * (0.72 + uv.x * 0.4)
                let cloth = SIMD3<Float>(0.08, 0.15, 0.22) + SIMD3<Float>(repeating: uv.y * 0.08)
                let sample = person ? (head ? skin : cloth) : background
                color[index] = UInt8(saturating: sample.x * 255)
                color[index + 1] = UInt8(saturating: sample.y * 255)
                color[index + 2] = UInt8(saturating: sample.z * 255)
                color[index + 3] = 255
                plate[index] = UInt8(saturating: background.x * 255)
                plate[index + 1] = UInt8(saturating: background.y * 255)
                plate[index + 2] = UInt8(saturating: background.z * 255)
                plate[index + 3] = 255
                mask[y * width + x] = person ? 1 : 0
            }
        }
        return ShaderFixture(color: color, mask: mask, plate: plate)
    }

    private static func loadFixture(at url: URL, width: Int, height: Int) throws -> ShaderFixture {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var color = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(
            CGContext(
                data: &color,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        let scale = max(CGFloat(width) / CGFloat(image.width), CGFloat(height) / CGFloat(image.height))
        let drawSize = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        context.interpolationQuality = .high
        context.draw(
            image,
            in: CGRect(
                x: (CGFloat(width) - drawSize.width) * 0.5,
                y: (CGFloat(height) - drawSize.height) * 0.5,
                width: drawSize.width,
                height: drawSize.height
            )
        )
        var mask = [Float](repeating: 0, count: width * height)
        for pixel in 0..<(width * height) {
            let index = pixel * 4
            let luminance = Float(color[index]) * 0.2126
                + Float(color[index + 1]) * 0.7152
                + Float(color[index + 2]) * 0.0722
            let x = Float(pixel % width) / Float(width)
            let y = Float(pixel / width) / Float(height)
            let head = pow((x - 0.5) / 0.25, 2) + pow((y - 0.34) / 0.3, 2) < 1
            mask[pixel] = luminance / 255 > 0.032 || head ? 1 : 0
        }
        var plate = color
        for y in 0..<height {
            let left = (y * width + 4) * 4
            let right = (y * width + width - 5) * 4
            let background = (0..<3).map { channel in
                UInt8((UInt16(color[left + channel]) + UInt16(color[right + channel])) / 2)
            }
            for x in 0..<width where mask[y * width + x] > 0 {
                let index = (y * width + x) * 4
                plate[index] = background[0]
                plate[index + 1] = background[1]
                plate[index + 2] = background[2]
                plate[index + 3] = 255
            }
        }
        return ShaderFixture(color: color, mask: mask, plate: plate)
    }

    private static func makeSignals(device: MTLDevice) throws -> MTLTexture {
        let width = 256
        let height = 4
        var values = [UInt16](repeating: 0, count: width * height)
        for x in 0..<width {
            let position = Float(x) / Float(width - 1)
            let spectrum = 0.12 + pow(sin(position * .pi * 5.0) * 0.5 + 0.5, 2) * (1 - position * 0.62)
            let waveform = sin(position * .pi * 12.0) * 0.38 + sin(position * .pi * 27.0) * 0.12 + 0.5
            values[x] = Float16(spectrum).bitPattern
            values[width + x] = Float16(waveform).bitPattern
        }
        return try makeTexture(
            device: device,
            format: .r16Float,
            width: width,
            height: height,
            bytes: values,
            bytesPerRow: width * MemoryLayout<UInt16>.stride
        )
    }

    private static func makeFlow(device: MTLDevice, width: Int, height: Int) throws -> MTLTexture {
        var values = [SIMD2<Float16>](repeating: .zero, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let point = SIMD2(Float(x) / Float(width) - 0.5, Float(y) / Float(height) - 0.5)
                let falloff = max(0, 1 - sqrt(point.x * point.x + point.y * point.y) * 1.7)
                values[y * width + x] = SIMD2(Float16(-point.y * 18 * falloff), Float16(point.x * 18 * falloff))
            }
        }
        return try makeTexture(
            device: device,
            format: .rg16Float,
            width: width,
            height: height,
            bytes: values,
            bytesPerRow: width * MemoryLayout<SIMD2<Float16>>.stride
        )
    }

    private static func makeDepth(
        device: MTLDevice,
        width: Int,
        height: Int,
        mask: [Float]
    ) throws -> MTLTexture {
        var values = [UInt16](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let position = y * width + x
                let background = 0.14 + Float(y) / Float(height) * 0.18
                let person = 0.72 + (1 - Float(y) / Float(height)) * 0.22
                values[position] = Float16(background + (person - background) * mask[position]).bitPattern
            }
        }
        return try makeTexture(
            device: device,
            format: .r16Float,
            width: width,
            height: height,
            bytes: values,
            bytesPerRow: width * MemoryLayout<UInt16>.stride
        )
    }

    private static func makeTexture<Bytes>(
        device: MTLDevice,
        format: MTLPixelFormat,
        width: Int,
        height: Int,
        bytes: [Bytes],
        bytesPerRow: Int,
        usage: MTLTextureUsage = .shaderRead
    ) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = usage
        let texture = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        bytes.withUnsafeBytes {
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0,
                withBytes: $0.baseAddress!,
                bytesPerRow: bytesPerRow
            )
        }
        return texture
    }
}

private struct ShaderFixture {
    let color: [UInt8]
    let mask: [Float]
    let plate: [UInt8]
}

private struct ShaderFixtureOutput {
    let width: Int
    let height: Int
    let bgra: [UInt8]

    var dynamicRange: UInt8 {
        var minimum = UInt8.max
        var maximum = UInt8.min
        for index in stride(from: 0, to: bgra.count, by: 4) {
            minimum = min(minimum, min(bgra[index], min(bgra[index + 1], bgra[index + 2])))
            maximum = max(maximum, max(bgra[index], max(bgra[index + 1], bgra[index + 2])))
        }
        return maximum - minimum
    }

    func meanAbsoluteDifference(from other: ShaderFixtureOutput) -> Double {
        precondition(width == other.width && height == other.height)
        var difference: UInt64 = 0
        for index in stride(from: 0, to: bgra.count, by: 4) {
            difference += UInt64(abs(Int(bgra[index]) - Int(other.bgra[index])))
            difference += UInt64(abs(Int(bgra[index + 1]) - Int(other.bgra[index + 1])))
            difference += UInt64(abs(Int(bgra[index + 2]) - Int(other.bgra[index + 2])))
        }
        return Double(difference) / Double(width * height * 3)
    }

    func writePNG(to url: URL) throws {
        var rgba = bgra
        for index in stride(from: 0, to: rgba.count, by: 4) {
            rgba.swapAt(index, index + 2)
            rgba[index + 3] = 255
        }
        let data = Data(rgba)
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let image = try XCTUnwrap(
            CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
            )
        )
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}

private extension UInt8 {
    init(saturating value: Float) {
        self = UInt8(Swift.min(Swift.max(value, 0), 255))
    }
}
