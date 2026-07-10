import XCTest
@testable import ShadeCam

final class AudioDSPTests: XCTestCase {
    func testLogBinEdgesAreMonotonicAndSpanAudibleRange() {
        let edges = AudioDSPMath.logBinEdges()

        XCTAssertEqual(edges.count, 257)
        XCTAssertEqual(edges.first!, 20, accuracy: 0.001)
        XCTAssertEqual(edges.last!, 20_000, accuracy: 0.01)
        XCTAssertTrue(zip(edges, edges.dropFirst()).allSatisfy(<))
    }

    func testBandSplitSeparatesSyntheticSpectrum() {
        let sampleRate: Float = 48_000
        let fftSize = 1_024
        let bass = syntheticSpectrum(frequency: 100, sampleRate: sampleRate, fftSize: fftSize)
        let mid = syntheticSpectrum(frequency: 1_000, sampleRate: sampleRate, fftSize: fftSize)
        let treble = syntheticSpectrum(frequency: 8_000, sampleRate: sampleRate, fftSize: fftSize)

        let bassLevels = AudioDSPMath.bandLevels(bass, sampleRate: sampleRate, fftSize: fftSize)
        let midLevels = AudioDSPMath.bandLevels(mid, sampleRate: sampleRate, fftSize: fftSize)
        let trebleLevels = AudioDSPMath.bandLevels(treble, sampleRate: sampleRate, fftSize: fftSize)

        XCTAssertGreaterThan(bassLevels.bass, 0)
        XCTAssertEqual(bassLevels.mid, 0)
        XCTAssertEqual(bassLevels.treble, 0)
        XCTAssertEqual(midLevels.bass, 0)
        XCTAssertGreaterThan(midLevels.mid, 0)
        XCTAssertEqual(midLevels.treble, 0)
        XCTAssertEqual(trebleLevels.bass, 0)
        XCTAssertEqual(trebleLevels.mid, 0)
        XCTAssertGreaterThan(trebleLevels.treble, 0)
    }

    func testAGCStaysBoundedAndRecoversAfterPeak() {
        var agc = SoftAudioAGC(attack: 0.5, release: 0.5)

        let initialScale = agc.scale(for: 1)
        let quietScale = agc.scale(for: 0.1)
        let firstQuiet = agc.normalize(0.1, scale: quietScale)
        let recoveredScale = agc.scale(for: 0.1)
        let recoveredQuiet = agc.normalize(0.1, scale: recoveredScale)
        let loudScale = agc.scale(for: 10)

        XCTAssertEqual(agc.normalize(1, scale: initialScale), 1)
        XCTAssertGreaterThan(recoveredQuiet, firstQuiet)
        XCTAssertEqual(agc.normalize(10, scale: loudScale), 1)
        XCTAssertGreaterThanOrEqual(agc.runningPeak, 0)
    }

    func testWaveformDownsamplingAveragesEachSegment() {
        let waveform = AudioDSPMath.downsampleWaveform(
            [-1, -1, -0.5, -0.5, 0.5, 0.5, 1, 1],
            count: 4
        )

        XCTAssertEqual(waveform, [-1, -0.5, 0.5, 1])
    }

    private func syntheticSpectrum(frequency: Float, sampleRate: Float, fftSize: Int) -> [Float] {
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)
        magnitudes[Int(frequency / (sampleRate / Float(fftSize)))] = 1
        return magnitudes
    }
}
