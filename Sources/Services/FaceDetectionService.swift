import CoreVideo
import Vision

actor FaceDetectionService {
    private let signalBus: SignalBus
    private let request = DetectFaceRectanglesRequest()
    private var isProcessing = false

    init(signalBus: SignalBus) {
        self.signalBus = signalBus
    }

    func process(_ frame: SendablePixelBuffer, at timestamp: TimeInterval) async {
        guard !isProcessing else {
            return
        }
        isProcessing = true
        defer {
            isProcessing = false
        }

        guard let faces = try? await request.perform(on: frame.value) else {
            return
        }
        guard let primary = faces.max(by: {
            $0.boundingBox.width * $0.boundingBox.height
                < $1.boundingBox.width * $1.boundingBox.height
        }) else {
            signalBus.write(.zero, to: SignalNames.faceRect, at: timestamp)
            return
        }

        let rect = primary.boundingBox.verticallyFlipped()
        signalBus.write(
            SIMD4(
                Float(rect.origin.x),
                Float(rect.origin.y),
                Float(rect.width),
                Float(rect.height)
            ),
            to: SignalNames.faceRect,
            at: timestamp
        )
    }
}
