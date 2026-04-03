import SwiftUI

@main
struct HelmApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView(appModel: self.appModel)
        }
    }
}
