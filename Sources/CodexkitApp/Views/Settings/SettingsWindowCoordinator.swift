import Combine
import Foundation

@MainActor
protocol SettingsSaveRequestApplying {
    func applySettingsSaveRequests(_ requests: SettingsSaveRequests) throws
}

extension TokenStore: SettingsSaveRequestApplying {
    @MainActor
    func applySettingsSaveRequests(_ requests: SettingsSaveRequests) throws {
        try self.saveSettings(requests)
    }
}

enum SettingsPage: String, CaseIterable, Identifiable {
    case accounts
    case general
    case usage
    case provider
    case apiService
    case apiServiceDashboard
    case apiServiceLogs
    case updates

    var id: String { self.rawValue }
}

struct SettingsWindowDraft: Equatable {
    var accountOrder: [String]
    var accountOrderingMode: CodexBarOpenAIAccountOrderingMode
    var manualActivationBehavior: CodexBarOpenAIManualActivationBehavior
    var serviceTier: CodexBarServiceTier
    var usageDisplayMode: CodexBarUsageDisplayMode
    var menuBarQuotaVisibility: CodexBarMenuBarQuotaVisibility
    var menuBarAPIServiceStatusVisibility: CodexBarMenuBarAPIServiceStatusVisibility
    var plusRelativeWeight: Double
    var proRelativeToPlusMultiplier: Double
    var teamRelativeToPlusMultiplier: Double
    var preferredCodexAppPath: String?
    var accountActivationScopeMode: CodexBarActivationScopeMode
    var accountActivationRootPaths: [String]
    var cliProxyAPIEnabled: Bool
    var cliProxyAPIHost: String
    var cliProxyAPIPort: Int
    var cliProxyAPIManagementSecretKey: String
    var cliProxyAPIClientAPIKey: String
    var cliProxyAPIMemberAccountIDs: [String]
    var cliProxyAPIRestrictFreeAccounts: Bool
    var cliProxyAPIRoutingStrategy: CLIProxyAPIRoutingStrategy
    var cliProxyAPISwitchProjectOnQuotaExceeded: Bool
    var cliProxyAPISwitchPreviewModelOnQuotaExceeded: Bool
    var cliProxyAPIRequestRetry: Int
    var cliProxyAPIMaxRetryInterval: Int
    var cliProxyAPIDisableCooling: Bool
    var cliProxyAPIMemberPrioritiesByAccountID: [String: Int]
    var codexkitAutomaticallyChecksForUpdates: Bool
    var codexkitAutomaticallyInstallsUpdates: Bool
    var codexkitUpdateCheckSchedule: CodexBarUpdateCheckSchedule
    var cliProxyAPIAutomaticallyChecksForUpdates: Bool
    var cliProxyAPIAutomaticallyInstallsUpdates: Bool
    var cliProxyAPIUpdateCheckSchedule: CodexBarUpdateCheckSchedule

    init(
        config: CodexBarConfig,
        accounts: [TokenAccount],
        probeService: CLIProxyAPIProbeService = .shared
    ) {
        self.accountOrder = Self.normalizedAccountOrder(
            config.openAI.accountOrder,
            availableAccountIDs: accounts.map(\.accountId)
        )
        self.accountOrderingMode = config.openAI.accountOrderingMode
        self.manualActivationBehavior = config.openAI.manualActivationBehavior
        self.serviceTier = config.global.serviceTier ?? .standard
        self.usageDisplayMode = config.openAI.usageDisplayMode
        self.menuBarQuotaVisibility = config.openAI.menuBarDisplay.quotaVisibility
        self.menuBarAPIServiceStatusVisibility = config.openAI.menuBarDisplay.apiServiceStatusVisibility
        self.plusRelativeWeight = config.openAI.quotaSort.plusRelativeWeight
        self.proRelativeToPlusMultiplier = config.openAI.quotaSort.proRelativeToPlusMultiplier
        self.teamRelativeToPlusMultiplier = config.openAI.quotaSort.teamRelativeToPlusMultiplier
        self.preferredCodexAppPath = config.desktop.preferredCodexAppPath
        self.accountActivationScopeMode = config.desktop.accountActivationScope.mode
        self.accountActivationRootPaths = config.desktop.accountActivationScope.rootPaths
        let cliProxyDefaults = probeService.suggestedDraftValues(existingSettings: config.desktop.cliProxyAPI)
        self.cliProxyAPIEnabled = config.desktop.cliProxyAPI.enabled
        self.cliProxyAPIHost = cliProxyDefaults.host
        self.cliProxyAPIPort = cliProxyDefaults.port
        self.cliProxyAPIManagementSecretKey = cliProxyDefaults.managementSecretKey
        self.cliProxyAPIClientAPIKey = cliProxyDefaults.clientAPIKey
        self.cliProxyAPIMemberAccountIDs = config.desktop.cliProxyAPI.memberAccountIDs
        self.cliProxyAPIRestrictFreeAccounts = config.desktop.cliProxyAPI.restrictFreeAccounts
        self.cliProxyAPIRoutingStrategy = cliProxyDefaults.routingStrategy
        self.cliProxyAPISwitchProjectOnQuotaExceeded = cliProxyDefaults.switchProjectOnQuotaExceeded
        self.cliProxyAPISwitchPreviewModelOnQuotaExceeded = cliProxyDefaults.switchPreviewModelOnQuotaExceeded
        self.cliProxyAPIRequestRetry = cliProxyDefaults.requestRetry
        self.cliProxyAPIMaxRetryInterval = cliProxyDefaults.maxRetryInterval
        self.cliProxyAPIDisableCooling = cliProxyDefaults.disableCooling
        self.cliProxyAPIMemberPrioritiesByAccountID = config.desktop.cliProxyAPI.memberPrioritiesByAccountID
        self.codexkitAutomaticallyChecksForUpdates = config.desktop.codexkitUpdate.automaticallyChecksForUpdates
        self.codexkitAutomaticallyInstallsUpdates = config.desktop.codexkitUpdate.automaticallyInstallsUpdates
        self.codexkitUpdateCheckSchedule = config.desktop.codexkitUpdate.checkSchedule
        self.cliProxyAPIAutomaticallyChecksForUpdates = config.desktop.cliProxyAPIUpdate.automaticallyChecksForUpdates
        self.cliProxyAPIAutomaticallyInstallsUpdates = config.desktop.cliProxyAPIUpdate.automaticallyInstallsUpdates
        self.cliProxyAPIUpdateCheckSchedule = config.desktop.cliProxyAPIUpdate.checkSchedule
    }

