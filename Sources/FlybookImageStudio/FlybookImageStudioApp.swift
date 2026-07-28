import SwiftUI

@main
struct FlybookImageStudioApp: App {
    @StateObject private var model = StudioModel()

    var body: some Scene {
        WindowGroup("Flybook Image Studio") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1080, minHeight: 700)
                .task { model.reload() }
        }
        .windowStyle(.titleBar)
    }
}
