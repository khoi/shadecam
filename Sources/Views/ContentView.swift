import SwiftUI

struct ContentView: View {
    @State private var camera = CameraCaptureService()

    var body: some View {
        CameraPreviewView(frameStore: camera.frameStore)
            .frame(minWidth: 800, minHeight: 500)
            .task {
                await camera.start()
            }
            .onDisappear {
                camera.stop()
            }
    }
}