    static func mergedAccountOrder(
        preferredAccountOrder: [String],
        fallbackAccountOrder: [String],
        availableAccountIDs: [String]
    ) -> [String] {
        self.normalizedAccountOrder(
            preferredAccountOrder + fallbackAccountOrder,
            availableAccountIDs: availableAccountIDs
        )
    }

    private static func normalizedAccountOrder(_ accountOrder: [String], availableAccountIDs: [String]) -> [String] {
        let availableSet = Set(availableAccountIDs)
        var normalized: [String] = []
        var seen: Set<String> = []

        for accountID in accountOrder where availableSet.contains(accountID) {
            guard seen.insert(accountID).inserted else { continue }
            normalized.append(accountID)
        }

        for accountID in availableAccountIDs where seen.insert(accountID).inserted {
            normalized.append(accountID)
        }

        return normalized
    }
}

struct SettingsOpenAIAccountOrderItem: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
}

enum SettingsDirtyField: Hashable {
    case accountOrder
    case accountOrderingMode
    case manualActivationBehavior
    case serviceTier
    case usageDisplayMode
    case menuBarQuotaVisibility
    case menuBarAPIServiceStatusVisibility
    case plusRelativeWeight
    case proRelativeToPlusMultiplier
    case teamRelativeToPlusMultiplier
    case preferredCodexAppPath
    case accountActivationScopeMode
    case accountActivationRootPaths
    case cliProxyAPIEnabled
    case cliProxyAPIHost
    case cliProxyAPIPort
    case cliProxyAPIManagementSecretKey
    case cliProxyAPIClientAPIKey
    case cliProxyAPIMemberAccountIDs
    case cliProxyAPIRestrictFreeAccounts
    case cliProxyAPIRoutingStrategy
    case cliProxyAPISwitchProjectOnQuotaExceeded
    case cliProxyAPISwitchPreviewModelOnQuotaExceeded
    case cliProxyAPIRequestRetry
    case cliProxyAPIMaxRetryInterval
    case cliProxyAPIDisableCooling
    case cliProxyAPIMemberPrioritiesByAccountID
    case codexkitAutomaticallyChecksForUpdates
    case codexkitAutomaticallyInstallsUpdates
    case codexkitUpdateCheckSchedule
    case cliProxyAPIAutomaticallyChecksForUpdates
    case cliProxyAPIAutomaticallyInstallsUpdates
    case cliProxyAPIUpdateCheckSchedule
}

enum SettingsPendingAction: Equatable {
    case selectPage(SettingsPage)
    case close
}

@MainActor
final class SettingsWindowCoordinator: ObservableObject {
    @Published var selectedPage: SettingsPage
    @Published var draft: SettingsWindowDraft
    @Published var validationMessage: String?
    @Published var pendingAction: SettingsPendingAction?

    private var accounts: [TokenAccount]
    private var baseline: SettingsWindowDraft
    private var dirtyFields: Set<SettingsDirtyField> = []
    private let probeService: CLIProxyAPIProbeService

    init(
        config: CodexBarConfig,
        accounts: [TokenAccount],
        selectedPage: SettingsPage = .accounts,
        probeService: CLIProxyAPIProbeService = .shared
    ) {
        let draft = SettingsWindowDraft(config: config, accounts: accounts, probeService: probeService)
        self.selectedPage = selectedPage
        self.draft = draft
        self.accounts = accounts
        self.baseline = draft
        self.probeService = probeService
        self.validationMessage = nil
        self.pendingAction = nil
    }

    var hasChanges: Bool {
        self.makeSaveRequests().isEmpty == false
    }

    var hasCurrentPageChanges: Bool {
        self.hasChanges(on: self.selectedPage)
    }

    var orderedAccounts: [SettingsOpenAIAccountOrderItem] {
        let accountByID = Dictionary(uniqueKeysWithValues: self.accounts.map { ($0.accountId, $0) })
        return self.draft.accountOrder.compactMap { accountID in
            guard let account = accountByID[accountID] else { return nil }
            return SettingsOpenAIAccountOrderItem(
                id: accountID,
                title: Self.accountTitle(for: account),
                detail: Self.accountDetail(for: account)
            )
        }
    }

    var showsManualAccountOrderSection: Bool {
        self.draft.accountOrderingMode == .manual
    }

    var showsManualActivationBehaviorSection: Bool {
        true
    }

    var showsCodexAppPathSection: Bool {
        self.showsManualActivationBehaviorSection &&
        self.draft.manualActivationBehavior == .launchNewInstance
    }

    var showsAccountActivationPathsSection: Bool {
        self.draft.accountActivationScopeMode != .global
    }

    func moveAccount(accountID: String, offset: Int) {
        guard let currentIndex = self.draft.accountOrder.firstIndex(of: accountID) else { return }
        let targetIndex = currentIndex + offset
        guard self.draft.accountOrder.indices.contains(targetIndex) else { return }
        self.draft.accountOrder.swapAt(currentIndex, targetIndex)
        self.dirtyFields.insert(.accountOrder)
    }

    func setAccountOrder(_ accountOrder: [String]) {
        self.draft.accountOrder = accountOrder
        self.dirtyFields.insert(.accountOrder)
    }

    func update<Value>(
        _ keyPath: WritableKeyPath<SettingsWindowDraft, Value>,
        to value: Value,
        field: SettingsDirtyField
    ) {
        self.draft[keyPath: keyPath] = value
        self.dirtyFields.insert(field)
    }

    func requestPageSelection(_ page: SettingsPage) {
        guard page != self.selectedPage else { return }
        guard self.hasCurrentPageChanges else {
            self.selectedPage = page
            return
        }

        self.pendingAction = .selectPage(page)
    }

    func requestClose() -> Bool {
        guard self.hasCurrentPageChanges else {
            self.pendingAction = nil
            return true
        }

        self.pendingAction = .close
        return false
    }

    func saveAndClose(
        using sink: SettingsSaveRequestApplying,
        onClose: () -> Void
    ) {
        do {
            _ = try self.save(page: self.selectedPage, using: sink)
            onClose()
        } catch {
            self.validationMessage = error.localizedDescription
        }
    }

