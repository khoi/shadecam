import SwiftUI

struct ContentView: View {
    @State private var camera = CameraCaptureService()
    @State private var shader = ShaderEditorModel()
    @State private var renderControl = RenderControl()
    @State private var renderMetrics = RenderMetrics()
    @State private var segmentationQuality = SegmentationQuality.balanced

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
                CameraPreviewView(
                    frameStore: camera.frameStore,
                    maskStore: camera.maskStore,
                    faceRectStore: camera.faceRectStore,
                    pipelineStore: shader.pipelineStore,
                    renderControl: renderControl,
                    renderMetrics: renderMetrics
                )
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
            await camera.start()
        }
        .onDisappear {
            camera.stop()
        }
        .onChange(of: segmentationQuality) { _, quality in
            camera.setSegmentationQuality(quality)
        }
        .toolbar {
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
