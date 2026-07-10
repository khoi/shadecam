import Foundation

struct SignalTextureFrame: Equatable, Sendable {
    static let width = 256
    static let height = 4
    static let zero = SignalTextureFrame(values: [Float](repeating: 0, count: width * height))

    let values: [Float]

    init(spectrum: [Float], waveform: [Float]) {
        precondition(spectrum.count == Self.width)
        precondition(waveform.count == Self.width)
        values = spectrum + waveform + [Float](repeating: 0, count: Self.width * 2)
    }

    private init(values: [Float]) {
        self.values = values
    }
}

struct SignalTextureSnapshot: Sendable {
    let frame: SignalTextureFrame
    let revision: UInt64
}

final class SignalTextureStore: @unchecked Sendable {
    private let lock = NSLock()
    private var frame = SignalTextureFrame.zero
    private var revision: UInt64 = 0

    func update(_ frame: SignalTextureFrame) {
        lock.withLock {
            self.frame = frame
            revision &+= 1
        }
    }

    func clear() {
        update(.zero)
    }

    func current(after revision: UInt64) -> SignalTextureSnapshot? {
        lock.withLock {
            guard self.revision != revision else {
                return nil
            }
            return SignalTextureSnapshot(frame: frame, revision: self.revision)
        }
    }
}
