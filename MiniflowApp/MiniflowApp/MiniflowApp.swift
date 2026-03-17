import SwiftUI

@main
struct MiniflowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No main window — purely menu bar driven.
        // Settings window is opened by AppDelegate on demand.
        Settings {
            EmptyView()
        }
    }
}