    func save(using sink: SettingsSaveRequestApplying) throws -> SettingsSaveRequests {
        let requests = self.makeSaveRequests()
        guard requests.isEmpty == false else { return requests }
        try sink.applySettingsSaveRequests(requests)
        self.baseline = self.draft
        self.dirtyFields.removeAll()
        self.validationMessage = nil
        return requests
    }

    func save(page: SettingsPage, using sink: SettingsSaveRequestApplying) throws -> SettingsSaveRequests {
        let requests = self.makeSaveRequests(for: page)
        guard requests.isEmpty == false else {
            self.validationMessage = nil
            return requests
        }

        try sink.applySettingsSaveRequests(requests)
        self.syncBaseline(to: self.draft, fields: Self.fields(for: page))
        self.dirtyFields.subtract(Self.fields(for: page))
        self.validationMessage = nil
        return requests
    }

    func cancelAndClose(onClose: () -> Void) {
        self.cancel()
        onClose()
    }

    func cancel() {
        self.draft = self.baseline
        self.dirtyFields.removeAll()
        self.validationMessage = nil
        self.pendingAction = nil
    }

    func discardChanges(on page: SettingsPage) {
        self.syncDraft(to: self.baseline, fields: Self.fields(for: page))
        self.dirtyFields.subtract(Self.fields(for: page))
        self.validationMessage = nil
    }

    func commitChanges(on page: SettingsPage) {
        self.commitChanges(fields: Self.fields(for: page))
    }

    func revertDraftField(_ field: SettingsDirtyField) {
        self.syncDraft(to: self.baseline, fields: [field])
        self.dirtyFields.remove(field)
    }

    func makeAPIServiceActionRequest(clientAPIKey: String?, enabled: Bool) -> CLIProxyAPISettingsUpdate {
        let draftClientAPIKey = self.draft.cliProxyAPIClientAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return CLIProxyAPISettingsUpdate(
            enabled: enabled,
            host: self.draft.cliProxyAPIHost,
            port: self.draft.cliProxyAPIPort,
            repositoryRootPath: nil,
            managementSecretKey: self.draft.cliProxyAPIManagementSecretKey,
            clientAPIKey: draftClientAPIKey.isEmpty ? clientAPIKey : draftClientAPIKey,
            memberAccountIDs: self.draft.cliProxyAPIMemberAccountIDs,
            restrictFreeAccounts: self.draft.cliProxyAPIRestrictFreeAccounts,
            routingStrategy: self.draft.cliProxyAPIRoutingStrategy,
            switchProjectOnQuotaExceeded: self.draft.cliProxyAPISwitchProjectOnQuotaExceeded,
            switchPreviewModelOnQuotaExceeded: self.draft.cliProxyAPISwitchPreviewModelOnQuotaExceeded,
            requestRetry: self.draft.cliProxyAPIRequestRetry,
            maxRetryInterval: self.draft.cliProxyAPIMaxRetryInterval,
            disableCooling: self.draft.cliProxyAPIDisableCooling,
            memberPrioritiesByAccountID: self.draft.cliProxyAPIMemberPrioritiesByAccountID
        )
    }

    func makeAPIServiceRuntimeActionRequest(clientAPIKey: String?, persistedEnabled: Bool) -> CLIProxyAPISettingsUpdate {
        self.makeAPIServiceActionRequest(clientAPIKey: clientAPIKey, enabled: persistedEnabled)
    }

    func apiServiceRoutingEnablePreflightMessage(runtimeState: CLIProxyAPIServiceState) -> String? {
        if self.draft.cliProxyAPIMemberAccountIDs.isEmpty {
            return L.menuAPIServiceSetupRequiredMessage
        }
        if runtimeState.status != .running {
            return L.menuAPIServiceStartRequiredMessage
        }
        return nil
    }

    func completeAPIServiceAction() {
        self.commitChanges(on: .apiService)
    }

    func completeAPIServiceRuntimeStartAction() {
        self.commitChanges(fields: Self.apiServiceRuntimeActionFields)
    }

    func failAPIServiceAction(_ message: String) {
        self.validationMessage = message
    }

    func rollbackAPIServiceEnabledAction(_ message: String) {
        self.revertDraftField(.cliProxyAPIEnabled)
        self.validationMessage = message
    }

    func confirmPendingActionSave(
        using sink: SettingsSaveRequestApplying,
        onClose: () -> Void
    ) {
        guard let action = self.pendingAction else { return }

        do {
            _ = try self.save(page: self.selectedPage, using: sink)
            self.pendingAction = nil
            self.perform(action, onClose: onClose)
        } catch {
            self.validationMessage = error.localizedDescription
        }
    }

    func confirmPendingActionDiscard(onClose: () -> Void) {
        guard let action = self.pendingAction else { return }

        self.discardChanges(on: self.selectedPage)
        self.pendingAction = nil
        self.perform(action, onClose: onClose)
    }

    func cancelPendingAction() {
        self.pendingAction = nil
    }

