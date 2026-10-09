import OpenMuseCore
import SwiftUI

@main
struct OpenMuseMacApp: App {
    @StateObject private var model = OpenMuseAppModel()

    var body: some Scene {
        WindowGroup {
            OpenMuseRootView(model: model)
                .frame(minWidth: 880, minHeight: 620)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.titleBar)
    }
}
