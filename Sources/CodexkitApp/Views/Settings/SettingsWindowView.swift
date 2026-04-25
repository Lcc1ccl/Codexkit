import AppKit
import Combine
import SwiftUI

private struct SettingsPageSection: Identifiable {
    let id: String
    let title: String?
    let pages: [SettingsPage]
}

struct SettingsWindowView: View {
    @ObservedObject private var store: TokenStore
    @ObservedObject private var updateCoordinator: UpdateCoordinator
    private let codexAppPathPanelService: CodexAppPathPanelService
    private let onClose: () -> Void

    @StateObject private var coordinator: SettingsWindowCoordinator

    @MainActor
    init(
        store: TokenStore,
        updateCoordinator: UpdateCoordinator? = nil,
        codexAppPathPanelService: CodexAppPathPanelService,
        initialPage: SettingsPage = .accounts,
        onClose: @escaping () -> Void
    ) {
        self._store = ObservedObject(wrappedValue: store)
        self._updateCoordinator = ObservedObject(wrappedValue: updateCoordinator ?? .shared)
        self.codexAppPathPanelService = codexAppPathPanelService
        self.onClose = onClose
        self._coordinator = StateObject(
            wrappedValue: SettingsWindowCoordinator(
                config: store.config,
                accounts: store.accounts,
                selectedPage: initialPage
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                self.sidebar
                Divider()
                self.detail
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                if let validationMessage = self.coordinator.validationMessage {
                    Text(validationMessage)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack {
                    Spacer()

                    Button(L.cancel) {
                        self.handleCloseRequest()
                    }
                    .keyboardShortcut(.cancelAction)

                    Button(L.save) {
                        self.saveCurrentPage()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(self.coordinator.hasCurrentPageChanges == false)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(self.store.$config.dropFirst()) { config in
            self.coordinator.reconcileExternalState(
                config: config,
                accounts: self.store.accounts
            )
        }
        .onReceive(self.store.$accounts.dropFirst()) { accounts in
            self.coordinator.reconcileExternalState(
                config: self.store.config,
                accounts: accounts
            )
        }
        .background(
            SettingsWindowBridge {
                $0.shouldCloseHandler = { self.coordinator.requestClose() }
            }
        )
        .confirmationDialog(
            L.settingsUnsavedChangesTitle,
            isPresented: Binding(
                get: { self.coordinator.pendingAction != nil },
                set: { if $0 == false { self.coordinator.cancelPendingAction() } }
            ),
            titleVisibility: .visible
        ) {
            Button(L.save) {
                self.coordinator.confirmPendingActionSave(
                    using: self.store,
                    onClose: self.onClose
                )
            }
            Button(L.settingsDiscardChangesAction, role: .destructive) {
                self.coordinator.confirmPendingActionDiscard(onClose: self.onClose)
            }
            Button(L.cancel, role: .cancel) {
                self.coordinator.cancelPendingAction()
            }
        } message: {
            Text(L.settingsUnsavedChangesMessage(self.coordinator.selectedPage.title))
        }
    }

    private func binding<Value>(
        _ keyPath: WritableKeyPath<SettingsWindowDraft, Value>,
        field: SettingsDirtyField
    ) -> Binding<Value> {
        Binding(
            get: { self.coordinator.draft[keyPath: keyPath] },
            set: { self.coordinator.update(keyPath, to: $0, field: field) }
        )
    }

    private var settingsPageSections: [SettingsPageSection] {
        [
            SettingsPageSection(
                id: "core",
                title: nil,
                pages: [.general, .accounts, .usage, .provider, .updates]
            ),
            SettingsPageSection(
                id: "api-service",
                title: L.settingsAPIServiceGroupTitle,
                pages: [.apiService, .apiServiceDashboard, .apiServiceLogs]
            )
        ]
    }

    private func sidebarRow(for page: SettingsPage) -> some View {
        Button {
            self.coordinator.requestPageSelection(page)
        } label: {
            HStack(spacing: 10) {
                Label {
                    Text(page.title)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: page.iconName)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowBackground(
            RoundedRectangle(cornerRadius: 8)
                .fill(self.coordinator.selectedPage == page ? Color.accentColor.opacity(0.12) : Color.clear)
        )
    }

    private var sidebar: some View {
        List {
            ForEach(self.settingsPageSections) { section in
                if let title = section.title {
                    Section {
                        ForEach(section.pages) { page in
                            self.sidebarRow(for: page)
                        }
                    } header: {
                        Text(title)
                    }
                } else {
                    ForEach(section.pages) { page in
                        self.sidebarRow(for: page)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 240, idealWidth: 240, maxWidth: 240)
    }

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                switch self.coordinator.selectedPage {
                case .accounts:
                    SettingsAccountsPage(
                        coordinator: self.coordinator,
                        store: self.store,
                        codexAppPathPanelService: self.codexAppPathPanelService
                    )
                case .general:
                    SettingsGeneralPage(coordinator: self.coordinator)
                case .usage:
                    SettingsUsagePage(coordinator: self.coordinator)
                case .provider:
                    SettingsProviderPage(store: self.store)
                case .apiService:
                    SettingsAPIServicePage(coordinator: self.coordinator, store: self.store)
                case .apiServiceDashboard:
                    SettingsAPIServiceDashboardPage(store: self.store)
                case .apiServiceLogs:
                    SettingsAPIServiceLogsPage(store: self.store)
                case .updates:
                    SettingsUpdatesPage(coordinator: self.coordinator, updateCoordinator: self.updateCoordinator)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func saveCurrentPage() {
        do {
            _ = try self.coordinator.save(page: self.coordinator.selectedPage, using: self.store)
        } catch {
            self.coordinator.validationMessage = error.localizedDescription
        }
    }

    private func handleCloseRequest() {
        if self.coordinator.requestClose() {
            self.onClose()
        }
    }
}

private struct SettingsWindowBridge: NSViewRepresentable {
    let configure: (DetachedWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window as? DetachedWindow else { return }
            self.configure(window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window as? DetachedWindow else { return }
            self.configure(window)
        }
    }
}

private struct SettingsAccountsPage: View {
    @ObservedObject var coordinator: SettingsWindowCoordinator
    @ObservedObject var store: TokenStore
    let codexAppPathPanelService: CodexAppPathPanelService

    private let oauthAccountService = CodexBarOAuthAccountService()
    private let openAIAccountCSVService = OpenAIAccountCSVService()
    private let openAIAccountCSVPanelService = OpenAIAccountCSVPanelService()

    @State private var accountCSVMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(SettingsPage.accounts.title)
                .font(.system(size: 16, weight: .semibold))

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button(L.importOpenAICSVAction) {
                        self.importOpenAIAccountsCSV()
                    }
                    Button(L.exportOpenAICSVAction) {
                        self.exportOpenAIAccountsCSV()
                    }
                }

                if let accountCSVMessage {
                    Text(accountCSVMessage)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            SettingsAccountOrderingModeSection(
                mode: Binding(
                    get: { self.coordinator.draft.accountOrderingMode },
                    set: { self.coordinator.update(\.accountOrderingMode, to: $0, field: .accountOrderingMode) }
                )
            )

            if self.coordinator.showsManualActivationBehaviorSection {
                SettingsManualActivationBehaviorSection(
                    behavior: Binding(
                        get: { self.coordinator.draft.manualActivationBehavior },
                        set: { self.coordinator.update(\.manualActivationBehavior, to: $0, field: .manualActivationBehavior) }
                    ),
                    preferredCodexAppPath: Binding(
                        get: { self.coordinator.draft.preferredCodexAppPath },
                        set: { self.coordinator.update(\.preferredCodexAppPath, to: $0, field: .preferredCodexAppPath) }
                    ),
                    validationMessage: self.$coordinator.validationMessage,
                    codexAppPathPanelService: self.codexAppPathPanelService,
                    showsCodexAppPathSection: self.coordinator.showsCodexAppPathSection
                )
            }

            SettingsAccountActivationScopeSection(
                scopeMode: Binding(
                    get: { self.coordinator.draft.accountActivationScopeMode },
                    set: { self.coordinator.update(\.accountActivationScopeMode, to: $0, field: .accountActivationScopeMode) }
                ),
                rootPaths: Binding(
                    get: { self.coordinator.draft.accountActivationRootPaths },
                    set: { self.coordinator.update(\.accountActivationRootPaths, to: $0, field: .accountActivationRootPaths) }
                ),
                validationMessage: self.$coordinator.validationMessage,
                showsPathsSection: self.coordinator.showsAccountActivationPathsSection
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(L.accountServiceTierTitle)
                    .font(.system(size: 12, weight: .medium))
                Text(L.accountServiceTierHint)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Picker(
                    L.accountServiceTierTitle,
                    selection: Binding(
                        get: { self.coordinator.draft.serviceTier },
                        set: { self.coordinator.update(\.serviceTier, to: $0, field: .serviceTier) }
                    )
                ) {
                    Text(L.accountServiceTierStandard).tag(CodexBarServiceTier.standard)
                    Text(L.accountServiceTierFast).tag(CodexBarServiceTier.fast)
                }
                .pickerStyle(.segmented)
            }

            if self.coordinator.showsManualAccountOrderSection {
                SettingsAccountOrderSection(coordinator: self.coordinator)
            }
        }
    }

    private func exportOpenAIAccountsCSV() {
        do {
            let accounts = try self.oauthAccountService.exportAccounts()
            guard accounts.isEmpty == false else {
                self.coordinator.validationMessage = L.noOpenAIAccountsToExport
                self.accountCSVMessage = nil
                return
            }
            guard let exportURL = self.openAIAccountCSVPanelService.requestExportURL() else {
                return
            }

            let csv = self.openAIAccountCSVService.makeCSV(from: accounts)
            try csv.write(to: exportURL, atomically: true, encoding: String.Encoding.utf8)
            self.coordinator.validationMessage = nil
            self.accountCSVMessage = exportURL.lastPathComponent
        } catch {
            self.coordinator.validationMessage = error.localizedDescription
            self.accountCSVMessage = nil
        }
    }

    private func importOpenAIAccountsCSV() {
        do {
            guard let importURL = self.openAIAccountCSVPanelService.requestImportURL() else {
                return
            }

            let csvText = try String(contentsOf: importURL, encoding: .utf8)
            let parsed = try self.openAIAccountCSVService.parseCSV(csvText)
            _ = try self.oauthAccountService.importAccounts(
                parsed.accounts,
                activeAccountID: parsed.activeAccountID
            )
            self.store.load()
            self.coordinator.reconcileExternalState(config: self.store.config, accounts: self.store.accounts)
            self.coordinator.validationMessage = nil
            self.accountCSVMessage = importURL.lastPathComponent
        } catch {
            self.coordinator.validationMessage = error.localizedDescription
            self.accountCSVMessage = nil
        }
    }
}

private struct SettingsGeneralPage: View {
    @ObservedObject var coordinator: SettingsWindowCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(SettingsPage.general.title)
                .font(.system(size: 16, weight: .semibold))

            Text(L.settingsGeneralMenuBarDisplayHint)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            SettingsMenuBarQuotaVisibilitySection(
                visibility: Binding(
                    get: { self.coordinator.draft.menuBarQuotaVisibility },
                    set: { self.coordinator.update(\.menuBarQuotaVisibility, to: $0, field: .menuBarQuotaVisibility) }
                )
            )

            SettingsMenuBarAPIServiceStatusSection(
                visibility: Binding(
                    get: { self.coordinator.draft.menuBarAPIServiceStatusVisibility },
                    set: { self.coordinator.update(\.menuBarAPIServiceStatusVisibility, to: $0, field: .menuBarAPIServiceStatusVisibility) }
                )
            )
        }
    }
}

private struct SettingsUsagePage: View {
    @ObservedObject var coordinator: SettingsWindowCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(SettingsPage.usage.title)
                .font(.system(size: 16, weight: .semibold))

            SettingsUsageDisplayModeSection(
                usageDisplayMode: Binding(
                    get: { self.coordinator.draft.usageDisplayMode },
                    set: { self.coordinator.update(\.usageDisplayMode, to: $0, field: .usageDisplayMode) }
                )
            )

            SettingsQuotaSortSection(
                plusRelativeWeight: Binding(
                    get: { self.coordinator.draft.plusRelativeWeight },
                    set: { self.coordinator.update(\.plusRelativeWeight, to: $0, field: .plusRelativeWeight) }
                ),
                proRelativeToPlusMultiplier: Binding(
                    get: { self.coordinator.draft.proRelativeToPlusMultiplier },
                    set: { self.coordinator.update(\.proRelativeToPlusMultiplier, to: $0, field: .proRelativeToPlusMultiplier) }
                ),
                teamRelativeToPlusMultiplier: Binding(
                    get: { self.coordinator.draft.teamRelativeToPlusMultiplier },
                    set: { self.coordinator.update(\.teamRelativeToPlusMultiplier, to: $0, field: .teamRelativeToPlusMultiplier) }
                )
            )
        }
    }
}

private struct SettingsProviderPage: View {
    @ObservedObject var store: TokenStore
    @State private var errorMessage: String?

    private let codexDesktopLaunchProbeService = CodexDesktopLaunchProbeService.shared

    private var openRouterProvider: CodexBarProvider? {
        guard let provider = self.store.openRouterProvider, provider.accounts.isEmpty == false else {
            return nil
        }
        return provider
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(SettingsPage.provider.title)
                    .font(.system(size: 16, weight: .semibold))

                Spacer()

                Button(L.settingsProviderAddCompatibleProvider) {
                    self.openAddProviderWindow(defaultPreset: .custom)
                }

                Button(L.settingsProviderAddOpenRouter) {
                    self.openAddProviderWindow(defaultPreset: .openRouter)
                }
            }

            Text(L.settingsProviderPageHint)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage, errorMessage.isEmpty == false {
                Text(errorMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.red)
            }

            if self.store.customProviders.isEmpty && self.openRouterProvider == nil {
                Text(L.settingsProviderEmptyState)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                if self.store.customProviders.isEmpty == false {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L.settingsProviderCompatibleProvidersTitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)

                        ForEach(self.store.customProviders) { provider in
                            CompatibleProviderRowView(
                                provider: provider,
                                isActiveProvider: self.store.activeProvider?.id == provider.id,
                                activeAccountId: provider.activeAccountId
                            ) { account in
                                Task { await self.activateCompatibleProvider(providerID: provider.id, accountID: account.id) }
                            } onConfigure: {
                                self.openEditCompatibleProviderWindow(provider: provider)
                            } onDeleteAccount: { account in
                                self.deleteCompatibleAccount(providerID: provider.id, accountID: account.id)
                            } onDeleteProvider: {
                                self.deleteProvider(providerID: provider.id)
                            }
                        }
                    }
                }

                if let provider = self.openRouterProvider {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L.settingsProviderOpenRouterTitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)

                        OpenRouterProviderRowView(
                            provider: provider,
                            isActiveProvider: self.store.activeProvider?.id == provider.id,
                            activeAccountId: provider.activeAccountId
                        ) { account in
                            Task { await self.activateOpenRouterProvider(accountID: account.id) }
                        } onSelectModel: { modelID in
                            Task { await self.selectOpenRouterModel(modelID) }
                        } onAddAccount: {
                            self.openAddOpenRouterAccountWindow(provider: provider)
                        } onEditModel: {
                            self.openEditOpenRouterWindow(provider: provider)
                        } onDeleteAccount: { account in
                            self.deleteOpenRouterAccount(accountID: account.id)
                        }
                    }
                }
            }
        }
    }

    private func openAddProviderWindow(defaultPreset: AddProviderPreset) {
        DetachedWindowPresenter.shared.show(
            id: "settings-add-provider",
            title: L.settingsProviderWindowTitle,
            size: CGSize(width: 520, height: 620)
        ) {
            AddProviderSheet(store: self.store, defaultPreset: defaultPreset) { preset, label, baseURL, accountLabel, apiKey, openRouterSelection in
                do {
                    switch preset {
                    case .custom:
                        try self.store.addCustomProvider(label: label, baseURL: baseURL, accountLabel: accountLabel, apiKey: apiKey)
                    case .openRouter:
                        guard let openRouterSelection else { return }
                        try self.store.addOpenRouterProvider(
                            apiKey: openRouterSelection.apiKey,
                            selectedModelID: openRouterSelection.selectedModelID,
                            pinnedModelIDs: openRouterSelection.pinnedModelIDs,
                            cachedModelCatalog: openRouterSelection.cachedModelCatalog,
                            fetchedAt: openRouterSelection.fetchedAt
                        )
                    }
                    self.errorMessage = nil
                    DetachedWindowPresenter.shared.close(id: "settings-add-provider")
                } catch {
                    self.errorMessage = error.localizedDescription
                }
            } onCancel: {
                DetachedWindowPresenter.shared.close(id: "settings-add-provider")
            }
        }
    }

    private func openEditCompatibleProviderWindow(provider: CodexBarProvider) {
        let windowID = "settings-edit-provider-\(provider.id)"
        DetachedWindowPresenter.shared.show(
            id: windowID,
            title: L.settingsProviderEditProviderTitle,
            size: CGSize(width: 560, height: 520)
        ) {
            EditCompatibleProviderSheet(provider: provider) { label, baseURL, accounts, activeAccountID in
                do {
                    try self.store.updateCustomProvider(
                        providerID: provider.id,
                        label: label,
                        baseURL: baseURL,
                        accounts: accounts,
                        activeAccountID: activeAccountID
                    )
                    self.errorMessage = nil
                    DetachedWindowPresenter.shared.close(id: windowID)
                } catch {
                    self.errorMessage = error.localizedDescription
                }
            } onCancel: {
                DetachedWindowPresenter.shared.close(id: windowID)
            }
        }
    }

    private func openAddOpenRouterAccountWindow(provider: CodexBarProvider) {
        let windowID = "settings-add-openrouter-account-\(provider.id)"
        DetachedWindowPresenter.shared.show(
            id: windowID,
            title: L.settingsProviderAddOpenRouterAccountTitle,
            size: CGSize(width: 520, height: 620)
        ) {
            AddOpenRouterAccountSheet(provider: provider, store: self.store) { selection in
                do {
                    try self.store.addOpenRouterProviderAccount(
                        apiKey: selection.apiKey,
                        selectedModelID: selection.selectedModelID,
                        pinnedModelIDs: selection.pinnedModelIDs,
                        cachedModelCatalog: selection.cachedModelCatalog,
                        fetchedAt: selection.fetchedAt
                    )
                    self.errorMessage = nil
                    DetachedWindowPresenter.shared.close(id: windowID)
                } catch {
                    self.errorMessage = error.localizedDescription
                }
            } onCancel: {
                DetachedWindowPresenter.shared.close(id: windowID)
            }
        }
    }

    private func openEditOpenRouterWindow(provider: CodexBarProvider) {
        let windowID = "settings-edit-openrouter-model"
        DetachedWindowPresenter.shared.show(
            id: windowID,
            title: L.settingsProviderEditOpenRouterTitle,
            size: CGSize(width: 520, height: 620)
        ) {
            EditOpenRouterModelSheet(provider: provider, store: self.store) { error in
                self.errorMessage = error
            } onClose: {
                DetachedWindowPresenter.shared.close(id: windowID)
            }
        }
    }

    private func activateCompatibleProvider(providerID: String, accountID: String) async {
        let previousActiveProviderID = self.store.config.active.providerId
        let previousActiveAccountID = self.store.config.active.accountId

        do {
            try await CompatibleProviderUseExecutor.execute(
                configuredBehavior: self.store.config.openAI.manualActivationBehavior,
                activateOnly: {
                    try self.store.activateCustomProvider(providerID: providerID, accountID: accountID)
                },
                restorePreviousSelection: {
                    try self.store.restoreActiveSelection(
                        activeProviderID: previousActiveProviderID,
                        activeAccountID: previousActiveAccountID
                    )
                },
                launchNewInstance: {
                    _ = try await self.codexDesktopLaunchProbeService.launchNewInstance()
                }
            )
            self.errorMessage = nil
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    private func activateOpenRouterProvider(accountID: String) async {
        let previousActiveProviderID = self.store.config.active.providerId
        let previousActiveAccountID = self.store.config.active.accountId

        do {
            try await CompatibleProviderUseExecutor.execute(
                configuredBehavior: self.store.config.openAI.manualActivationBehavior,
                activateOnly: {
                    try self.store.activateOpenRouterProvider(accountID: accountID)
                },
                restorePreviousSelection: {
                    try self.store.restoreActiveSelection(
                        activeProviderID: previousActiveProviderID,
                        activeAccountID: previousActiveAccountID
                    )
                },
                launchNewInstance: {
                    _ = try await self.codexDesktopLaunchProbeService.launchNewInstance()
                }
            )
            self.errorMessage = nil
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    private func selectOpenRouterModel(_ modelID: String) async {
        do {
            try self.store.updateOpenRouterSelectedModel(modelID)
            if let provider = self.store.openRouterProvider,
               self.store.activeProvider?.id != provider.id,
               let accountID = provider.activeAccountId {
                await self.activateOpenRouterProvider(accountID: accountID)
            }
            self.errorMessage = nil
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    private func deleteCompatibleAccount(providerID: String, accountID: String) {
        do {
            try self.store.removeCustomProviderAccount(providerID: providerID, accountID: accountID)
            self.errorMessage = nil
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    private func deleteProvider(providerID: String) {
        do {
            try self.store.removeCustomProvider(providerID: providerID)
            self.errorMessage = nil
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    private func deleteOpenRouterAccount(accountID: String) {
        do {
            try self.store.removeOpenRouterProviderAccount(accountID: accountID)
            self.errorMessage = nil
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}

private struct SettingsAPIServiceDashboardPage: View {
    @ObservedObject var store: TokenStore
    @State private var isRefreshingQuota = false

    private var state: CLIProxyAPIServiceState { self.store.cliProxyAPIState }
    private var usageGroups: [CLIProxyAPIUsageGroup] {
        CLIProxyAPIAccountGrouping.groupedUsageItems(self.state.accountUsageItems)
    }
    private var quotaGroups: [CLIProxyAPIQuotaGroup] {
        CLIProxyAPIAccountGrouping.groupedQuotaItems(self.state.quotaSnapshot?.accounts ?? [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(SettingsPage.apiServiceDashboard.title)
                    .font(.system(size: 16, weight: .semibold))

                Spacer()

                Button(self.isRefreshingQuota ? L.settingsAPIServiceRefreshingQuota : L.settingsAPIServiceRefreshQuota) {
                    self.isRefreshingQuota = true
                    Task { @MainActor in
                        await CLIProxyAPIRuntimeController.shared.refreshQuotaSnapshot(trigger: "settings-dashboard")
                        self.isRefreshingQuota = false
                    }
                }
                .disabled(self.isRefreshingQuota || self.state.status == .stopped)
            }

            Text(L.settingsAPIServiceDashboardPageHint)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 12) {
                SettingsDashboardMetricCard(
                    title: L.settingsAPIServiceDashboardRuntimeTitle,
                    value: self.state.status.rawValue.capitalized,
                    detail: self.state.lastError ?? L.settingsAPIServiceDashboardNoRuntimeIssue
                )

                SettingsDashboardMetricCard(
                    title: L.settingsAPIServiceDashboardRequestsTitle,
                    value: self.state.totalRequests.map(String.init) ?? "--",
                    detail: L.settingsAPIServiceDashboardFailedRequests(self.state.failedRequests ?? 0)
                )

                SettingsDashboardMetricCard(
                    title: L.settingsAPIServiceDashboardTokensTitle,
                    value: self.state.totalTokens.map(String.init) ?? "--",
                    detail: self.state.quotaSnapshot.map {
                        L.settingsAPIServiceDashboardQuotaWindow(
                            $0.minimumFiveHourRemainingPercent.map { "\($0)%" } ?? "--",
                            $0.minimumWeeklyRemainingPercent.map { "\($0)%" } ?? "--"
                        )
                    } ?? L.settingsAPIServiceDashboardNoQuotaWindow
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(L.settingsAPIServiceQuotaPanelTitle)
                    .font(.system(size: 16, weight: .semibold))

                if let snapshot = self.state.quotaSnapshot {
                    Text(L.settingsAPIServiceQuotaFreshness(self.quotaStatusText(snapshot), self.quotaUpdatedText(snapshot)))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    if self.quotaGroups.isEmpty {
                        Text(L.settingsAPIServiceNoQuotaData)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(self.quotaGroups) { group in
                            SettingsAPIServiceQuotaGroupView(group: group)
                        }
                    }
                } else {
                    Text(L.settingsAPIServiceDashboardEmptyState)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(L.settingsAPIServiceTrafficPanelTitle)
                    .font(.system(size: 16, weight: .semibold))

                if self.usageGroups.isEmpty {
                    Text(L.settingsAPIServiceNoUsageData)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(self.usageGroups) { group in
                        SettingsAPIServiceUsageGroupView(group: group)
                    }
                }
            }
        }
    }

    private func quotaUpdatedText(_ snapshot: CLIProxyAPIQuotaSnapshot) -> String {
        guard let date = snapshot.latestRefreshDate else { return "--" }
        return Self.quotaDateFormatter.string(from: date)
    }

    private func quotaStatusText(_ snapshot: CLIProxyAPIQuotaSnapshot) -> String {
        var status = snapshot.refreshStatus.rawValue
        if snapshot.stale {
            status += " · stale"
        }
        return status
    }

    private static let quotaDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct SettingsDashboardMetricCard: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(self.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            Text(self.value)
                .font(.system(size: 18, weight: .semibold))
            Text(self.detail)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
}

private struct SettingsAPIServiceLogsPage: View {
    @ObservedObject var store: TokenStore
    @State private var isLoading = false
    @State private var logsResponse: CLIProxyAPIManagementLogsResponse?
    @State private var errorMessage: String?

    private let managementService = CLIProxyAPIManagementService()
    private let limit = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(SettingsPage.apiServiceLogs.title)
                    .font(.system(size: 16, weight: .semibold))

                Spacer()

                Button(self.isLoading ? L.settingsAPIServiceLogsRefreshing : L.settingsAPIServiceLogsRefresh) {
                    Task { await self.loadLogs() }
                }
                .disabled(self.isLoading || self.store.cliProxyAPIState.status == .stopped)
            }

            Text(L.settingsAPIServiceLogsPageHint)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if self.store.cliProxyAPIState.status == .stopped && self.logsResponse == nil && self.errorMessage == nil {
                Text(L.settingsAPIServiceLogsStoppedHint)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            if let logsResponse {
                HStack(spacing: 12) {
                    Text(L.settingsAPIServiceLogsLineCount(logsResponse.lineCount))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text(L.settingsAPIServiceLogsLatestTimestamp(logsResponse.latestTimestamp))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                if logsResponse.lines.isEmpty {
                    Text(L.settingsAPIServiceLogsEmptyState)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(logsResponse.lines.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(size: 11, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .frame(minHeight: 280)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
                }
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
            } else if self.isLoading {
                ProgressView(L.settingsAPIServiceLogsLoading)
            }
        }
        .task {
            guard self.logsResponse == nil, self.errorMessage == nil else { return }
            await self.loadLogs()
        }
    }

    @MainActor
    private func loadLogs() async {
        let config = self.store.cliProxyAPIState.config
        guard config.managementSecretKey.isEmpty == false else {
            self.errorMessage = L.settingsAPIServiceLogsMissingSecret
            return
        }

        if self.store.cliProxyAPIState.status == .stopped {
            self.logsResponse = nil
            self.errorMessage = nil
            return
        }

        self.isLoading = true
        defer { self.isLoading = false }

        do {
            self.logsResponse = try await self.managementService.getLogs(
                config: config,
                afterTimestamp: nil,
                limit: self.limit
            )
            self.errorMessage = nil
        } catch {
            self.logsResponse = nil
            self.errorMessage = error.localizedDescription
        }
    }
}
private struct SettingsUpdatesPage: View {
    private enum ManualCheckTarget: String, Identifiable {
        case codexkit
        case cliProxyAPI

        var id: String { self.rawValue }
    }

    @ObservedObject var coordinator: SettingsWindowCoordinator
    @ObservedObject var updateCoordinator: UpdateCoordinator

    @State private var activeManualCheckTarget: ManualCheckTarget?

    private let cliProxyAPIInstalledVersionProvider = LocalCLIProxyAPIInstalledVersionProvider()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(SettingsPage.updates.title)
                .font(.system(size: 16, weight: .semibold))

            Text(L.settingsUpdatesPageHint)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            self.updateCard(
                title: L.settingsUpdatesCodexkitTitle,
                autoCheck: Binding(
                    get: { self.coordinator.draft.codexkitAutomaticallyChecksForUpdates },
                    set: { self.coordinator.update(\.codexkitAutomaticallyChecksForUpdates, to: $0, field: .codexkitAutomaticallyChecksForUpdates) }
                ),
                autoInstall: Binding(
                    get: { self.coordinator.draft.codexkitAutomaticallyInstallsUpdates },
                    set: { self.coordinator.update(\.codexkitAutomaticallyInstallsUpdates, to: $0, field: .codexkitAutomaticallyInstallsUpdates) }
                ),
                schedule: Binding(
                    get: { self.coordinator.draft.codexkitUpdateCheckSchedule },
                    set: { self.coordinator.update(\.codexkitUpdateCheckSchedule, to: $0, field: .codexkitUpdateCheckSchedule) }
                ),
                detailNote: L.settingsUpdatesCodexkitSourceNote,
                action: { self.presentManualCheck(.codexkit) }
            )

            self.updateCard(
                title: L.settingsUpdatesCLIProxyAPITitle,
                autoCheck: Binding(
                    get: { self.coordinator.draft.cliProxyAPIAutomaticallyChecksForUpdates },
                    set: { self.coordinator.update(\.cliProxyAPIAutomaticallyChecksForUpdates, to: $0, field: .cliProxyAPIAutomaticallyChecksForUpdates) }
                ),
                autoInstall: Binding(
                    get: { self.coordinator.draft.cliProxyAPIAutomaticallyInstallsUpdates },
                    set: { self.coordinator.update(\.cliProxyAPIAutomaticallyInstallsUpdates, to: $0, field: .cliProxyAPIAutomaticallyInstallsUpdates) }
                ),
                schedule: Binding(
                    get: { self.coordinator.draft.cliProxyAPIUpdateCheckSchedule },
                    set: { self.coordinator.update(\.cliProxyAPIUpdateCheckSchedule, to: $0, field: .cliProxyAPIUpdateCheckSchedule) }
                ),
                detailNote: L.settingsUpdatesCLIProxyAPISourceNote,
                action: { self.presentManualCheck(.cliProxyAPI) }
            )
        }
        .sheet(item: self.$activeManualCheckTarget) { target in
            SettingsManualUpdateSheet(
                targetTitle: target == .codexkit ? L.settingsUpdatesCodexkitTitle : L.settingsUpdatesCLIProxyAPITitle,
                currentVersion: self.currentVersion(for: target),
                latestVersion: self.latestVersion(for: target),
                statusText: self.statusText(for: target),
                actionTitle: self.actionTitle(for: target),
                isActionDisabled: self.isActionDisabled(for: target),
                onAction: { self.performAction(for: target) }
            )
        }
    }

    private func updateCard(
        title: String,
        autoCheck: Binding<Bool>,
        autoInstall: Binding<Bool>,
        schedule: Binding<CodexBarUpdateCheckSchedule>,
        detailNote: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))

            Toggle(L.settingsUpdatesAutoCheckTitle, isOn: autoCheck)
            Toggle(L.settingsUpdatesAutoInstallTitle, isOn: autoInstall)

            HStack {
                Text(L.settingsUpdatesScheduleTitle)
                Spacer()
                Picker("", selection: schedule) {
                    ForEach(CodexBarUpdateCheckSchedule.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140)
            }

            Button(L.settingsUpdatesManualCheckAction, action: action)

            Text(detailNote)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }

    private func presentManualCheck(_ target: ManualCheckTarget) {
        self.activeManualCheckTarget = target
        switch target {
        case .codexkit:
            Task { await self.updateCoordinator.checkForUpdates(trigger: .manual) }
        case .cliProxyAPI:
            Task { await self.updateCoordinator.checkCLIProxyAPIForUpdates(trigger: .manual) }
        }
    }

    private func currentVersion(for target: ManualCheckTarget) -> String {
        switch target {
        case .codexkit:
            return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        case .cliProxyAPI:
            switch self.updateCoordinator.cliProxyAPIState {
            case let .upToDate(installedVersion, _):
                return installedVersion
            case let .updateAvailable(availability):
                return availability.installedVersion
            case let .executing(availability):
                return availability.installedVersion
            case .idle, .checking, .failed:
                return self.cliProxyAPIInstalledVersionProvider.resolveInstalledVersion()
            }
        }
    }

    private func latestVersion(for target: ManualCheckTarget) -> String {
        switch target {
        case .codexkit:
            if let availability = self.updateCoordinator.pendingAvailability {
                return availability.release.version
            }
            switch self.updateCoordinator.state {
            case let .upToDate(_, checkedVersion):
                return checkedVersion
            case let .executing(availability):
                return availability.release.version
            case let .updateAvailable(availability):
                return availability.release.version
            case .idle, .checking, .failed:
                return L.settingsUpdatesUnknownVersion
            }
        case .cliProxyAPI:
            if let availability = self.updateCoordinator.cliProxyAPIPendingAvailability {
                return availability.release.version
            }
            switch self.updateCoordinator.cliProxyAPIState {
            case let .upToDate(_, checkedVersion):
                return checkedVersion
            case let .executing(availability):
                return availability.release.version
            case let .updateAvailable(availability):
                return availability.release.version
            case .idle, .checking, .failed:
                return L.settingsUpdatesUnknownVersion
            }
        }
    }

    private func statusText(for target: ManualCheckTarget) -> String {
        switch target {
        case .codexkit:
            switch self.updateCoordinator.state {
            case .idle:
                return L.settingsUpdatesIdle
            case .checking:
                return L.settingsUpdatesChecking
            case let .upToDate(currentVersion, _):
                return L.settingsUpdatesUpToDate(currentVersion)
            case let .updateAvailable(availability):
                return L.settingsUpdatesAvailable(
                    availability.currentVersion,
                    availability.release.version
                )
            case let .executing(availability):
                return L.settingsUpdatesExecuting(availability.release.version)
            case let .failed(message):
                return L.settingsUpdatesFailed(message)
            }
        case .cliProxyAPI:
            switch self.updateCoordinator.cliProxyAPIState {
            case .idle:
                return L.settingsUpdatesIdle
            case .checking:
                return L.settingsUpdatesChecking
            case let .upToDate(installedVersion, _):
                return L.settingsUpdatesUpToDate(installedVersion)
            case let .updateAvailable(availability):
                return L.settingsUpdatesAvailable(
                    availability.installedVersion,
                    availability.release.version
                )
            case let .executing(availability):
                return L.settingsUpdatesExecuting(availability.release.version)
            case let .failed(message):
                return L.settingsUpdatesFailed(message)
            }
        }
    }

    private func actionTitle(for target: ManualCheckTarget) -> String {
        switch target {
        case .codexkit:
            return self.updateCoordinator.pendingAvailability == nil ? L.settingsUpdatesManualCheckAction : L.settingsUpdatesInstallAction
        case .cliProxyAPI:
            return self.updateCoordinator.cliProxyAPIPendingAvailability == nil ? L.settingsUpdatesManualCheckAction : L.settingsUpdatesInstallAction
        }
    }

    private func isActionDisabled(for target: ManualCheckTarget) -> Bool {
        switch target {
        case .codexkit:
            return self.updateCoordinator.isChecking
        case .cliProxyAPI:
            return self.updateCoordinator.isCheckingCLIProxyAPIUpdates
        }
    }

    private func performAction(for target: ManualCheckTarget) {
        switch target {
        case .codexkit:
            if self.updateCoordinator.pendingAvailability != nil {
                Task { await self.updateCoordinator.handleToolbarAction() }
            } else {
                Task { await self.updateCoordinator.checkForUpdates(trigger: .manual) }
            }
        case .cliProxyAPI:
            if self.updateCoordinator.cliProxyAPIPendingAvailability != nil {
                Task { await self.updateCoordinator.handleCLIProxyAPIAction() }
            } else {
                Task { await self.updateCoordinator.checkCLIProxyAPIForUpdates(trigger: .manual) }
            }
        }
    }
}

private struct SettingsManualUpdateSheet: View {
    let targetTitle: String
    let currentVersion: String
    let latestVersion: String
    let statusText: String
    let actionTitle: String
    let isActionDisabled: Bool
    let onAction: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L.settingsUpdatesManualDialogTitle(targetTitle))
                .font(.system(size: 15, weight: .semibold))

            VStack(alignment: .leading, spacing: 10) {
                SettingsUpdatesInfoRow(title: L.settingsUpdatesInstalledVersionTitle, value: self.currentVersion)
                SettingsUpdatesInfoRow(title: L.settingsUpdatesLatestVersionTitle, value: self.latestVersion)
                SettingsUpdatesInfoRow(title: L.settingsUpdatesStatusTitle, value: self.statusText)
            }

            HStack {
                Spacer()
                Button(L.cancel) {
                    self.dismiss()
                }
                Button(self.actionTitle) {
                    self.onAction()
                }
                .disabled(self.isActionDisabled)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
    }
}

private struct SettingsAPIServicePage: View {
    @ObservedObject var coordinator: SettingsWindowCoordinator
    @ObservedObject var store: TokenStore
    @State private var isImportingConfiguration = false
    @State private var importSourcePath = ""
    @State private var revealsClientAPIKey = false
    @State private var previewSnapshot: CLIProxyAPISyncSnapshot?

    private let probeService = CLIProxyAPIProbeService.shared

    private var displayedState: CLIProxyAPIServiceState {
        var state = self.store.cliProxyAPIState
        if let previewSnapshot {
            state.config.host = previewSnapshot.values.host
            state.config.port = previewSnapshot.values.port
            state.config.managementSecretKey = previewSnapshot.values.managementSecretKey
            state.config.clientAPIKey = previewSnapshot.values.clientAPIKey
            state.config.routingStrategy = previewSnapshot.values.routingStrategy
            state.config.switchProjectOnQuotaExceeded = previewSnapshot.values.switchProjectOnQuotaExceeded
            state.config.switchPreviewModelOnQuotaExceeded = previewSnapshot.values.switchPreviewModelOnQuotaExceeded
            state.config.requestRetry = previewSnapshot.values.requestRetry
            state.config.maxRetryInterval = previewSnapshot.values.maxRetryInterval
            state.config.disableCooling = previewSnapshot.values.disableCooling
            state.modelIDs = previewSnapshot.modelIDs
            state.authFileCount = previewSnapshot.authFileCount
            state.modelCount = previewSnapshot.modelCount
            state.totalRequests = previewSnapshot.totalRequests
            state.failedRequests = previewSnapshot.failedRequests
            state.totalTokens = previewSnapshot.totalTokens
            state.quotaSnapshot = previewSnapshot.quotaSnapshot
            state.accountUsageItems = previewSnapshot.accountUsageItems
            state.observedAuthFiles = previewSnapshot.observedAuthFiles
        }
        return state
    }

    private var memberGroups: [CLIProxyAPIAccountGroup] {
        CLIProxyAPIAccountGrouping.groupedMemberAccounts(
            localAccounts: self.store.accounts,
            importedUsageItems: self.displayedState.accountUsageItems
        )
    }


    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(SettingsPage.apiService.title)
                .font(.system(size: 16, weight: .semibold))

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    self.addressCard
                    self.clientAPIKeyCard
                    self.portCard
                }

                self.importConfigSection
                self.runtimeControlsSection

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(L.settingsAPIServiceMembers)
                            .font(.system(size: 12, weight: .medium))
                        if let count = self.displayedState.authFileCount {
                            self.memberCountTag(L.settingsAPIServiceAuthFileCount(count))
                        }
                        if let count = self.displayedState.modelCount {
                            self.memberCountTag(L.settingsAPIServiceModelCount(count))
                        }
                        Spacer(minLength: 0)
                        Toggle(
                            L.settingsAPIServiceRestrictFreeAccounts,
                            isOn: Binding(
                                get: { self.coordinator.draft.cliProxyAPIRestrictFreeAccounts },
                                set: { enabled in
                                    self.coordinator.update(\.cliProxyAPIRestrictFreeAccounts, to: enabled, field: .cliProxyAPIRestrictFreeAccounts)
                                    guard enabled else { return }
                                    let filteredIDs = self.coordinator.draft.cliProxyAPIMemberAccountIDs.filter { accountID in
                                        self.store.oauthAccount(accountID: accountID)?.isExplicitFreePlanType == false
                                    }
                                    self.coordinator.update(\.cliProxyAPIMemberAccountIDs, to: Array(Set(filteredIDs)).sorted(), field: .cliProxyAPIMemberAccountIDs)
                                }
                            )
                        )
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                    }

                    if self.memberGroups.isEmpty {
                        Text(L.settingsAPIServiceNoImportedAccounts)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(self.memberGroups) { group in
                            SettingsAPIServiceMemberGroupView(
                                group: group,
                                selectedMemberIDs: Binding(
                                    get: { self.coordinator.draft.cliProxyAPIMemberAccountIDs },
                                    set: { self.coordinator.update(\.cliProxyAPIMemberAccountIDs, to: $0, field: .cliProxyAPIMemberAccountIDs) }
                                ),
                                restrictFreeAccounts: Binding(
                                    get: { self.coordinator.draft.cliProxyAPIRestrictFreeAccounts },
                                    set: { self.coordinator.update(\.cliProxyAPIRestrictFreeAccounts, to: $0, field: .cliProxyAPIRestrictFreeAccounts) }
                                ),
                                prioritiesByAccountID: Binding(
                                    get: { self.coordinator.draft.cliProxyAPIMemberPrioritiesByAccountID },
                                    set: { self.coordinator.update(\.cliProxyAPIMemberPrioritiesByAccountID, to: $0, field: .cliProxyAPIMemberPrioritiesByAccountID) }
                                )
                            )
                        }
                    }
                }

                self.modelIDsSection

                Text(L.settingsAPIServiceHint)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var addressCard: some View {
        SettingsAPIServiceFieldCard(title: L.settingsAPIServiceAddress) {
            TextField(
                L.settingsAPIServiceAddressPlaceholder,
                text: Binding(
                    get: { self.coordinator.draft.cliProxyAPIHost },
                    set: { self.coordinator.update(\.cliProxyAPIHost, to: $0, field: .cliProxyAPIHost) }
                )
            )
            .textFieldStyle(.roundedBorder)
        }
    }

    private var clientAPIKeyCard: some View {
        SettingsAPIServiceFieldCard(
            title: L.settingsAPIServiceClientAPIKey,
            headerActions: {
                HStack(spacing: 6) {
                    SettingsAPIServiceIconButton(systemName: self.revealsClientAPIKey ? "eye.slash" : "eye") {
                        self.revealsClientAPIKey.toggle()
                    }
                    SettingsAPIServiceIconButton(systemName: "doc.on.doc") {
                        self.copyToPasteboard(self.coordinator.draft.cliProxyAPIClientAPIKey)
                    }
                    SettingsAPIServiceIconButton(systemName: "arrow.triangle.2.circlepath") {
                        self.coordinator.update(
                            \.cliProxyAPIClientAPIKey,
                            to: CLIProxyAPIService.shared.generateDistinctClientAPIKey(
                                managementSecretKey: self.coordinator.draft.cliProxyAPIManagementSecretKey
                            ),
                            field: .cliProxyAPIClientAPIKey
                        )
                    }
                }
            }
        ) {
            HStack(spacing: 8) {
                Group {
                    if self.revealsClientAPIKey {
                        TextField(
                            L.settingsAPIServiceClientAPIKeyPlaceholder,
                            text: Binding(
                                get: { self.coordinator.draft.cliProxyAPIClientAPIKey },
                                set: { self.coordinator.update(\.cliProxyAPIClientAPIKey, to: $0, field: .cliProxyAPIClientAPIKey) }
                            )
                        )
                    } else {
                        SecureField(
                            L.settingsAPIServiceClientAPIKeyPlaceholder,
                            text: Binding(
                                get: { self.coordinator.draft.cliProxyAPIClientAPIKey },
                                set: { self.coordinator.update(\.cliProxyAPIClientAPIKey, to: $0, field: .cliProxyAPIClientAPIKey) }
                            )
                        )
                    }
                }
                .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var portCard: some View {
        SettingsAPIServiceFieldCard(title: L.settingsAPIServicePort) {
            HStack(spacing: 8) {
                TextField(
                    L.settingsAPIServicePort,
                    text: Binding(
                        get: { String(self.coordinator.draft.cliProxyAPIPort) },
                        set: { value in
                            let digits = value.filter(\.isNumber)
                            if let port = Int(digits), (1...65535).contains(port) {
                                self.coordinator.update(\.cliProxyAPIPort, to: port, field: .cliProxyAPIPort)
                            }
                        }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

                SettingsAPIServiceIconButton(systemName: "arrow.triangle.2.circlepath") {
                    self.coordinator.update(
                        \.cliProxyAPIPort,
                        to: CLIProxyAPIService.shared.generateRandomAvailablePort(),
                        field: .cliProxyAPIPort
                    )
                }
            }
        }
    }

    private var importConfigSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L.settingsAPIServiceImportConfig)
                .font(.system(size: 12, weight: .medium))

            HStack(spacing: 8) {
                SettingsAPIServiceIconButton(
                    systemName: "folder",
                    helpText: L.settingsAPIServiceImportPath
                ) {
                    self.chooseCPAPath()
                }

                SettingsAPIServiceIconButton(
                    systemName: "magnifyingglass",
                    helpText: L.settingsAPIServiceDetectPath
                ) {
                    self.detectExternalCPAPath()
                }

                SettingsAPIServiceIconButton(
                    systemName: self.isImportingConfiguration ? "arrow.down.circle" : "square.and.arrow.down",
                    isDisabled: self.isImportingConfiguration || self.importSourcePath.isEmpty,
                    helpText: self.isImportingConfiguration ? L.settingsAPIServiceImporting : L.settingsAPIServiceImportAction
                ) {
                    self.importFromSelectedPath()
                }
            }
        }
    }

    private var runtimeControlsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.settingsAPIServiceRuntimeControls)
                .font(.system(size: 12, weight: .medium))

            HStack(alignment: .top, spacing: 12) {
                self.routingStrategyCard
                self.retryPolicyCard
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle(
                    L.settingsAPIServiceSwitchProjectOnQuota,
                    isOn: Binding(
                        get: { self.coordinator.draft.cliProxyAPISwitchProjectOnQuotaExceeded },
                        set: { self.coordinator.update(\.cliProxyAPISwitchProjectOnQuotaExceeded, to: $0, field: .cliProxyAPISwitchProjectOnQuotaExceeded) }
                    )
                )
                Toggle(
                    L.settingsAPIServiceSwitchPreviewModelOnQuota,
                    isOn: Binding(
                        get: { self.coordinator.draft.cliProxyAPISwitchPreviewModelOnQuotaExceeded },
                        set: { self.coordinator.update(\.cliProxyAPISwitchPreviewModelOnQuotaExceeded, to: $0, field: .cliProxyAPISwitchPreviewModelOnQuotaExceeded) }
                    )
                )
                Toggle(
                    L.settingsAPIServiceDisableCooling,
                    isOn: Binding(
                        get: { self.coordinator.draft.cliProxyAPIDisableCooling },
                        set: { self.coordinator.update(\.cliProxyAPIDisableCooling, to: $0, field: .cliProxyAPIDisableCooling) }
                    )
                )
            }
        }
    }

    private var routingStrategyCard: some View {
        SettingsAPIServiceFieldCard(title: L.settingsAPIServiceRoutingStrategy) {
            Picker(
                L.settingsAPIServiceRoutingStrategy,
                selection: Binding(
                    get: { self.coordinator.draft.cliProxyAPIRoutingStrategy },
                    set: { self.coordinator.update(\.cliProxyAPIRoutingStrategy, to: $0, field: .cliProxyAPIRoutingStrategy) }
                )
            ) {
                Text(L.settingsAPIServiceRoutingRoundRobin).tag(CLIProxyAPIRoutingStrategy.roundRobin)
                Text(L.settingsAPIServiceRoutingFillFirst).tag(CLIProxyAPIRoutingStrategy.fillFirst)
            }
            .pickerStyle(.segmented)
        }
    }

    private var retryPolicyCard: some View {
        SettingsAPIServiceFieldCard(title: L.settingsAPIServiceRetryPolicy) {
            HStack(spacing: 8) {
                TextField(
                    L.settingsAPIServiceRequestRetry,
                    text: Binding(
                        get: { String(self.coordinator.draft.cliProxyAPIRequestRetry) },
                        set: { value in
                            let digits = value.filter(\.isNumber)
                            self.coordinator.update(\.cliProxyAPIRequestRetry, to: Int(digits) ?? 0, field: .cliProxyAPIRequestRetry)
                        }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
                .multilineTextAlignment(.center)

                TextField(
                    L.settingsAPIServiceMaxRetryInterval,
                    text: Binding(
                        get: { String(self.coordinator.draft.cliProxyAPIMaxRetryInterval) },
                        set: { value in
                            let digits = value.filter(\.isNumber)
                            self.coordinator.update(\.cliProxyAPIMaxRetryInterval, to: Int(digits) ?? 0, field: .cliProxyAPIMaxRetryInterval)
                        }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 90)
                .multilineTextAlignment(.center)
            }
        }
    }

    private var modelIDsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(L.settingsAPIServiceModelIDsTitle)
                    .font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
                Button(L.settingsAPIServiceModelIDsCopyAll) {
                    self.copyToPasteboard(self.displayedState.modelIDs.joined(separator: "\n"))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(self.displayedState.modelIDs.isEmpty)
            }

            if self.displayedState.modelIDs.isEmpty {
                Text(L.settingsAPIServiceModelIDsEmpty)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                Text(self.displayedState.modelIDs.joined(separator: "\n"))
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
    }


    private func copyToPasteboard(_ value: String) {
        guard value.isEmpty == false else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }


    private func detectExternalCPAPath() {
        guard let detected = self.probeService.detectExternalRepositoryRoot() else {
            self.importSourcePath = ""
            self.coordinator.validationMessage = L.settingsAPIServiceNoDetectedPath
            return
        }
        self.importSourcePath = detected.path
        self.coordinator.validationMessage = L.settingsAPIServiceDetectedPathReady
    }

    private func importFromSelectedPath() {
        guard self.importSourcePath.isEmpty == false else {
            self.coordinator.validationMessage = L.settingsAPIServiceImportPathRequired
            return
        }
        self.importConfiguration(from: self.importSourcePath)
    }

    private func chooseCPAPath() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = L.settingsAPIServiceChoosePath

        if panel.runModal() == .OK, let url = panel.url {
            self.importSourcePath = url.path
            self.coordinator.validationMessage = L.settingsAPIServiceImportPathReady
        }
    }

    private func importConfiguration(from path: String) {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPath.isEmpty == false else { return }
        self.isImportingConfiguration = true
        self.coordinator.validationMessage = nil
        self.previewSnapshot = nil
        Task { @MainActor in
            defer { self.isImportingConfiguration = false }
            do {
                let importedAccounts = self.probeService.localTokenAccounts(repoRootPath: trimmedPath)
                for account in importedAccounts {
                    self.store.addOrUpdate(account)
                }
                let snapshot = try await self.probeService.syncSnapshot(
                    host: self.coordinator.draft.cliProxyAPIHost,
                    port: self.coordinator.draft.cliProxyAPIPort,
                    managementSecretKey: self.coordinator.draft.cliProxyAPIManagementSecretKey,
                    explicitRepoRootPath: trimmedPath,
                    localAccounts: self.store.accounts
                )
                self.applySuggestedValues(snapshot.values)
                let mergedMemberIDs = Array(Set(self.coordinator.draft.cliProxyAPIMemberAccountIDs + snapshot.memberAccountIDs)).sorted()
                self.coordinator.update(\.cliProxyAPIMemberAccountIDs, to: mergedMemberIDs, field: .cliProxyAPIMemberAccountIDs)
                let importedPriorities = snapshot.observedAuthFiles.reduce(into: self.coordinator.draft.cliProxyAPIMemberPrioritiesByAccountID) { partial, file in
                    guard let localAccountID = file.localAccountID,
                          let priority = file.priority else { return }
                    partial[localAccountID] = priority
                }
                self.coordinator.update(\.cliProxyAPIMemberPrioritiesByAccountID, to: importedPriorities, field: .cliProxyAPIMemberPrioritiesByAccountID)
                self.previewSnapshot = snapshot
            } catch {
                self.previewSnapshot = nil
                self.coordinator.validationMessage = error.localizedDescription
            }
        }
    }

    private func applySuggestedValues(_ values: CLIProxyAPISuggestedDraftValues) {
        self.coordinator.update(\.cliProxyAPIHost, to: values.host, field: .cliProxyAPIHost)
        self.coordinator.update(\.cliProxyAPIPort, to: values.port, field: .cliProxyAPIPort)
        self.coordinator.update(\.cliProxyAPIManagementSecretKey, to: values.managementSecretKey, field: .cliProxyAPIManagementSecretKey)
        self.coordinator.update(\.cliProxyAPIClientAPIKey, to: values.clientAPIKey, field: .cliProxyAPIClientAPIKey)
        self.coordinator.update(\.cliProxyAPIRoutingStrategy, to: values.routingStrategy, field: .cliProxyAPIRoutingStrategy)
        self.coordinator.update(\.cliProxyAPISwitchProjectOnQuotaExceeded, to: values.switchProjectOnQuotaExceeded, field: .cliProxyAPISwitchProjectOnQuotaExceeded)
        self.coordinator.update(\.cliProxyAPISwitchPreviewModelOnQuotaExceeded, to: values.switchPreviewModelOnQuotaExceeded, field: .cliProxyAPISwitchPreviewModelOnQuotaExceeded)
        self.coordinator.update(\.cliProxyAPIRequestRetry, to: values.requestRetry, field: .cliProxyAPIRequestRetry)
        self.coordinator.update(\.cliProxyAPIMaxRetryInterval, to: values.maxRetryInterval, field: .cliProxyAPIMaxRetryInterval)
        self.coordinator.update(\.cliProxyAPIDisableCooling, to: values.disableCooling, field: .cliProxyAPIDisableCooling)
    }

    private func memberCountTag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.12))
            .foregroundColor(.secondary)
            .clipShape(Capsule())
    }

}

private struct SettingsAPIServiceFieldCard<Content: View, HeaderActions: View>: View {
    let title: String
    @ViewBuilder let headerActions: HeaderActions
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(self.title)
                    .font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
                self.headerActions
            }
            self.content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(minHeight: 92)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

private extension SettingsAPIServiceFieldCard where HeaderActions == EmptyView {
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.headerActions = EmptyView()
        self.content = content()
    }
}

private struct SettingsAPIServiceIconButton: View {
    let systemName: String
    var isDisabled = false
    var helpText: String?
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            Image(systemName: self.systemName)
                .font(.system(size: 12, weight: .medium))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(self.isDisabled)
        .help(self.helpText ?? "")
    }
}

private struct SettingsAPIServiceAccountUsageRow: View {
    let item: CLIProxyAPIAccountUsageItem

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            self.planBadge

            Spacer(minLength: 0)

            self.metricBadge(L.settingsAPIServiceSuccessFailed(self.item.successRequests, self.item.failedRequests))
            self.metricBadge(L.settingsAPIServiceTokens(self.item.totalTokens))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }

    private var planBadge: some View {
        Text(self.item.planType.uppercased())
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(self.planColor.opacity(0.16))
            .foregroundColor(self.planColor)
            .clipShape(Capsule())
    }

    private func metricBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.12))
            .foregroundColor(.secondary)
            .clipShape(Capsule())
    }

    private var planColor: Color {
        switch self.item.planType.lowercased() {
        case "team":
            return Color(red: 0.34, green: 0.60, blue: 0.92)
        case "plus":
            return Color(red: 0.32, green: 0.72, blue: 0.46)
        default:
            return .secondary
        }
    }
}

