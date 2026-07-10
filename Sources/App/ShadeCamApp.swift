import SwiftUI

@main
struct ShadeCamApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1200, height: 760)
        .windowResizability(.contentMinSize)
    }
}
