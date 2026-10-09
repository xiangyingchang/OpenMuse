import OpenMuseCore
import SwiftUI

@main
struct OpenMuseIOSApp: App {
    @StateObject private var model = OpenMuseAppModel()

    var body: some Scene {
        WindowGroup {
            OpenMuseRootView(model: model)
                .preferredColorScheme(.dark)
        }
    }
}