private struct SettingsAPIServiceQuotaAccountRow: View {
    let item: CLIProxyAPIQuotaAccountItem

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(self.item.planType.uppercased())
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.accentColor.opacity(0.12))
                .foregroundColor(.accentColor)
                .clipShape(Capsule())

            Spacer(minLength: 0)

            Text("\(L.settingsAPIServiceRemaining5h) \(self.item.fiveHourRemainingPercent.map(String.init) ?? "--")%")
                .font(.system(size: 11, weight: .medium))
            Text("\(L.settingsAPIServiceRemainingWeekly) \(self.item.weeklyRemainingPercent.map(String.init) ?? "--")%")
                .font(.system(size: 11, weight: .medium))
            Text(self.item.refreshStatus.rawValue)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(self.item.refreshStatus == .ok ? .green : .orange)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}

private struct SettingsAPIServiceMemberGroupView: View {
    let group: CLIProxyAPIAccountGroup
    @Binding var selectedMemberIDs: [String]
    @Binding var restrictFreeAccounts: Bool
    @Binding var prioritiesByAccountID: [String: Int]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(self.group.email)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)

            ForEach(self.group.memberItems) { item in
                let isChecked =
                    item.accountIDs.isEmpty == false &&
                    item.accountIDs.allSatisfy { self.selectedMemberIDs.contains($0) }
                let isFreeSelectionBlocked =
                    self.restrictFreeAccounts &&
                    self.isExplicitFreePlanType(item.planType) &&
                    isChecked == false
                HStack(spacing: 10) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { isChecked },
                            set: { enabled in
                                guard item.isSelectable else { return }
                                if enabled && isFreeSelectionBlocked {
                                    return
                                }
                                var ids = self.selectedMemberIDs
                                if enabled {
                                    for accountID in item.accountIDs where ids.contains(accountID) == false {
                                        ids.append(accountID)
                                    }
                                } else {
                                    ids.removeAll { item.accountIDs.contains($0) }
                                }
                                self.selectedMemberIDs = ids.sorted()
                            }
                        )
                    )
                    .labelsHidden()
                    .disabled(item.isSelectable == false || isFreeSelectionBlocked)

                    self.planBadge(item.planType)

                    Spacer(minLength: 0)

                    HStack(spacing: 6) {
                        Text(L.settingsAPIServicePriorityLabel)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        TextField(
                            "0",
                            text: Binding(
                                get: { self.priorityText(for: item.accountIDs) },
                                set: { self.updatePriority($0, for: item.accountIDs) }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 56)
                        .multilineTextAlignment(.center)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }

    private func planBadge(_ planType: String) -> some View {
        Text(planType.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(self.planColor(planType).opacity(0.16))
            .foregroundColor(self.planColor(planType))
            .clipShape(Capsule())
    }

    private func planColor(_ planType: String) -> Color {
        switch planType.lowercased() {
        case "team": return Color(red: 0.34, green: 0.60, blue: 0.92)
        case "plus": return Color(red: 0.32, green: 0.72, blue: 0.46)
        default: return .secondary
        }
    }

    private func priorityText(for accountIDs: [String]) -> String {
        let values = accountIDs.compactMap { self.prioritiesByAccountID[$0] }
        guard values.isEmpty == false else { return "0" }
        if Set(values).count == 1, let first = values.first {
            return String(first)
        }
        return ""
    }

    private func isExplicitFreePlanType(_ planType: String) -> Bool {
        let normalized = planType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty == false && normalized.contains("free")
    }

    private func updatePriority(_ text: String, for accountIDs: [String]) {
        let digits = text.filter(\.isNumber)
        var next = self.prioritiesByAccountID
        if digits.isEmpty {
            for accountID in accountIDs {
                next.removeValue(forKey: accountID)
            }
        } else if let value = Int(digits) {
            for accountID in accountIDs {
                next[accountID] = value
            }
        }
        self.prioritiesByAccountID = next
    }
}

private struct SettingsAPIServiceUsageGroupView: View {
    let group: CLIProxyAPIUsageGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(group.email)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)

            ForEach(group.usageItems) { usageItem in
                SettingsAPIServiceAccountUsageRow(item: usageItem)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}

private struct SettingsAPIServiceQuotaGroupView: View {
    let group: CLIProxyAPIQuotaGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(group.email)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)

            ForEach(group.items) { item in
                SettingsAPIServiceQuotaAccountRow(item: item)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}

private struct SettingsUpdatesInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(self.title)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 160, alignment: .leading)
            Text(self.value)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.06))
        )
    }
}