    func reconcileExternalState(config: CodexBarConfig, accounts: [TokenAccount]) {
        let externalDraft = SettingsWindowDraft(config: config, accounts: accounts, probeService: self.probeService)
        self.accounts = accounts

        if self.dirtyFields.contains(.accountOrder) == false {
            self.draft.accountOrder = externalDraft.accountOrder
        } else {
            self.draft.accountOrder = SettingsWindowDraft.mergedAccountOrder(
                preferredAccountOrder: self.draft.accountOrder,
                fallbackAccountOrder: externalDraft.accountOrder,
                availableAccountIDs: accounts.map(\.accountId)
            )
        }
        self.baseline.accountOrder = externalDraft.accountOrder

        self.reconcile(\.accountOrderingMode, externalValue: externalDraft.accountOrderingMode, field: .accountOrderingMode)
        self.reconcile(\.manualActivationBehavior, externalValue: externalDraft.manualActivationBehavior, field: .manualActivationBehavior)
        self.reconcile(\.serviceTier, externalValue: externalDraft.serviceTier, field: .serviceTier)
        self.reconcile(\.usageDisplayMode, externalValue: externalDraft.usageDisplayMode, field: .usageDisplayMode)
        self.reconcile(\.menuBarQuotaVisibility, externalValue: externalDraft.menuBarQuotaVisibility, field: .menuBarQuotaVisibility)
        self.reconcile(\.menuBarAPIServiceStatusVisibility, externalValue: externalDraft.menuBarAPIServiceStatusVisibility, field: .menuBarAPIServiceStatusVisibility)
        self.reconcile(\.plusRelativeWeight, externalValue: externalDraft.plusRelativeWeight, field: .plusRelativeWeight)
        self.reconcile(\.proRelativeToPlusMultiplier, externalValue: externalDraft.proRelativeToPlusMultiplier, field: .proRelativeToPlusMultiplier)
        self.reconcile(\.teamRelativeToPlusMultiplier, externalValue: externalDraft.teamRelativeToPlusMultiplier, field: .teamRelativeToPlusMultiplier)
        self.reconcile(\.preferredCodexAppPath, externalValue: externalDraft.preferredCodexAppPath, field: .preferredCodexAppPath)
        self.reconcile(\.accountActivationScopeMode, externalValue: externalDraft.accountActivationScopeMode, field: .accountActivationScopeMode)
        self.reconcile(\.accountActivationRootPaths, externalValue: externalDraft.accountActivationRootPaths, field: .accountActivationRootPaths)
        self.reconcile(\.cliProxyAPIEnabled, externalValue: externalDraft.cliProxyAPIEnabled, field: .cliProxyAPIEnabled)
        self.reconcile(\.cliProxyAPIHost, externalValue: externalDraft.cliProxyAPIHost, field: .cliProxyAPIHost)
        self.reconcile(\.cliProxyAPIPort, externalValue: externalDraft.cliProxyAPIPort, field: .cliProxyAPIPort)
        self.reconcile(\.cliProxyAPIManagementSecretKey, externalValue: externalDraft.cliProxyAPIManagementSecretKey, field: .cliProxyAPIManagementSecretKey)
        self.reconcile(\.cliProxyAPIClientAPIKey, externalValue: externalDraft.cliProxyAPIClientAPIKey, field: .cliProxyAPIClientAPIKey)
        self.reconcile(\.cliProxyAPIMemberAccountIDs, externalValue: externalDraft.cliProxyAPIMemberAccountIDs, field: .cliProxyAPIMemberAccountIDs)
        self.reconcile(\.cliProxyAPIRestrictFreeAccounts, externalValue: externalDraft.cliProxyAPIRestrictFreeAccounts, field: .cliProxyAPIRestrictFreeAccounts)
        self.reconcile(\.cliProxyAPIRoutingStrategy, externalValue: externalDraft.cliProxyAPIRoutingStrategy, field: .cliProxyAPIRoutingStrategy)
        self.reconcile(\.cliProxyAPISwitchProjectOnQuotaExceeded, externalValue: externalDraft.cliProxyAPISwitchProjectOnQuotaExceeded, field: .cliProxyAPISwitchProjectOnQuotaExceeded)
        self.reconcile(\.cliProxyAPISwitchPreviewModelOnQuotaExceeded, externalValue: externalDraft.cliProxyAPISwitchPreviewModelOnQuotaExceeded, field: .cliProxyAPISwitchPreviewModelOnQuotaExceeded)
        self.reconcile(\.cliProxyAPIRequestRetry, externalValue: externalDraft.cliProxyAPIRequestRetry, field: .cliProxyAPIRequestRetry)
        self.reconcile(\.cliProxyAPIMaxRetryInterval, externalValue: externalDraft.cliProxyAPIMaxRetryInterval, field: .cliProxyAPIMaxRetryInterval)
        self.reconcile(\.cliProxyAPIDisableCooling, externalValue: externalDraft.cliProxyAPIDisableCooling, field: .cliProxyAPIDisableCooling)
        self.reconcile(\.cliProxyAPIMemberPrioritiesByAccountID, externalValue: externalDraft.cliProxyAPIMemberPrioritiesByAccountID, field: .cliProxyAPIMemberPrioritiesByAccountID)
        self.reconcile(\.codexkitAutomaticallyChecksForUpdates, externalValue: externalDraft.codexkitAutomaticallyChecksForUpdates, field: .codexkitAutomaticallyChecksForUpdates)
        self.reconcile(\.codexkitAutomaticallyInstallsUpdates, externalValue: externalDraft.codexkitAutomaticallyInstallsUpdates, field: .codexkitAutomaticallyInstallsUpdates)
        self.reconcile(\.codexkitUpdateCheckSchedule, externalValue: externalDraft.codexkitUpdateCheckSchedule, field: .codexkitUpdateCheckSchedule)
        self.reconcile(\.cliProxyAPIAutomaticallyChecksForUpdates, externalValue: externalDraft.cliProxyAPIAutomaticallyChecksForUpdates, field: .cliProxyAPIAutomaticallyChecksForUpdates)
        self.reconcile(\.cliProxyAPIAutomaticallyInstallsUpdates, externalValue: externalDraft.cliProxyAPIAutomaticallyInstallsUpdates, field: .cliProxyAPIAutomaticallyInstallsUpdates)
        self.reconcile(\.cliProxyAPIUpdateCheckSchedule, externalValue: externalDraft.cliProxyAPIUpdateCheckSchedule, field: .cliProxyAPIUpdateCheckSchedule)
    }

    func makeSaveRequests() -> SettingsSaveRequests {
        var requests = self.makeSaveRequests(for: .accounts)
        Self.merge(self.makeSaveRequests(for: .general), into: &requests)
        Self.merge(self.makeSaveRequests(for: .usage), into: &requests)
        Self.merge(self.makeSaveRequests(for: .provider), into: &requests)
        Self.merge(self.makeSaveRequests(for: .apiService), into: &requests)
        Self.merge(self.makeSaveRequests(for: .apiServiceDashboard), into: &requests)
        Self.merge(self.makeSaveRequests(for: .apiServiceLogs), into: &requests)
        Self.merge(self.makeSaveRequests(for: .updates), into: &requests)
        return requests
    }

    func hasChanges(on page: SettingsPage) -> Bool {
        self.makeSaveRequests(for: page).isEmpty == false
    }

