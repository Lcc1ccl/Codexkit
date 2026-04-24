import CoreGraphics
import SwiftUI

@MainActor
final class SettingsWindowLauncher {
    static let shared = SettingsWindowLauncher()

    private init() {}

    func show(initialPage: SettingsPage = .accounts) {
        DetachedWindowPresenter.shared.show(
            id: "openai-settings",
            title: L.settingsWindowTitle,
            size: CGSize(width: 1080, height: 760),
            resizable: true,
            preserveExistingSize: true
        ) {
            SettingsWindowView(
                store: TokenStore.shared,
                codexAppPathPanelService: CodexAppPathPanelService.shared,
                initialPage: initialPage
            ) {
                DetachedWindowPresenter.shared.close(id: "openai-settings")
            }
        }
    }
}
