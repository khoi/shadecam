import CoreVideo
import Vision

actor PersonSegmentationService {
    private let maskStore: PixelBufferStore
    private let request: GeneratePersonSegmentationRequest
    private var isProcessing = false

    init(maskStore: PixelBufferStore) {
        self.maskStore = maskStore
        request = GeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormatType = kCVPixelFormatType_OneComponent16Half
    }

    func process(_ frame: SendablePixelBuffer) async {
        guard !isProcessing else {
            return
        }

        isProcessing = true
        defer {
            isProcessing = false
        }

        guard let observation = try? await request.perform(on: frame.value) else {
            return
        }

        let width = Int(observation.size.width)
        let height = Int(observation.size.height)
        let attributes = [
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ] as CFDictionary
        var destination: CVPixelBuffer?
        guard CVPixelBufferCreate(
            nil,
            width,
            height,
            observation.pixelFormat,
            attributes,
            &destination
        ) == kCVReturnSuccess,
        let destination
        else {
            return
        }

        let sourceBytesPerRow = width * MemoryLayout<UInt16>.stride
        CVPixelBufferLockBaseAddress(destination, [])
        defer {
            CVPixelBufferUnlockBaseAddress(destination, [])
        }

        guard let destinationBaseAddress = CVPixelBufferGetBaseAddress(destination) else {
            return
        }
        let destinationBytesPerRow = CVPixelBufferGetBytesPerRow(destination)

        observation.withUnsafePointer { sourceBaseAddress in
            for row in 0..<height {
                memcpy(
                    destinationBaseAddress.advanced(by: row * destinationBytesPerRow),
                    sourceBaseAddress.advanced(by: row * sourceBytesPerRow),
                    sourceBytesPerRow
                )
            }
        }
        maskStore.update(destination)
    }
}