    func makeSaveRequests(for page: SettingsPage) -> SettingsSaveRequests {
        var requests = SettingsSaveRequests()

        if page == .accounts,
           self.draft.accountOrder != self.baseline.accountOrder ||
            self.draft.accountOrderingMode != self.baseline.accountOrderingMode ||
            self.draft.manualActivationBehavior != self.baseline.manualActivationBehavior ||
            self.draft.serviceTier != self.baseline.serviceTier {
            requests.openAIAccount = OpenAIAccountSettingsUpdate(
                accountOrder: self.draft.accountOrder,
                accountOrderingMode: self.draft.accountOrderingMode,
                manualActivationBehavior: self.draft.manualActivationBehavior,
                serviceTier: self.draft.serviceTier != self.baseline.serviceTier ? self.draft.serviceTier : nil
            )
        }

        if page == .accounts,
           self.draft.preferredCodexAppPath != self.baseline.preferredCodexAppPath ||
            self.draft.accountActivationScopeMode != self.baseline.accountActivationScopeMode ||
            self.draft.accountActivationRootPaths != self.baseline.accountActivationRootPaths {
            let normalizedScope = CodexBarDesktopSettings.AccountActivationScope(
                mode: self.draft.accountActivationScopeMode,
                rootPaths: self.draft.accountActivationRootPaths
            )
            requests.desktop = DesktopSettingsUpdate(
                preferredCodexAppPath: self.draft.preferredCodexAppPath,
                accountActivationScopeMode: normalizedScope.mode,
                accountActivationRootPaths: normalizedScope.rootPaths
            )
        }

        if page == .general,
           self.draft.menuBarQuotaVisibility != self.baseline.menuBarQuotaVisibility ||
            self.draft.menuBarAPIServiceStatusVisibility != self.baseline.menuBarAPIServiceStatusVisibility {
            requests.openAIGeneral = OpenAIGeneralSettingsUpdate(
                menuBarQuotaVisibility: self.draft.menuBarQuotaVisibility,
                menuBarAPIServiceStatusVisibility: self.draft.menuBarAPIServiceStatusVisibility
            )
        }

        if page == .usage,
           self.draft.usageDisplayMode != self.baseline.usageDisplayMode ||
            self.draft.plusRelativeWeight != self.baseline.plusRelativeWeight ||
            self.draft.proRelativeToPlusMultiplier != self.baseline.proRelativeToPlusMultiplier ||
            self.draft.teamRelativeToPlusMultiplier != self.baseline.teamRelativeToPlusMultiplier {
            requests.openAIUsage = OpenAIUsageSettingsUpdate(
                usageDisplayMode: self.draft.usageDisplayMode,
                plusRelativeWeight: self.draft.plusRelativeWeight,
                proRelativeToPlusMultiplier: self.draft.proRelativeToPlusMultiplier,
                teamRelativeToPlusMultiplier: self.draft.teamRelativeToPlusMultiplier
            )
        }

        if page == .apiService,
           self.draft.cliProxyAPIEnabled != self.baseline.cliProxyAPIEnabled ||
            self.draft.cliProxyAPIHost != self.baseline.cliProxyAPIHost ||
           self.draft.cliProxyAPIPort != self.baseline.cliProxyAPIPort ||
            self.draft.cliProxyAPIManagementSecretKey != self.baseline.cliProxyAPIManagementSecretKey ||
            self.draft.cliProxyAPIClientAPIKey != self.baseline.cliProxyAPIClientAPIKey ||
            self.draft.cliProxyAPIMemberAccountIDs != self.baseline.cliProxyAPIMemberAccountIDs ||
            self.draft.cliProxyAPIRestrictFreeAccounts != self.baseline.cliProxyAPIRestrictFreeAccounts ||
            self.draft.cliProxyAPIRoutingStrategy != self.baseline.cliProxyAPIRoutingStrategy ||
            self.draft.cliProxyAPISwitchProjectOnQuotaExceeded != self.baseline.cliProxyAPISwitchProjectOnQuotaExceeded ||
            self.draft.cliProxyAPISwitchPreviewModelOnQuotaExceeded != self.baseline.cliProxyAPISwitchPreviewModelOnQuotaExceeded ||
            self.draft.cliProxyAPIRequestRetry != self.baseline.cliProxyAPIRequestRetry ||
            self.draft.cliProxyAPIMaxRetryInterval != self.baseline.cliProxyAPIMaxRetryInterval ||
            self.draft.cliProxyAPIDisableCooling != self.baseline.cliProxyAPIDisableCooling ||
            self.draft.cliProxyAPIMemberPrioritiesByAccountID != self.baseline.cliProxyAPIMemberPrioritiesByAccountID {
            requests.cliProxyAPI = CLIProxyAPISettingsUpdate(
                enabled: self.draft.cliProxyAPIEnabled,
                host: self.draft.cliProxyAPIHost,
                port: self.draft.cliProxyAPIPort,
                repositoryRootPath: nil,
                managementSecretKey: self.draft.cliProxyAPIManagementSecretKey,
                clientAPIKey: self.draft.cliProxyAPIClientAPIKey,
                memberAccountIDs: self.sanitizedCLIProxyAPIMemberAccountIDs(),
                restrictFreeAccounts: self.draft.cliProxyAPIRestrictFreeAccounts,
                routingStrategy: self.draft.cliProxyAPIRoutingStrategy,
                switchProjectOnQuotaExceeded: self.draft.cliProxyAPISwitchProjectOnQuotaExceeded,
                switchPreviewModelOnQuotaExceeded: self.draft.cliProxyAPISwitchPreviewModelOnQuotaExceeded,
                requestRetry: self.draft.cliProxyAPIRequestRetry,
                maxRetryInterval: self.draft.cliProxyAPIMaxRetryInterval,
                disableCooling: self.draft.cliProxyAPIDisableCooling,
                memberPrioritiesByAccountID: self.draft.cliProxyAPIMemberPrioritiesByAccountID
            )
        }

        if page == .updates,
           self.draft.codexkitAutomaticallyChecksForUpdates != self.baseline.codexkitAutomaticallyChecksForUpdates ||
            self.draft.codexkitAutomaticallyInstallsUpdates != self.baseline.codexkitAutomaticallyInstallsUpdates ||
            self.draft.codexkitUpdateCheckSchedule != self.baseline.codexkitUpdateCheckSchedule ||
            self.draft.cliProxyAPIAutomaticallyChecksForUpdates != self.baseline.cliProxyAPIAutomaticallyChecksForUpdates ||
            self.draft.cliProxyAPIAutomaticallyInstallsUpdates != self.baseline.cliProxyAPIAutomaticallyInstallsUpdates ||
            self.draft.cliProxyAPIUpdateCheckSchedule != self.baseline.cliProxyAPIUpdateCheckSchedule {
            requests.desktop = DesktopSettingsUpdate(
                preferredCodexAppPath: nil,
                accountActivationScopeMode: nil,
                accountActivationRootPaths: nil,
                codexkitUpdate: .init(
                    automaticallyChecksForUpdates: self.draft.codexkitAutomaticallyChecksForUpdates,
                    automaticallyInstallsUpdates: self.draft.codexkitAutomaticallyInstallsUpdates,
                    checkSchedule: self.draft.codexkitUpdateCheckSchedule
                ),
                cliProxyAPIUpdate: .init(
                    automaticallyChecksForUpdates: self.draft.cliProxyAPIAutomaticallyChecksForUpdates,
                    automaticallyInstallsUpdates: self.draft.cliProxyAPIAutomaticallyInstallsUpdates,
                    checkSchedule: self.draft.cliProxyAPIUpdateCheckSchedule
                )
            )
        }

        return requests
    }

