import SwiftUI

@main
struct CodexkitApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycleObserver.self) private var lifecycleObserver

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
