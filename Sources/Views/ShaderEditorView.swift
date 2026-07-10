import SwiftUI

struct ShaderEditorView: View {
    @Bindable var model: ShaderEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Picker("Preset", selection: $model.selectedPreset) {
                    ForEach(model.presets) { preset in
                        Text(preset.name).tag(preset)
                    }
                }
                .labelsHidden()

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