    private static func accountTitle(for account: TokenAccount) -> String {
        if let organizationName = account.organizationName?.trimmingCharacters(in: .whitespacesAndNewlines),
           organizationName.isEmpty == false {
            return organizationName
        }
        if account.email.isEmpty == false {
            return account.email
        }
        return account.accountId
    }

    private static func accountDetail(for account: TokenAccount) -> String {
        if let organizationName = account.organizationName?.trimmingCharacters(in: .whitespacesAndNewlines),
           organizationName.isEmpty == false,
           account.email.isEmpty == false {
            return account.email
        }
        return account.accountId
    }

    private func reconcile<Value: Equatable>(
        _ keyPath: WritableKeyPath<SettingsWindowDraft, Value>,
        externalValue: Value,
        field: SettingsDirtyField
    ) {
        if self.dirtyFields.contains(field) == false {
            self.draft[keyPath: keyPath] = externalValue
        }
        self.baseline[keyPath: keyPath] = externalValue
    }

    private func sanitizedCLIProxyAPIMemberAccountIDs() -> [String] {
        let accountByID = Dictionary(uniqueKeysWithValues: self.accounts.map { ($0.accountId, $0) })
        let selectedIDs = self.draft.cliProxyAPIMemberAccountIDs.filter { accountByID[$0] != nil }
        guard self.draft.cliProxyAPIRestrictFreeAccounts else {
            return Array(Set(selectedIDs)).sorted()
        }

        return Array(
            Set(
                selectedIDs.filter { accountID in
                    guard let account = accountByID[accountID] else { return false }
                    return account.isExplicitFreePlanType == false
                }
            )
        ).sorted()
    }

    private static func fields(for page: SettingsPage) -> Set<SettingsDirtyField> {
        switch page {
        case .accounts:
            return [
                .accountOrder,
                .accountOrderingMode,
                .manualActivationBehavior,
                .serviceTier,
                .preferredCodexAppPath,
                .accountActivationScopeMode,
                .accountActivationRootPaths,
            ]
        case .general:
            return [
                .menuBarQuotaVisibility,
                .menuBarAPIServiceStatusVisibility,
            ]
        case .usage:
            return [
                .usageDisplayMode,
                .plusRelativeWeight,
                .proRelativeToPlusMultiplier,
                .teamRelativeToPlusMultiplier,
            ]
        case .provider:
            return []
        case .apiService:
            return [
                .cliProxyAPIEnabled,
                .cliProxyAPIHost,
                .cliProxyAPIPort,
                .cliProxyAPIManagementSecretKey,
                .cliProxyAPIClientAPIKey,
                .cliProxyAPIMemberAccountIDs,
                .cliProxyAPIRestrictFreeAccounts,
                .cliProxyAPIRoutingStrategy,
                .cliProxyAPISwitchProjectOnQuotaExceeded,
                .cliProxyAPISwitchPreviewModelOnQuotaExceeded,
                .cliProxyAPIRequestRetry,
                .cliProxyAPIMaxRetryInterval,
                .cliProxyAPIDisableCooling,
                .cliProxyAPIMemberPrioritiesByAccountID,
            ]
        case .apiServiceDashboard, .apiServiceLogs:
            return []
        case .updates:
            return [
                .codexkitAutomaticallyChecksForUpdates,
                .codexkitAutomaticallyInstallsUpdates,
                .codexkitUpdateCheckSchedule,
                .cliProxyAPIAutomaticallyChecksForUpdates,
                .cliProxyAPIAutomaticallyInstallsUpdates,
                .cliProxyAPIUpdateCheckSchedule,
            ]
        }
    }

    private static var apiServiceRuntimeActionFields: Set<SettingsDirtyField> {
        Self.fields(for: .apiService).subtracting([.cliProxyAPIEnabled])
    }

    private func commitChanges(fields: Set<SettingsDirtyField>) {
        self.syncBaseline(to: self.draft, fields: fields)
        self.dirtyFields.subtract(fields)
        self.validationMessage = nil
    }

    private static func merge(_ source: SettingsSaveRequests, into destination: inout SettingsSaveRequests) {
        if let sourceAccount = source.openAIAccount {
            if let existingAccount = destination.openAIAccount {
                destination.openAIAccount = OpenAIAccountSettingsUpdate(
                    accountOrder: existingAccount.accountOrder ?? sourceAccount.accountOrder,
                    accountOrderingMode: existingAccount.accountOrderingMode ?? sourceAccount.accountOrderingMode,
                    manualActivationBehavior: existingAccount.manualActivationBehavior ?? sourceAccount.manualActivationBehavior,
                    serviceTier: existingAccount.serviceTier ?? sourceAccount.serviceTier
                )
            } else {
                destination.openAIAccount = sourceAccount
            }
        }
        destination.openAIUsage = destination.openAIUsage ?? source.openAIUsage
        destination.openAIGeneral = destination.openAIGeneral ?? source.openAIGeneral
        if let sourceDesktop = source.desktop {
            if let existingDesktop = destination.desktop {
                destination.desktop = DesktopSettingsUpdate(
                    preferredCodexAppPath: existingDesktop.preferredCodexAppPath ?? sourceDesktop.preferredCodexAppPath,
                    accountActivationScopeMode: existingDesktop.accountActivationScopeMode ?? sourceDesktop.accountActivationScopeMode,
                    accountActivationRootPaths: existingDesktop.accountActivationRootPaths ?? sourceDesktop.accountActivationRootPaths,
                    codexkitUpdate: existingDesktop.codexkitUpdate ?? sourceDesktop.codexkitUpdate,
                    cliProxyAPIUpdate: existingDesktop.cliProxyAPIUpdate ?? sourceDesktop.cliProxyAPIUpdate
                )
            } else {
                destination.desktop = sourceDesktop
            }
        }
        destination.cliProxyAPI = destination.cliProxyAPI ?? source.cliProxyAPI
    }