private struct SettingsManualActivationBehaviorSection: View {
    @Binding var behavior: CodexBarOpenAIManualActivationBehavior
    @Binding var preferredCodexAppPath: String?
    @Binding var validationMessage: String?

    let codexAppPathPanelService: CodexAppPathPanelService
    let showsCodexAppPathSection: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.manualActivationBehaviorTitle)
                .font(.system(size: 12, weight: .medium))

            Text(L.manualActivationBehaviorHint)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(CodexBarOpenAIManualActivationBehavior.allCases) { option in
                    Button {
                        self.behavior = option
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: self.behavior == option ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(self.behavior == option ? .accentColor : .secondary)
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(option.title)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.primary)
                                Text(option.detail)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(self.behavior == option ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.06))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if self.showsCodexAppPathSection {
                SettingsCodexAppPathSection(
                    preferredCodexAppPath: self.$preferredCodexAppPath,
                    validationMessage: self.$validationMessage,
                    codexAppPathPanelService: self.codexAppPathPanelService
                )
            }
        }
    }
}

private struct SettingsAccountOrderingModeSection: View {
    @Binding var mode: CodexBarOpenAIAccountOrderingMode

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.accountOrderingModeTitle)
                .font(.system(size: 12, weight: .medium))

            Text(L.accountOrderingModeHint)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(CodexBarOpenAIAccountOrderingMode.allCases) { option in
                    Button {
                        self.mode = option
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: self.mode == option ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(self.mode == option ? .accentColor : .secondary)
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(option.title)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.primary)
                                Text(option.detail)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(self.mode == option ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.06))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct SettingsAccountActivationScopeSection: View {
    @Binding var scopeMode: CodexBarActivationScopeMode
    @Binding var rootPaths: [String]
    @Binding var validationMessage: String?

    let showsPathsSection: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.accountActivationScopeTitle)
                .font(.system(size: 12, weight: .medium))

            Text(L.accountActivationScopeHint)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(CodexBarActivationScopeMode.allCases) { option in
                    Button {
                        self.scopeMode = option
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: self.scopeMode == option ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(self.scopeMode == option ? .accentColor : .secondary)
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(option.title)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.primary)
                                Text(option.detail)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(self.scopeMode == option ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.06))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if self.showsPathsSection {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(L.accountActivationRootPathsTitle)
                            .font(.system(size: 11, weight: .medium))
                        Spacer(minLength: 0)
                        Button {
                            self.addRootPath()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if self.rootPaths.isEmpty {
                        Text(L.accountActivationRootPathsEmpty)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(Array(self.rootPaths.enumerated()), id: \.offset) { index, path in
                            SettingsAccountActivationPathRow(
                                path: path,
                                onChoose: { self.chooseRootPath(at: index) },
                                onRemove: { self.removeRootPath(at: index) }
                            )
                        }
                    }
                }
            }
        }
    }

    private func addRootPath() {
        self.rootPaths.append("")
        self.validationMessage = nil
    }

    private func removeRootPath(at index: Int) {
        guard self.rootPaths.indices.contains(index) else { return }
        self.rootPaths.remove(at: index)
        self.validationMessage = nil
    }

    private func chooseRootPath(at index: Int) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = L.accountActivationRootPathChoose

        if panel.runModal() == .OK, let url = panel.url {
            guard self.rootPaths.indices.contains(index) else { return }
            self.rootPaths[index] = url.path
            self.validationMessage = nil
        }
    }
}

