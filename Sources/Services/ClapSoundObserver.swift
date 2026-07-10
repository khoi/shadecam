@preconcurrency import SoundAnalysis
import Foundation

final class ClapSoundObserver: NSObject, SNResultsObserving, @unchecked Sendable {
    private let signalBus: SignalBus
    private let lock = NSLock()
    private var mapper = ClapTriggerMapper()

    init(signalBus: SignalBus) {
        self.signalBus = signalBus
    }

    func request(_ request: any SNRequest, didProduce result: any SNResult) {
        guard let result = result as? SNClassificationResult else {
            return
        }
        let classifications = result.classifications.map {
            SoundClassification(identifier: $0.identifier, confidence: $0.confidence)
        }
        let timestamp = ProcessInfo.processInfo.systemUptime
        let shouldTrigger = lock.withLock {
            mapper.shouldTrigger(classifications: classifications, at: timestamp)
        }
        if shouldTrigger {
            signalBus.trigger(SignalNames.clapEvent, at: timestamp, position: SIMD2(repeating: 0.5))
        }
    }
}
