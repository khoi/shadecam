import Accelerate
import Foundation

struct AudioBands: Equatable, Sendable {
    let bass: Float
    let mid: Float
    let treble: Float
}

struct AudioDSPOutput: Equatable, Sendable {
    let spectrum: [Float]
    let waveform: [Float]
    let audio: SIMD4<Float>
}

enum AudioDSPMath {
    static func logBinEdges(
        count: Int = SignalTextureFrame.width,
        minimumFrequency: Float = 20,
        maximumFrequency: Float = 20_000
    ) -> [Float] {
        precondition(count > 0)
        precondition(minimumFrequency > 0)
        precondition(maximumFrequency > minimumFrequency)
        let ratio = maximumFrequency / minimumFrequency
        return (0...count).map { index in
            minimumFrequency * pow(ratio, Float(index) / Float(count))
        }
    }

    static func logBinnedSpectrum(
        _ magnitudes: [Float],
        sampleRate: Float,
        fftSize: Int,
        edges: [Float] = logBinEdges()
    ) -> [Float] {
        precondition(edges.count >= 2)
        precondition(sampleRate > 0)
        precondition(fftSize > 0)
        guard !magnitudes.isEmpty else {
            return [Float](repeating: 0, count: edges.count - 1)
        }

        let frequencyStep = sampleRate / Float(fftSize)
        return zip(edges, edges.dropFirst()).map { lowerFrequency, upperFrequency in
            let lowerIndex = max(Int(ceil(lowerFrequency / frequencyStep)), 1)
            let upperIndex = max(Int(ceil(upperFrequency / frequencyStep)), lowerIndex + 1)
            let range = lowerIndex..<min(upperIndex, magnitudes.count)
            if !range.isEmpty {
                return range.reduce(0) { max($0, magnitudes[$1]) }
            }
            let centerFrequency = sqrt(lowerFrequency * upperFrequency)
            let index = min(max(Int((centerFrequency / frequencyStep).rounded()), 0), magnitudes.count - 1)
            return magnitudes[index]
        }
    }

    static func bandLevels(
        _ magnitudes: [Float],
        sampleRate: Float,
        fftSize: Int
    ) -> AudioBands {
        AudioBands(
            bass: level(in: 20..<250, magnitudes: magnitudes, sampleRate: sampleRate, fftSize: fftSize),
            mid: level(in: 250..<4_000, magnitudes: magnitudes, sampleRate: sampleRate, fftSize: fftSize),
            treble: level(in: 4_000..<20_000, magnitudes: magnitudes, sampleRate: sampleRate, fftSize: fftSize)
        )
    }

    static func downsampleWaveform(_ samples: [Float], count: Int = SignalTextureFrame.width) -> [Float] {
        precondition(count > 0)
        guard !samples.isEmpty else {
            return [Float](repeating: 0, count: count)
        }

        return (0..<count).map { index in
            let lower = index * samples.count / count
            let upper = max((index + 1) * samples.count / count, lower + 1)
            let range = lower..<min(upper, samples.count)
            return range.reduce(0) { $0 + samples[$1] } / Float(range.count)
        }
    }

    private static func level(
        in frequencies: Range<Float>,
        magnitudes: [Float],
        sampleRate: Float,
        fftSize: Int
    ) -> Float {
        precondition(sampleRate > 0)
        precondition(fftSize > 0)
        let frequencyStep = sampleRate / Float(fftSize)
        let values = magnitudes.indices.lazy.filter { index in
            frequencies.contains(Float(index) * frequencyStep)
        }.map { magnitudes[$0] }
        guard !values.isEmpty else {
            return 0
        }
        return sqrt(values.reduce(0) { $0 + $1 * $1 } / Float(values.count))
    }
}

struct SoftAudioAGC: Sendable {
    let attack: Float
    let release: Float
    let floor: Float
    private(set) var runningPeak: Float = 0

    init(attack: Float = 0.5, release: Float = 0.02, floor: Float = 0.000_1) {
        precondition((0...1).contains(attack))
        precondition((0...1).contains(release))
        precondition(floor > 0)
        self.attack = attack
        self.release = release
        self.floor = floor
    }