private struct SettingsAccountActivationPathRow: View {
    let path: String
    let onChoose: () -> Void
    let onRemove: () -> Void

    private var codexPath: String {
        let trimmed = self.path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "" }
        return URL(fileURLWithPath: trimmed, isDirectory: true)
            .appendingPathComponent(".codex", isDirectory: true)
            .path
    }

    private var hasCodexDirectory: Bool {
        self.codexPath.isEmpty == false && FileManager.default.fileExists(atPath: self.codexPath)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(self.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? L.accountActivationRootPathPlaceholder : self.path)
                    .font(.system(size: 11, weight: self.path.isEmpty ? .regular : .medium, design: self.path.isEmpty ? .default : .monospaced))
                    .foregroundColor(self.path.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(self.hasCodexDirectory ? L.accountActivationCodexDetected(self.codexPath) : L.accountActivationCodexMissing)
                    .font(.system(size: 10))
                    .foregroundColor(self.hasCodexDirectory ? .secondary : .orange)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)

            Button(L.accountActivationRootPathChoose) {
                self.onChoose()
            }
            .controlSize(.small)

            Button(role: .destructive) {
                self.onRemove()
            } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.06))
        )
    }
}

private struct SettingsAccountOrderSection: View {
    @ObservedObject var coordinator: SettingsWindowCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.accountOrderTitle)
                .font(.system(size: 12, weight: .medium))

            Text(L.accountOrderHint)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if self.coordinator.orderedAccounts.isEmpty {
                Text(L.noOpenAIAccountsForOrdering)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(self.coordinator.orderedAccounts.enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.system(size: 11, weight: .medium))
                                Text(item.detail)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }

                            Spacer(minLength: 12)

                            HStack(spacing: 6) {
                                Button(L.moveUp) {
                                    self.coordinator.moveAccount(accountID: item.id, offset: -1)
                                }
                                .disabled(index == 0)

                                Button(L.moveDown) {
                                    self.coordinator.moveAccount(accountID: item.id, offset: 1)
                                }
                                .disabled(index == self.coordinator.orderedAccounts.count - 1)
                            }
                            .controlSize(.small)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.secondary.opacity(0.06))
                        )
                    }
                }
            }
        }
    }
}

