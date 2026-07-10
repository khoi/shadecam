import CoreVideo
import Foundation
import Vision

actor FaceExpressionService {
    private let signalBus: SignalBus
    private let calibrationStore: ExpressionCalibrationStore
    private let request = DetectFaceLandmarksRequest()
    private var tracker: ExpressionScoreTracker
    private var smileTrigger = SmileTriggerMapper()
    private var isProcessing = false

    init(signalBus: SignalBus) {
        let calibrationStore = ExpressionCalibrationStore()
        self.signalBus = signalBus
        self.calibrationStore = calibrationStore
        tracker = ExpressionScoreTracker(baseline: calibrationStore.load() ?? .default)
    }

    func process(_ frame: SendablePixelBuffer, at timestamp: TimeInterval) async {
        guard !isProcessing else {
            return
        }
        isProcessing = true
        defer {
            isProcessing = false
        }

        guard let observations = try? await request.perform(on: frame.value) else {
            return
        }
        guard let primary = observations.max(by: {
            $0.boundingBox.width * $0.boundingBox.height
                < $1.boundingBox.width * $1.boundingBox.height
        }) else {
            clear(at: timestamp)
            return
        }
        guard
            let landmarks = primary.landmarks,
            let geometry = ExpressionGeometry.measure(
                expressionLandmarks(
                    landmarks,
                    boundingBox: primary.boundingBox.cgRect,
                    imageSize: CGSize(
                        width: CVPixelBufferGetWidth(frame.value),
                        height: CVPixelBufferGetHeight(frame.value)
                    )
                )
            )
        else {
            return
        }

        let scores = tracker.update(
            geometry,
            yawDegrees: primary.yaw.converted(to: .degrees).value,
            pitchDegrees: primary.pitch.converted(to: .degrees).value
        )
        signalBus.write(scores.vector, to: SignalNames.expression, at: timestamp)
        if smileTrigger.shouldTrigger(smile: scores.smile, at: timestamp) {
            let boundingBox = primary.boundingBox.cgRect
            signalBus.trigger(
                SignalNames.smileEvent,
                at: timestamp,
                position: SIMD2(
                    Float(boundingBox.midX),
                    1 - Float(boundingBox.midY)
                )
            )
        }
    }

    func clear(at timestamp: TimeInterval) {
        tracker.clear()
        smileTrigger = SmileTriggerMapper()
        signalBus.write(.zero, to: SignalNames.expression, at: timestamp)
    }

    func calibrateNeutral(at timestamp: TimeInterval) -> Bool {
        guard let baseline = tracker.calibrate() else {
            return false
        }
        calibrationStore.save(baseline)
        signalBus.write(tracker.scores.vector, to: SignalNames.expression, at: timestamp)
        _ = smileTrigger.shouldTrigger(smile: tracker.scores.smile, at: timestamp)
        return true
    }

    private func expressionLandmarks(
        _ landmarks: FaceObservation.Landmarks2D,
        boundingBox: CGRect,
        imageSize: CGSize
    ) -> ExpressionLandmarks {
        func points(_ region: FaceObservation.Landmarks2D.Region) -> [SIMD2<Float>] {
            ExpressionLandmarkGeometry.points(
                region.points.map(\.cgPoint),
                in: boundingBox,
                imageSize: imageSize
            )
        }

        return ExpressionLandmarks(
            leftEye: points(landmarks.leftEye),
            rightEye: points(landmarks.rightEye),
            leftEyebrow: points(landmarks.leftEyebrow),
            rightEyebrow: points(landmarks.rightEyebrow),
            outerLips: points(landmarks.outerLips),
            innerLips: points(landmarks.innerLips)
        )
    }
}