    mutating func scale(for peak: Float) -> Float {
        let peak = max(peak, 0)
        if runningPeak == 0 {
            runningPeak = peak
        } else {
            let coefficient = peak > runningPeak ? attack : release
            runningPeak += coefficient * (peak - runningPeak)
        }
        return 1 / max(runningPeak, floor)
    }

    func normalize(_ value: Float, scale: Float) -> Float {
        min(max(value * scale, 0), 1)
    }
}

final class AudioDSP {
    let fftSize: Int

    private let log2FFTSize: vDSP_Length
    private let setup: FFTSetup
    private let window: [Float]
    private var agc: SoftAudioAGC

    init(fftSize: Int = 1_024, agc: SoftAudioAGC = SoftAudioAGC()) {
        precondition(fftSize > 1 && fftSize.nonzeroBitCount == 1)
        let log2FFTSize = vDSP_Length(log2(Float(fftSize)))
        guard let setup = vDSP_create_fftsetup(log2FFTSize, FFTRadix(kFFTRadix2)) else {
            fatalError("FFT setup could not be created")
        }
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        self.fftSize = fftSize
        self.log2FFTSize = log2FFTSize
        self.setup = setup
        self.window = window
        self.agc = agc
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
    }

    func process(_ samples: [Float], sampleRate: Float) -> AudioDSPOutput {
        precondition(sampleRate > 0)
        var input = [Float](repeating: 0, count: fftSize)
        input.replaceSubrange(0..<min(samples.count, fftSize), with: samples.prefix(fftSize))
        let magnitudes = magnitudeSpectrum(input)
        let rawSpectrum = AudioDSPMath.logBinnedSpectrum(
            magnitudes,
            sampleRate: sampleRate,
            fftSize: fftSize
        )
        let bands = AudioDSPMath.bandLevels(magnitudes, sampleRate: sampleRate, fftSize: fftSize)
        var rms: Float = 0
        vDSP_rmsqv(input, 1, &rms, vDSP_Length(input.count))
        let audio = SIMD4(rms, bands.bass, bands.mid, bands.treble)
        let peak = max(rawSpectrum.max() ?? 0, audio.max())
        let scale = agc.scale(for: peak)
        let spectrum = rawSpectrum.map { agc.normalize($0, scale: scale) }
        let waveform = AudioDSPMath.downsampleWaveform(input).map {
            min(max(0.5 + 0.5 * $0 * scale, 0), 1)
        }
        return AudioDSPOutput(
            spectrum: spectrum,
            waveform: waveform,
            audio: SIMD4(
                agc.normalize(audio.x, scale: scale),
                agc.normalize(audio.y, scale: scale),
                agc.normalize(audio.z, scale: scale),
                agc.normalize(audio.w, scale: scale)
            )
        )
    }

    private func magnitudeSpectrum(_ input: [Float]) -> [Float] {
        var windowed = [Float](repeating: 0, count: fftSize)
        vDSP_vmul(input, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))
        var real = [Float](repeating: 0, count: fftSize / 2)
        var imaginary = [Float](repeating: 0, count: fftSize / 2)
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)

        real.withUnsafeMutableBufferPointer { realBuffer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryBuffer in
                var split = DSPSplitComplex(
                    realp: realBuffer.baseAddress!,
                    imagp: imaginaryBuffer.baseAddress!
                )
                windowed.withUnsafeBytes { bytes in
                    let complex = bytes.bindMemory(to: DSPComplex.self)
                    vDSP_ctoz(complex.baseAddress!, 2, &split, 1, vDSP_Length(fftSize / 2))
                }
                vDSP_fft_zrip(setup, &split, 1, log2FFTSize, FFTDirection(kFFTDirection_Forward))
                split.imagp[0] = 0
                vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(magnitudes.count))
            }
        }
        var scale = 2 / Float(fftSize)
        vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(magnitudes.count))
        magnitudes[0] *= 0.5
        return magnitudes
    }
}

private extension SIMD4 where Scalar == Float {
    func max() -> Float {
        Swift.max(x, y, z, w)
    }
}
