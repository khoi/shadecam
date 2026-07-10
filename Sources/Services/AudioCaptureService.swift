@preconcurrency import AVFoundation
import Foundation

final class AudioCaptureService: @unchecked Sendable {
    let signalTextureStore: SignalTextureStore

    private let signalBus: SignalBus
    private let engine = AVAudioEngine()
    private let processingQueue = DispatchQueue(label: "app.supabit.shadecam.audio")
    private let stateLock = NSLock()
    private var dsp = AudioDSP()
    private var enabled = false
    private var tapInstalled = false

    init(signalBus: SignalBus, signalTextureStore: SignalTextureStore) {
        self.signalBus = signalBus
        self.signalTextureStore = signalTextureStore
    }

    func setNeeds(_ needs: Set<ShaderNeed>) {
        if needs.contains(.audio) {
            start()
        } else {
            stop()
        }
    }

    func stop() {
        let shouldStop = stateLock.withLock {
            defer {
                enabled = false
            }
            return enabled || tapInstalled
        }
        guard shouldStop else {
            return
        }
        processingQueue.async { [self] in
            stopEngine()
            signalTextureStore.clear()
            signalBus.write(.zero, to: SignalNames.audio, at: ProcessInfo.processInfo.systemUptime)
        }
    }

    private func start() {
        let shouldStart = stateLock.withLock {
            guard !enabled else {
                return false
            }
            enabled = true
            return true
        }
        guard shouldStart else {
            return
        }

        Task { [self] in
            let authorized = switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                true
            case .notDetermined:
                await AVCaptureDevice.requestAccess(for: .audio)
            default:
                false
            }
            guard authorized, isEnabled else {
                stateLock.withLock {
                    enabled = false
                }
                return
            }
            processingQueue.async { [self] in
                startEngine()
            }
        }
    }

    private var isEnabled: Bool {
        stateLock.withLock {
            enabled
        }
    }

    private func startEngine() {
        guard isEnabled, !engine.isRunning else {
            return
        }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            stateLock.withLock {
                enabled = false
            }
            return
        }
        input.installTap(
            onBus: 0,
            bufferSize: AVAudioFrameCount(dsp.fftSize),
            format: format
        ) { [weak self] buffer, time in
            self?.receive(buffer, at: time)
        }
        stateLock.withLock {
            tapInstalled = true
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            stopEngine()
            stateLock.withLock {
                enabled = false
            }
        }
    }

    private func stopEngine() {
        if engine.isRunning {
            engine.stop()
        }
        let shouldRemoveTap = stateLock.withLock {
            defer {
                tapInstalled = false
            }
            return tapInstalled
        }
        if shouldRemoveTap {
            engine.inputNode.removeTap(onBus: 0)
        }
        engine.reset()
        dsp = AudioDSP()
    }

    private func receive(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
        guard isEnabled, let channels = buffer.floatChannelData else {
            return
        }
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameCount > 0, channelCount > 0 else {
            return
        }

        let samples: [Float]
        if buffer.format.isInterleaved {
            let channel = channels[0]
            samples = (0..<frameCount).map { frame in
                let offset = frame * channelCount
                return (0..<channelCount).reduce(0) { $0 + channel[offset + $1] } / Float(channelCount)
            }
        } else {
            samples = (0..<frameCount).map { frame in
                (0..<channelCount).reduce(0) { $0 + channels[$1][frame] } / Float(channelCount)
            }
        }
        let sampleRate = Float(buffer.format.sampleRate)
        let timestamp = time.hostTime == 0
            ? ProcessInfo.processInfo.systemUptime
            : AVAudioTime.seconds(forHostTime: time.hostTime)
        processingQueue.async { [self, samples] in
            guard isEnabled else {
                return
            }
            let output = dsp.process(samples, sampleRate: sampleRate)
            signalTextureStore.update(
                SignalTextureFrame(spectrum: output.spectrum, waveform: output.waveform)
            )
            signalBus.write(output.audio, to: SignalNames.audio, at: timestamp)
        }
    }
}