    private func perform(_ action: SettingsPendingAction, onClose: () -> Void) {
        switch action {
        case let .selectPage(page):
            self.selectedPage = page
        case .close:
            onClose()
        }
    }

    private func syncBaseline(to source: SettingsWindowDraft, fields: Set<SettingsDirtyField>) {
        if fields.contains(.accountOrder) {
            self.baseline.accountOrder = source.accountOrder
        }
        if fields.contains(.accountOrderingMode) {
            self.baseline.accountOrderingMode = source.accountOrderingMode
        }
        if fields.contains(.manualActivationBehavior) {
            self.baseline.manualActivationBehavior = source.manualActivationBehavior
        }
        if fields.contains(.serviceTier) {
            self.baseline.serviceTier = source.serviceTier
        }
        if fields.contains(.usageDisplayMode) {
            self.baseline.usageDisplayMode = source.usageDisplayMode
        }
        if fields.contains(.menuBarQuotaVisibility) {
            self.baseline.menuBarQuotaVisibility = source.menuBarQuotaVisibility
        }
        if fields.contains(.menuBarAPIServiceStatusVisibility) {
            self.baseline.menuBarAPIServiceStatusVisibility = source.menuBarAPIServiceStatusVisibility
        }
        if fields.contains(.plusRelativeWeight) {
            self.baseline.plusRelativeWeight = source.plusRelativeWeight
        }
        if fields.contains(.proRelativeToPlusMultiplier) {
            self.baseline.proRelativeToPlusMultiplier = source.proRelativeToPlusMultiplier
        }
        if fields.contains(.teamRelativeToPlusMultiplier) {
            self.baseline.teamRelativeToPlusMultiplier = source.teamRelativeToPlusMultiplier
        }
        if fields.contains(.preferredCodexAppPath) {
            self.baseline.preferredCodexAppPath = source.preferredCodexAppPath
        }
        if fields.contains(.accountActivationScopeMode) {
            self.baseline.accountActivationScopeMode = source.accountActivationScopeMode
        }
        if fields.contains(.accountActivationRootPaths) {
            self.baseline.accountActivationRootPaths = source.accountActivationRootPaths
        }
        if fields.contains(.cliProxyAPIEnabled) {
            self.baseline.cliProxyAPIEnabled = source.cliProxyAPIEnabled
        }
        if fields.contains(.cliProxyAPIHost) {
            self.baseline.cliProxyAPIHost = source.cliProxyAPIHost
        }
        if fields.contains(.cliProxyAPIPort) {
            self.baseline.cliProxyAPIPort = source.cliProxyAPIPort
        }
        if fields.contains(.cliProxyAPIManagementSecretKey) {
            self.baseline.cliProxyAPIManagementSecretKey = source.cliProxyAPIManagementSecretKey
        }
        if fields.contains(.cliProxyAPIClientAPIKey) {
            self.baseline.cliProxyAPIClientAPIKey = source.cliProxyAPIClientAPIKey
        }
        if fields.contains(.cliProxyAPIMemberAccountIDs) {
            self.baseline.cliProxyAPIMemberAccountIDs = source.cliProxyAPIMemberAccountIDs
        }
        if fields.contains(.cliProxyAPIRestrictFreeAccounts) {
            self.baseline.cliProxyAPIRestrictFreeAccounts = source.cliProxyAPIRestrictFreeAccounts
        }
        if fields.contains(.cliProxyAPIRoutingStrategy) {
            self.baseline.cliProxyAPIRoutingStrategy = source.cliProxyAPIRoutingStrategy
        }
        if fields.contains(.cliProxyAPISwitchProjectOnQuotaExceeded) {
            self.baseline.cliProxyAPISwitchProjectOnQuotaExceeded = source.cliProxyAPISwitchProjectOnQuotaExceeded
        }
        if fields.contains(.cliProxyAPISwitchPreviewModelOnQuotaExceeded) {
            self.baseline.cliProxyAPISwitchPreviewModelOnQuotaExceeded = source.cliProxyAPISwitchPreviewModelOnQuotaExceeded
        }
        if fields.contains(.cliProxyAPIRequestRetry) {
            self.baseline.cliProxyAPIRequestRetry = source.cliProxyAPIRequestRetry
        }
        if fields.contains(.cliProxyAPIMaxRetryInterval) {
            self.baseline.cliProxyAPIMaxRetryInterval = source.cliProxyAPIMaxRetryInterval
        }
        if fields.contains(.cliProxyAPIDisableCooling) {
            self.baseline.cliProxyAPIDisableCooling = source.cliProxyAPIDisableCooling
        }
        if fields.contains(.cliProxyAPIMemberPrioritiesByAccountID) {
            self.baseline.cliProxyAPIMemberPrioritiesByAccountID = source.cliProxyAPIMemberPrioritiesByAccountID
        }
        if fields.contains(.codexkitAutomaticallyChecksForUpdates) {
            self.baseline.codexkitAutomaticallyChecksForUpdates = source.codexkitAutomaticallyChecksForUpdates
        }
        if fields.contains(.codexkitAutomaticallyInstallsUpdates) {
            self.baseline.codexkitAutomaticallyInstallsUpdates = source.codexkitAutomaticallyInstallsUpdates
        }
        if fields.contains(.codexkitUpdateCheckSchedule) {
            self.baseline.codexkitUpdateCheckSchedule = source.codexkitUpdateCheckSchedule
        }
        if fields.contains(.cliProxyAPIAutomaticallyChecksForUpdates) {
            self.baseline.cliProxyAPIAutomaticallyChecksForUpdates = source.cliProxyAPIAutomaticallyChecksForUpdates
        }
        if fields.contains(.cliProxyAPIAutomaticallyInstallsUpdates) {
            self.baseline.cliProxyAPIAutomaticallyInstallsUpdates = source.cliProxyAPIAutomaticallyInstallsUpdates
        }
        if fields.contains(.cliProxyAPIUpdateCheckSchedule) {
            self.baseline.cliProxyAPIUpdateCheckSchedule = source.cliProxyAPIUpdateCheckSchedule
        }
    }

