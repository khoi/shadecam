@preconcurrency import AVFoundation
import CoreVideo
import Foundation

final class CameraCaptureService: NSObject, @unchecked Sendable {
    let frameStore = CameraFrameStore()

    private let captureQueue = DispatchQueue(label: "app.supabit.shadecam.capture")
    private let session = AVCaptureSession()
    private var configured = false

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

        frameStore.update(frame)
    }
}