private struct SettingsCodexAppPathSection: View {
    @Binding var preferredCodexAppPath: String?
    @Binding var validationMessage: String?

    let codexAppPathPanelService: CodexAppPathPanelService

    private var status: CodexDesktopPreferredAppPathStatus {
        CodexDesktopLaunchProbeService.preferredAppPathStatus(for: self.preferredCodexAppPath)
    }

    private var displayedValue: String {
        switch self.status {
        case .automatic:
            return L.codexAppPathAutomaticStatus
        case .manualValid(let path), .manualInvalid(let path):
            return path
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(L.codexAppPathTitle)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 72, alignment: .leading)

            Group {
                switch self.status {
                case .automatic:
                    Text(self.displayedValue)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                case .manualValid, .manualInvalid:
                    Text(self.displayedValue)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(self.statusColor)
                }
            }
            .lineLimit(1)
            .truncationMode(.middle)

            Spacer(minLength: 0)

            Button(L.codexAppPathChooseAction) {
                self.chooseCodexApp()
            }

            if (self.preferredCodexAppPath ?? "").isEmpty == false {
                Button(L.codexAppPathResetAction) {
                    self.preferredCodexAppPath = nil
                    self.validationMessage = nil
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    private var statusColor: Color {
        switch self.status {
        case .automatic:
            return .secondary
        case .manualValid:
            return .primary
        case .manualInvalid:
            return .orange
        }
    }

    private func chooseCodexApp() {
        guard let selectedURL = self.codexAppPathPanelService.requestCodexAppURL(
            currentPath: self.preferredCodexAppPath
        ) else {
            return
        }

        guard let validatedURL = CodexDesktopLaunchProbeService.validatedPreferredCodexAppURL(
            from: selectedURL.path
        ) else {
            self.validationMessage = L.codexAppPathInvalidSelection
            return
        }

        self.preferredCodexAppPath = validatedURL.path
        self.validationMessage = nil
    }
}

private struct SettingsUsageDisplayModeSection: View {
    @Binding var usageDisplayMode: CodexBarUsageDisplayMode

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.usageDisplayModeTitle)
                .font(.system(size: 12, weight: .medium))

            Picker(L.usageDisplayModeTitle, selection: self.$usageDisplayMode) {
                ForEach(CodexBarUsageDisplayMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

private struct SettingsMenuBarQuotaVisibilitySection: View {
    @Binding var visibility: CodexBarMenuBarQuotaVisibility

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.settingsMenuBarQuotaVisibilityTitle)
                .font(.system(size: 12, weight: .medium))

            Text(L.settingsMenuBarQuotaVisibilityHint)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(CodexBarMenuBarQuotaVisibility.allCases) { option in
                    SettingsOptionCard(
                        isSelected: self.visibility == option,
                        title: option.title,
                        detail: option.detail
                    ) {
                        self.visibility = option
                    }
                }
            }
        }
    }
}

private struct SettingsMenuBarAPIServiceStatusSection: View {
    @Binding var visibility: CodexBarMenuBarAPIServiceStatusVisibility

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.settingsMenuBarAPIServiceStatusTitle)
                .font(.system(size: 12, weight: .medium))

