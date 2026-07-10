import CoreVideo
import Vision

actor FaceDetectionService {
    private let faceRectStore: FaceRectStore
    private let request = DetectFaceRectanglesRequest()
    private var isProcessing = false

    init(faceRectStore: FaceRectStore) {
        self.faceRectStore = faceRectStore
    }

    func process(_ frame: SendablePixelBuffer) async {
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
            faceRectStore.update(.zero)
            return
        }

        let rect = primary.boundingBox.verticallyFlipped()
        faceRectStore.update(
            SIMD4(
                Float(rect.origin.x),
                Float(rect.origin.y),
                Float(rect.width),
                Float(rect.height)
            )
        )
    }
}
