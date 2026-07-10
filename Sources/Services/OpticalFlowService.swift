import CoreVideo
import Foundation
import Vision

actor OpticalFlowService {
    private let flowStore: PixelBufferStore
    private let request: TrackOpticalFlowRequest
    private var previousFrame: SendablePixelBuffer?
    private var isProcessing = false

    init(flowStore: PixelBufferStore) {
        self.flowStore = flowStore
        let request = TrackOpticalFlowRequest()
        request.computationAccuracy = .low
        request.outputPixelFormatType = request.supportedOutputPixelFormatTypes.contains(
            kCVPixelFormatType_TwoComponent16Half
        ) ? kCVPixelFormatType_TwoComponent16Half : kCVPixelFormatType_TwoComponent32Float
        self.request = request
    }

    static func isEnabled(for needs: Set<ShaderNeed>) -> Bool {
        needs.contains(.flow)
    }

    func process(_ frame: SendablePixelBuffer) async {
        guard !isProcessing else {
            return
        }
        guard let previousFrame else {
            self.previousFrame = frame
            return
        }

        isProcessing = true
        defer {
            self.previousFrame = frame
            isProcessing = false
        }

        let handler = TargetedImageRequestHandler(
            source: previousFrame.value,
            target: frame.value
        )
        guard
            let observation = try? await handler.perform(request),
            let pixelBuffer = makePixelBuffer(from: observation)
        else {
            return
        }
        flowStore.update(pixelBuffer)
    }

    func clear() {
        previousFrame = nil
        flowStore.clear()
    }

    private func makePixelBuffer(from observation: OpticalFlowObservation) -> CVPixelBuffer? {
        guard
            let format = OpticalFlowPixelFormat(cvPixelFormat: observation.pixelFormat),
            observation.size.width > 0,
            observation.size.height > 0
        else {
            return nil
        }

        let width = Int(observation.size.width)
        let height = Int(observation.size.height)
        let attributes: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:],
            kCVPixelBufferMetalCompatibilityKey: true,
        ]
        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferCreate(
            nil,
            width,
            height,
            format.cvPixelFormat,
            attributes as CFDictionary,
            &pixelBuffer
        ) == kCVReturnSuccess, let pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        }
        guard let destination = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }

        let sourceBytesPerRow = width * format.bytesPerPixel
        let destinationBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        observation.withUnsafePointer { source in
            for row in 0..<height {
                destination
                    .advanced(by: row * destinationBytesPerRow)
                    .copyMemory(
                        from: source.advanced(by: row * sourceBytesPerRow),
                        byteCount: sourceBytesPerRow
                    )
            }
        }
        return pixelBuffer
    }
}