            Text(L.settingsMenuBarAPIServiceStatusHint)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(CodexBarMenuBarAPIServiceStatusVisibility.allCases) { option in
                    SettingsOptionCard(
                        isSelected: self.visibility == option,
                        title: option.title,
                        detail: option.detail
                    ) {
                        self.visibility = option
                    }
                }
            }
        }
    }
}

private struct SettingsOptionCard: View {
    let isSelected: Bool
    let title: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: self.isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(self.isSelected ? .accentColor : .secondary)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 3) {
                    Text(self.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                    Text(self.detail)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(self.isSelected ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsQuotaSortSection: View {
    @Binding var plusRelativeWeight: Double
    @Binding var proRelativeToPlusMultiplier: Double
    @Binding var teamRelativeToPlusMultiplier: Double

    private var proAbsoluteWeight: Double {
        self.plusRelativeWeight * self.proRelativeToPlusMultiplier
    }

    private var teamAbsoluteWeight: Double {
        self.plusRelativeWeight * self.teamRelativeToPlusMultiplier
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.quotaSortSettingsTitle)
                .font(.system(size: 12, weight: .medium))

            Text(L.quotaSortSettingsHint)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L.quotaSortPlusWeightTitle)
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Text(L.quotaSortPlusWeightValue(self.plusRelativeWeight))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }

                Slider(
                    value: self.$plusRelativeWeight,
                    in: CodexBarOpenAISettings.QuotaSortSettings.plusRelativeWeightRange,
                    step: 0.5
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L.quotaSortProRatioTitle)
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Text(
                        L.quotaSortProRatioValue(
                            self.proRelativeToPlusMultiplier,
                            absoluteProWeight: self.proAbsoluteWeight
                        )
                    )
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                }

                Slider(
                    value: self.$proRelativeToPlusMultiplier,
                    in: CodexBarOpenAISettings.QuotaSortSettings.proRelativeToPlusRange,
                    step: 0.5
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L.quotaSortTeamRatioTitle)
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Text(
                        L.quotaSortTeamRatioValue(
                            self.teamRelativeToPlusMultiplier,
                            absoluteTeamWeight: self.teamAbsoluteWeight
                        )
                    )
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                }

                Slider(
                    value: self.$teamRelativeToPlusMultiplier,
                    in: CodexBarOpenAISettings.QuotaSortSettings.teamRelativeToPlusRange,
                    step: 0.1
                )
            }
        }
    }
}

