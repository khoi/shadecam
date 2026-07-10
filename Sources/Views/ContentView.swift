import SwiftUI

struct ContentView: View {
    @State private var signalBus: SignalBus
    @State private var camera: CameraCaptureService
    @State private var shader = ShaderEditorModel()
    @State private var renderControl = RenderControl()
    @State private var renderMetrics = RenderMetrics()
    @State private var segmentationQuality = SegmentationQuality.balanced
    @State private var showsSignalHUD = false

    init() {
        let signalBus = SignalBus.standard
        _signalBus = State(initialValue: signalBus)
        _camera = State(initialValue: CameraCaptureService(signalBus: signalBus))
    }

    var body: some View {
        VStack(spacing: 0) {
            if let banner = shader.banner {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(banner)
                        .lineLimit(2)
                    Spacer()
                    Button {
                        shader.dismissBanner()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.red)
            }

            HSplitView {
                ZStack(alignment: .topLeading) {
                    CameraPreviewView(
                        frameStore: camera.frameStore,
                        maskStore: camera.maskStore,
                        signalBus: signalBus,
                        pipelineStore: shader.pipelineStore,
                        renderControl: renderControl,
                        renderMetrics: renderMetrics
                    )

                    if showsSignalHUD {
                        SignalHUDView(
                            signalBus: signalBus,
                            renderMetrics: renderMetrics,
                            dismiss: { showsSignalHUD = false }
                        )
                        .padding(12)
                    }
                }
                .aspectRatio(camera.frameDimensions.aspectRatio, contentMode: .fit)
                .frame(minWidth: 520, minHeight: 500)
                .background(.black)

                ShaderEditorView(
                    model: shader,
                    segmentationQuality: $segmentationQuality,
                    renderMetrics: renderMetrics
                )
                    .frame(minWidth: 360, idealWidth: 460, maxWidth: 620)
            }
        }
        .task {
            camera.setNeeds(shader.needs)
            await camera.start()
        }
        .onDisappear {
            camera.stop()
        }
        .onChange(of: segmentationQuality) { _, quality in
            camera.setSegmentationQuality(quality)
        }
        .onChange(of: shader.needs) { _, needs in
            camera.setNeeds(needs)
        }
        .toolbar {
            ToolbarItem {
                Button {
                    showsSignalHUD.toggle()
                } label: {
                    Label("Signal HUD", systemImage: "waveform.path.ecg")
                }
                .help(showsSignalHUD ? "Hide Signal HUD" : "Show Signal HUD")
            }
            ToolbarItem {
                Button {
                    renderControl.requestPlateCapture()
                } label: {
                    Label("Capture Background", systemImage: "camera.aperture")
                }
            }
        }
    }
}
