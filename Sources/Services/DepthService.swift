import CoreML
import CoreVideo
import Foundation
import Vision

actor DepthService {
    private let depthStore: PixelBufferStore
    private var request: CoreMLRequest?
    private var normalizer = DepthNormalizer()
    private var generation = 0
    private var isProcessing = false

    init(depthStore: PixelBufferStore) {
        self.depthStore = depthStore
    }

    static func isEnabled(for needs: Set<ShaderNeed>) -> Bool {
        needs.contains(.depth)
    }

    func process(_ frame: SendablePixelBuffer) async {
        guard !isProcessing else {
            return
        }

        isProcessing = true
        let generation = generation
        defer {
            isProcessing = false
        }

        guard
            let request = try? depthRequest(),
            let observations = try? await request.perform(on: frame.value),
            generation == self.generation,
            let observation = observations.first(where: { $0 is PixelBufferObservation })
                as? PixelBufferObservation,
            let pixelBuffer = normalize(observation)
        else {
            return
        }
        depthStore.update(pixelBuffer)
    }

    func clear() {
        generation &+= 1
        normalizer.reset()
        depthStore.clear()
    }

    private func depthRequest() throws -> CoreMLRequest {
        if let request {
            return request
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        let model = try DepthAnythingV2SmallF16(configuration: configuration).model
        let container = try CoreMLModelContainer(model: model)
        var request = CoreMLRequest(model: container)
        request.cropAndScaleAction = .scaleToFill
        self.request = request
        return request
    }

    private func normalize(_ observation: PixelBufferObservation) -> CVPixelBuffer? {
        guard
            observation.pixelFormat == kCVPixelFormatType_OneComponent16Half,
            observation.size.width > 0,
            observation.size.height > 0
        else {
            return nil
        }

        let width = Int(observation.size.width)
        let height = Int(observation.size.height)
        return observation.withUnsafePointer { sourceAddress in
            let source = sourceAddress.assumingMemoryBound(to: UInt16.self)
            let count = width * height
            var minimum = Float.greatestFiniteMagnitude
            var maximum = -Float.greatestFiniteMagnitude
            for index in 0..<count {
                let value = Float(Float16(bitPattern: source[index]))
                guard value.isFinite else {
                    continue
                }
                minimum = min(minimum, value)
                maximum = max(maximum, value)
            }
            guard minimum <= maximum else {
                return nil
            }

            normalizer.update(with: DepthRange(minimum: minimum, maximum: maximum))
            guard let range = normalizer.range, let destination = makePixelBuffer(width: width, height: height) else {
                return nil
            }

            CVPixelBufferLockBaseAddress(destination, [])
            defer {
                CVPixelBufferUnlockBaseAddress(destination, [])
            }
            guard let destinationAddress = CVPixelBufferGetBaseAddress(destination) else {
                return nil
            }

            let destinationBytesPerRow = CVPixelBufferGetBytesPerRow(destination)
            for row in 0..<height {
                let destinationRow = destinationAddress
                    .advanced(by: row * destinationBytesPerRow)
                    .assumingMemoryBound(to: UInt16.self)
                let sourceRow = source.advanced(by: row * width)
                for column in 0..<width {
                    let value = Float(Float16(bitPattern: sourceRow[column]))
                    destinationRow[column] = Float16(range.normalize(value)).bitPattern
                }
            }
            return destination
        }
    }

    private func makePixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        let attributes: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:],
            kCVPixelBufferMetalCompatibilityKey: true,
        ]
        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferCreate(
            nil,
            width,
            height,
            kCVPixelFormatType_OneComponent16Half,
            attributes as CFDictionary,
            &pixelBuffer
        ) == kCVReturnSuccess else {
            return nil
        }
        return pixelBuffer
    }
}
