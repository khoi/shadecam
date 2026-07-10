import Foundation
import Observation

@MainActor
@Observable
final class ShaderEditorModel {
    let presets: [ShaderPreset]

    var source: String {
        didSet {
            guard source != oldValue else {
                return
            }
            scheduleCompilation()
        }
    }
    var selectedPreset: ShaderPreset {
        didSet {
            guard selectedPreset != oldValue else {
                return
            }
            loadSelectedPreset()
        }
    }
    private(set) var diagnostics: [ShaderDiagnostic] = []
    private(set) var banner: String?
    private(set) var isCompiling = false

    let pipelineStore: ShaderPipelineStore

    private let bundle: Bundle
    private let compiler: ShaderCompiler
    private var compileTask: Task<Void, Never>?

    init(bundle: Bundle = .main) {
        do {
            let presets = ShaderPresetLibrary.load(in: bundle)
            guard let selectedPreset = presets.first(where: { $0.resourceName == "passthrough" }) else {
                throw ShaderPresetError.missingResource("passthrough")
            }
            let source = try selectedPreset.source(in: bundle)
            let composer = try ShaderSourceComposer(bundle: bundle)
            let compiler = try ShaderCompiler(initialSource: source, composer: composer)
            self.bundle = bundle
            self.presets = presets
            self.selectedPreset = selectedPreset
            self.source = source
            self.compiler = compiler
            pipelineStore = compiler.pipelineStore
        } catch {
            fatalError(error.localizedDescription)
        }

        pipelineStore.setFaultHandler { [weak self] message in
            Task { @MainActor [weak self] in
                self?.banner = message
            }
        }
    }

    func dismissBanner() {
        banner = nil
    }

    private func loadSelectedPreset() {
        do {
            source = try selectedPreset.source(in: bundle)
        } catch {
            banner = error.localizedDescription
        }
    }

    private func scheduleCompilation() {
        compileTask?.cancel()
        let candidate = source
        compileTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, let self else {
                return
            }
            await compile(candidate)
        }
    }

    private func compile(_ candidate: String) async {
        isCompiling = true
        defer {
            if candidate == source {
                isCompiling = false
            }
        }

        do {
            let pipeline = try await compiler.compile(candidate)
            guard candidate == source, !Task.isCancelled else {
                return
            }
            pipelineStore.install(pipeline)
            diagnostics = []
            banner = nil
        } catch {
            guard candidate == source, !Task.isCancelled else {
                return
            }
            diagnostics = ShaderDiagnosticParser.parse(error.localizedDescription)
            if diagnostics.isEmpty {
                banner = error.localizedDescription
            }
        }
    }
}