private extension SettingsPage {
    var title: String {
        switch self {
        case .accounts:
            return L.settingsAccountsPageTitle
        case .general:
            return L.settingsGeneralPageTitle
        case .usage:
            return L.settingsUsagePageTitle
        case .provider:
            return L.settingsProviderPageTitle
        case .apiService:
            return L.settingsAPIServiceOverviewPageTitle
        case .apiServiceDashboard:
            return L.settingsAPIServiceDashboardPageTitle
        case .apiServiceLogs:
            return L.settingsAPIServiceLogsPageTitle
        case .updates:
            return L.settingsUpdatesPageTitle
        }
    }

    var iconName: String {
        switch self {
        case .accounts:
            return "person.crop.circle"
        case .general:
            return "switch.2"
        case .usage:
            return "chart.bar"
        case .provider:
            return "square.stack.3d.up"
        case .apiService:
            return "slider.horizontal.3"
        case .apiServiceDashboard:
            return "chart.xyaxis.line"
        case .apiServiceLogs:
            return "doc.text.magnifyingglass"
        case .updates:
            return "arrow.trianglehead.2.clockwise"
        }
    }
}

private extension CodexBarMenuBarQuotaVisibility {
    var title: String {
        switch self {
        case .both:
            return L.settingsMenuBarQuotaVisibilityBoth
        case .primaryOnly:
            return L.settingsMenuBarQuotaVisibilityPrimaryOnly
        case .secondaryOnly:
            return L.settingsMenuBarQuotaVisibilitySecondaryOnly
        case .hidden:
            return L.settingsMenuBarQuotaVisibilityHidden
        }
    }

