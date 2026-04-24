import AppKit
import Foundation

struct MenuBarStatusItemPresentation: Equatable {
    enum Emphasis: Equatable {
        case primary
        case secondary
        case warning
        case critical

        var foregroundColor: NSColor {
            switch self {
            case .primary:
                return .labelColor
            case .secondary:
                return .secondaryLabelColor
            case .warning:
                return .systemOrange
            case .critical:
                return .systemRed
            }
        }

        var fontWeight: NSFont.Weight {
            switch self {
            case .primary, .secondary:
                return .medium
            case .warning, .critical:
                return .semibold
            }
        }
    }

    let iconName: String
    let title: String
    let emphasis: Emphasis

    var foregroundColor: NSColor { self.emphasis.foregroundColor }
    var font: NSFont { .systemFont(ofSize: 12, weight: self.emphasis.fontWeight) }

    static func make(
        accounts: [TokenAccount],
        activeProvider: CodexBarProvider?,
        usageDisplayMode: CodexBarUsageDisplayMode,
        menuBarDisplay: CodexBarOpenAISettings.MenuBarDisplaySettings,
        updateAvailable: Bool,
        apiServiceEnabled: Bool = false,
        apiServiceMemberAccountIDs: [String] = [],
        observedAuthFiles: [CLIProxyAPIObservedAuthFile] = [],
        now: Date = Date()
    ) -> MenuBarStatusItemPresentation {
        let iconName = MenuBarIconResolver.iconName(
            accounts: accounts,
            activeProviderKind: activeProvider?.kind,
            updateAvailable: updateAvailable
        )

        if apiServiceEnabled {
            return self.makeAPIServicePresentation(
                iconName: iconName,
                accounts: accounts,
                memberAccountIDs: apiServiceMemberAccountIDs,
                observedAuthFiles: observedAuthFiles,
                visibility: menuBarDisplay.apiServiceStatusVisibility,
                now: now
            )
        }

        if let active = accounts.first(where: { $0.isActive }) {
            return MenuBarStatusItemPresentation(
                iconName: iconName,
                title: self.quotaTitle(
                    for: active,
                    mode: usageDisplayMode,
                    visibility: menuBarDisplay.quotaVisibility
                ),
                emphasis: self.emphasis(for: active)
            )
        }

        return MenuBarStatusItemPresentation(iconName: iconName, title: "", emphasis: .primary)
    }

    private static func quotaTitle(
        for account: TokenAccount,
        mode: CodexBarUsageDisplayMode,
        visibility: CodexBarMenuBarQuotaVisibility
    ) -> String {
        let windows = self.filteredWindows(
            from: account.usageWindowDisplays(mode: mode),
            visibility: visibility
        )
        return windows.map { "\(Int($0.displayPercent))%" }.joined(separator: "·")
    }

    private static func filteredWindows(
        from windows: [UsageWindowDisplay],
        visibility: CodexBarMenuBarQuotaVisibility
    ) -> [UsageWindowDisplay] {
        switch visibility {
        case .both:
            return windows
        case .primaryOnly:
            return windows.first.map { [$0] } ?? []
        case .secondaryOnly:
            guard windows.count > 1 else { return [] }
            return [windows[1]]
        case .hidden:
            return []
        }
    }

    private static func emphasis(for account: TokenAccount) -> Emphasis {
        if account.secondaryExhausted {
            return .critical
        }
        if account.primaryExhausted || account.isBelowVisualWarningThreshold() {
            return .warning
        }
        return .primary
    }

    private static func makeAPIServicePresentation(
        iconName: String,
        accounts: [TokenAccount],
        memberAccountIDs: [String],
        observedAuthFiles: [CLIProxyAPIObservedAuthFile],
        visibility: CodexBarMenuBarAPIServiceStatusVisibility,
        now: Date
    ) -> MenuBarStatusItemPresentation {
        guard visibility == .availableOverTotal else {
            return MenuBarStatusItemPresentation(iconName: iconName, title: "", emphasis: .primary)
        }

        let memberIDSet = Set(memberAccountIDs)
        let selectedAccounts = accounts.filter { memberIDSet.contains($0.accountId) }
        let observedByAccountID: [String: CLIProxyAPIObservedAuthFile] = Dictionary(
            observedAuthFiles.compactMap { file in
                guard let localAccountID = file.localAccountID else { return nil }
                return (localAccountID, file)
            },
            uniquingKeysWith: { first, _ in first }
        )
        let availableCount = selectedAccounts.reduce(into: 0) { partial, account in
            if let observed = observedByAccountID[account.accountId] {
                if self.isObservedAuthAvailable(observed, now: now) {
                    partial += 1
                }
            } else if account.isAvailableForNextUseRouting {
                partial += 1
            }
        }

        return MenuBarStatusItemPresentation(
            iconName: iconName,
            title: L.available(availableCount, selectedAccounts.count),
            emphasis: .primary
        )
    }

    private static func isObservedAuthAvailable(_ authFile: CLIProxyAPIObservedAuthFile, now: Date) -> Bool {
        if authFile.disabled {
            return false
        }
        if authFile.status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "disabled" {
            return false
        }
        if authFile.unavailable,
           let nextRetryAfter = authFile.nextRetryAfter,
           nextRetryAfter > now {
            return false
        }
        return true
    }
}
