@preconcurrency import AVFoundation
import CoreVideo
import Foundation

final class CameraCaptureService: NSObject, @unchecked Sendable {
    let frameStore = PixelBufferStore()
    let frameDimensions = CameraFrameDimensions()
    let maskStore: PixelBufferStore
    let faceRectStore: FaceRectStore

    private let captureQueue = DispatchQueue(label: "app.supabit.shadecam.capture")
    private let session = AVCaptureSession()
    private let segmentation: PersonSegmentationService
    private let faceDetection: FaceDetectionService
    private var capturedFrameCount = 0
    private var configured = false

    override init() {
        let maskStore = PixelBufferStore()
        let faceRectStore = FaceRectStore()
        self.maskStore = maskStore
        self.faceRectStore = faceRectStore
        segmentation = PersonSegmentationService(maskStore: maskStore)
        faceDetection = FaceDetectionService(faceRectStore: faceRectStore)
        super.init()
    }

    func start() async {
        let authorized = switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            true
        case .notDetermined:
            await AVCaptureDevice.requestAccess(for: .video)
        default:
            false
        }

        guard authorized else {
            return
        }

        captureQueue.async { [self] in
            configureIfNeeded()
            session.startRunning()
        }
    }

    func stop() {
        captureQueue.async { [self] in
            session.stopRunning()
        }
    }

    func setSegmentationQuality(_ quality: SegmentationQuality) {
        Task { [segmentation] in
            await segmentation.setQuality(quality)
        }
    }

    private func configureIfNeeded() {
        guard !configured else {
            return
        }

        guard
            let device = AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device)
        else {
            return
        }

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange),
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: captureQueue)

        session.beginConfiguration()
        if session.canAddInput(input) {
            session.addInput(input)
        }
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        session.commitConfiguration()
        configured = true
    }
}

extension CameraCaptureService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let frame = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        if capturedFrameCount == 0 {
            let width = CVPixelBufferGetWidth(frame)
            let height = CVPixelBufferGetHeight(frame)
            Task { @MainActor [frameDimensions] in
                frameDimensions.update(width: width, height: height)
            }
        }
        frameStore.update(frame)
        let segmentationFrame = SendablePixelBuffer(value: frame)
        Task { [segmentation, segmentationFrame] in
            await segmentation.process(segmentationFrame)
        }
        capturedFrameCount += 1
        if capturedFrameCount.isMultiple(of: 10) {
            Task { [faceDetection, segmentationFrame] in
                await faceDetection.process(segmentationFrame)
            }
        }
    }
}