    private func syncDraft(to source: SettingsWindowDraft, fields: Set<SettingsDirtyField>) {
        if fields.contains(.accountOrder) {
            self.draft.accountOrder = source.accountOrder
        }
        if fields.contains(.accountOrderingMode) {
            self.draft.accountOrderingMode = source.accountOrderingMode
        }
        if fields.contains(.manualActivationBehavior) {
            self.draft.manualActivationBehavior = source.manualActivationBehavior
        }
        if fields.contains(.serviceTier) {
            self.draft.serviceTier = source.serviceTier
        }
        if fields.contains(.usageDisplayMode) {
            self.draft.usageDisplayMode = source.usageDisplayMode
        }
        if fields.contains(.menuBarQuotaVisibility) {
            self.draft.menuBarQuotaVisibility = source.menuBarQuotaVisibility
        }
        if fields.contains(.menuBarAPIServiceStatusVisibility) {
            self.draft.menuBarAPIServiceStatusVisibility = source.menuBarAPIServiceStatusVisibility
        }
        if fields.contains(.plusRelativeWeight) {
            self.draft.plusRelativeWeight = source.plusRelativeWeight
        }
        if fields.contains(.proRelativeToPlusMultiplier) {
            self.draft.proRelativeToPlusMultiplier = source.proRelativeToPlusMultiplier
        }
        if fields.contains(.teamRelativeToPlusMultiplier) {
            self.draft.teamRelativeToPlusMultiplier = source.teamRelativeToPlusMultiplier
        }
        if fields.contains(.preferredCodexAppPath) {
            self.draft.preferredCodexAppPath = source.preferredCodexAppPath
        }
        if fields.contains(.accountActivationScopeMode) {
            self.draft.accountActivationScopeMode = source.accountActivationScopeMode
        }
        if fields.contains(.accountActivationRootPaths) {
            self.draft.accountActivationRootPaths = source.accountActivationRootPaths
        }
        if fields.contains(.cliProxyAPIEnabled) {
            self.draft.cliProxyAPIEnabled = source.cliProxyAPIEnabled
        }
        if fields.contains(.cliProxyAPIHost) {
            self.draft.cliProxyAPIHost = source.cliProxyAPIHost
        }
        if fields.contains(.cliProxyAPIPort) {
            self.draft.cliProxyAPIPort = source.cliProxyAPIPort
        }
        if fields.contains(.cliProxyAPIManagementSecretKey) {
            self.draft.cliProxyAPIManagementSecretKey = source.cliProxyAPIManagementSecretKey
        }
        if fields.contains(.cliProxyAPIClientAPIKey) {
            self.draft.cliProxyAPIClientAPIKey = source.cliProxyAPIClientAPIKey
        }
        if fields.contains(.cliProxyAPIMemberAccountIDs) {
            self.draft.cliProxyAPIMemberAccountIDs = source.cliProxyAPIMemberAccountIDs
        }
        if fields.contains(.cliProxyAPIRestrictFreeAccounts) {
            self.draft.cliProxyAPIRestrictFreeAccounts = source.cliProxyAPIRestrictFreeAccounts
        }
        if fields.contains(.cliProxyAPIRoutingStrategy) {
            self.draft.cliProxyAPIRoutingStrategy = source.cliProxyAPIRoutingStrategy
        }
        if fields.contains(.cliProxyAPISwitchProjectOnQuotaExceeded) {
            self.draft.cliProxyAPISwitchProjectOnQuotaExceeded = source.cliProxyAPISwitchProjectOnQuotaExceeded
        }
        if fields.contains(.cliProxyAPISwitchPreviewModelOnQuotaExceeded) {
            self.draft.cliProxyAPISwitchPreviewModelOnQuotaExceeded = source.cliProxyAPISwitchPreviewModelOnQuotaExceeded
        }
        if fields.contains(.cliProxyAPIRequestRetry) {
            self.draft.cliProxyAPIRequestRetry = source.cliProxyAPIRequestRetry
        }
        if fields.contains(.cliProxyAPIMaxRetryInterval) {
            self.draft.cliProxyAPIMaxRetryInterval = source.cliProxyAPIMaxRetryInterval
        }
        if fields.contains(.cliProxyAPIDisableCooling) {
            self.draft.cliProxyAPIDisableCooling = source.cliProxyAPIDisableCooling
        }
        if fields.contains(.cliProxyAPIMemberPrioritiesByAccountID) {
            self.draft.cliProxyAPIMemberPrioritiesByAccountID = source.cliProxyAPIMemberPrioritiesByAccountID
        }
        if fields.contains(.codexkitAutomaticallyChecksForUpdates) {
            self.draft.codexkitAutomaticallyChecksForUpdates = source.codexkitAutomaticallyChecksForUpdates
        }
        if fields.contains(.codexkitAutomaticallyInstallsUpdates) {
            self.draft.codexkitAutomaticallyInstallsUpdates = source.codexkitAutomaticallyInstallsUpdates
        }
        if fields.contains(.codexkitUpdateCheckSchedule) {
            self.draft.codexkitUpdateCheckSchedule = source.codexkitUpdateCheckSchedule
        }
        if fields.contains(.cliProxyAPIAutomaticallyChecksForUpdates) {
            self.draft.cliProxyAPIAutomaticallyChecksForUpdates = source.cliProxyAPIAutomaticallyChecksForUpdates
        }
        if fields.contains(.cliProxyAPIAutomaticallyInstallsUpdates) {
            self.draft.cliProxyAPIAutomaticallyInstallsUpdates = source.cliProxyAPIAutomaticallyInstallsUpdates
        }
        if fields.contains(.cliProxyAPIUpdateCheckSchedule) {
            self.draft.cliProxyAPIUpdateCheckSchedule = source.cliProxyAPIUpdateCheckSchedule
        }
    }
}
