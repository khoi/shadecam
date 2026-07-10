import SwiftUI

struct SignalHUDView: View {
    let signalBus: SignalBus
    let renderMetrics: RenderMetrics
    let dismiss: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            let snapshot = signalBus.snapshot(at: ProcessInfo.processInfo.systemUptime)
            VStack(alignment: .leading, spacing: 8) {
                header
                vectorRow(name: "face", value: snapshot.faceRect)
                vectorRow(name: "expression", value: snapshot.expression)
                audioRows(snapshot.audio)
                handsRow(snapshot.hands)

                VStack(spacing: 4) {
                    ForEach(Array(SignalNames.events.enumerated()), id: \.offset) { slot, name in
                        eventRow(name: name, value: snapshot.events[slot])
                    }
                }

                ForEach(additionalSignalNames(in: snapshot), id: \.self) { name in
                    vectorRow(name: name, value: snapshot.values[name]!)
                }
            }
            .font(.caption.monospaced())
            .padding(10)
            .frame(width: 300)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            .shadow(radius: 8, y: 3)
        }
    }

    private var header: some View {
        HStack {
            Text("SIGNALS")
                .fontWeight(.semibold)
            Spacer()
            Text("\(Int(renderMetrics.currentFramesPerSecond().rounded())) FPS")
                .foregroundStyle(.secondary)
            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help("Hide Signal HUD")
        }
    }

    private func vectorRow(name: String, value: SIMD4<Float>) -> some View {
        HStack(spacing: 6) {
            Text(name)
                .frame(width: 72, alignment: .leading)
                .foregroundStyle(.secondary)
            Text(String(format: "%.2f  %.2f  %.2f  %.2f", value.x, value.y, value.z, value.w))
                .lineLimit(1)
        }
    }

    private func eventRow(name: String, value: SIMD4<Float>) -> some View {
        HStack(spacing: 6) {
            Text(name.replacingOccurrences(of: "event.", with: ""))
                .frame(width: 72, alignment: .leading)
                .foregroundStyle(.secondary)
            meter(value.x)
            Text(value.y < 0 ? "never" : String(format: "%.1fs", value.y))
                .frame(width: 42, alignment: .trailing)
                .foregroundStyle(.secondary)
        }
    }

    private func audioRows(_ audio: SIMD4<Float>) -> some View {
        VStack(spacing: 4) {
            levelRow(name: "rms", value: audio.x)
            levelRow(name: "bass", value: audio.y)
            levelRow(name: "mid", value: audio.z)
            levelRow(name: "treble", value: audio.w)
        }
    }

    private func levelRow(name: String, value: Float) -> some View {
        HStack(spacing: 6) {
            Text(name)
                .frame(width: 72, alignment: .leading)
                .foregroundStyle(.secondary)
            meter(value)
            Text(String(format: "%.2f", value))
                .frame(width: 32, alignment: .trailing)
        }
    }

    private func meter(_ value: Float) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.secondary.opacity(0.2))
                Rectangle()
                    .fill(.cyan)
                    .frame(width: geometry.size.width * CGFloat(min(max(value, 0), 1)))
            }
        }
        .frame(height: 6)
    }

    private func handsRow(_ hands: ShaderHandUniforms) -> some View {
        let left = confidence(meanConfidence(of: 0, in: hands))
        let right = confidence(meanConfidence(of: 1, in: hands))
        return HStack(spacing: 6) {
            Text("hands")
                .frame(width: 72, alignment: .leading)
                .foregroundStyle(.secondary)
            Text("L \(left)  R \(right)")
                .lineLimit(1)
        }
    }

    private func meanConfidence(of hand: Int, in hands: ShaderHandUniforms) -> Float {
        (0..<21).reduce(0) { $0 + hands[hand, $1].z } / 21
    }

    private func confidence(_ value: Float) -> String {
        value > 0.01 ? String(format: "%.2f", value) : "—"
    }

    private func additionalSignalNames(in snapshot: SignalSnapshot) -> [String] {
        let standardNames = Set(
            [SignalNames.faceRect, SignalNames.expression, SignalNames.audio] + SignalNames.events
        )
        return snapshot.values.keys.filter {
            !standardNames.contains($0) && !$0.hasPrefix("hand.")
        }.sorted()
    }
}
