import SwiftUI

struct ShaderEditorView: View {
    @Bindable var model: ShaderEditorModel
    @Binding var segmentationQuality: SegmentationQuality
    let renderMetrics: RenderMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Picker("Preset", selection: $model.selectedPreset) {
                    ForEach(model.presets) { preset in
                        Text(preset.name).tag(preset)
                    }
                }
                .labelsHidden()

                Button {
                    model.loadShader()
                } label: {
                    Image(systemName: "folder")
                }
                .help("Load Shader")
                .keyboardShortcut("o", modifiers: .command)

                Button {
                    model.saveShader()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .help("Save Shader")
                .keyboardShortcut("s", modifiers: .command)

                Spacer()

                if model.isCompiling {
                    ProgressView()
                        .controlSize(.small)
                } else if model.diagnostics.isEmpty {
                    Label("Compiled", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }
            .padding(10)

            Divider()

            HStack {
                Picker("Segmentation", selection: $segmentationQuality) {
                    ForEach(SegmentationQuality.allCases) { quality in
                        Text(quality.name).tag(quality)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)

                Spacer()

                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    Text("\(Int(renderMetrics.currentFramesPerSecond().rounded())) FPS")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            TextEditor(text: $model.source)
                .font(.system(.body, design: .monospaced))
                .textEditorStyle(.plain)
                .padding(8)

            if !model.diagnostics.isEmpty {
                Divider()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(model.diagnostics) { diagnostic in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Line \(diagnostic.line), column \(diagnostic.column)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.red)
                                Text(diagnostic.message)
                                    .font(.caption)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                }
                .frame(maxHeight: 160)
            }
        }
    }
}