    var detail: String {
        switch self {
        case .both:
            return L.settingsMenuBarQuotaVisibilityBothHint
        case .primaryOnly:
            return L.settingsMenuBarQuotaVisibilityPrimaryOnlyHint
        case .secondaryOnly:
            return L.settingsMenuBarQuotaVisibilitySecondaryOnlyHint
        case .hidden:
            return L.settingsMenuBarQuotaVisibilityHiddenHint
        }
    }
}

private extension CodexBarMenuBarAPIServiceStatusVisibility {
    var title: String {
        switch self {
        case .availableOverTotal:
            return L.settingsMenuBarAPIServiceStatusVisible
        case .hidden:
            return L.settingsMenuBarAPIServiceStatusHidden
        }
    }

    var detail: String {
        switch self {
        case .availableOverTotal:
            return L.settingsMenuBarAPIServiceStatusVisibleHint
        case .hidden:
            return L.settingsMenuBarAPIServiceStatusHiddenHint
        }
    }
}

private extension CodexBarOpenAIManualActivationBehavior {
    var title: String {
        switch self {
        case .updateConfigOnly:
            return L.manualActivationUpdateConfigOnly
        case .launchNewInstance:
            return L.manualActivationLaunchNewInstance
        }
    }

    var detail: String {
        switch self {
        case .updateConfigOnly:
            return L.manualActivationUpdateConfigOnlyHint
        case .launchNewInstance:
            return L.manualActivationLaunchNewInstanceHint
        }
    }
}

private extension CodexBarOpenAIAccountOrderingMode {
    var title: String {
        switch self {
        case .quotaSort:
            return L.accountOrderingModeQuotaSort
        case .manual:
            return L.accountOrderingModeManual
        }
    }

    var detail: String {
        switch self {
        case .quotaSort:
            return L.accountOrderingModeQuotaSortHint
        case .manual:
            return L.accountOrderingModeManualHint
        }
    }
}

private extension CodexBarActivationScopeMode {
    var title: String {
        switch self {
        case .global:
            return L.accountActivationScopeGlobal
        case .specificPaths:
            return L.accountActivationScopeSpecificPaths
        case .globalAndSpecificPaths:
            return L.accountActivationScopeGlobalAndSpecificPaths
        }
    }

    var detail: String {
        switch self {
        case .global:
            return L.accountActivationScopeGlobalHint
        case .specificPaths:
            return L.accountActivationScopeSpecificPathsHint
        case .globalAndSpecificPaths:
            return L.accountActivationScopeGlobalAndSpecificPathsHint
        }
    }
}
