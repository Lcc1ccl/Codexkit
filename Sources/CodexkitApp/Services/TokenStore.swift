import AppKit
import Combine
import Foundation

struct OpenAIAccountSettingsUpdate: Equatable {
    var accountOrder: [String]?
    var accountOrderingMode: CodexBarOpenAIAccountOrderingMode?
    var manualActivationBehavior: CodexBarOpenAIManualActivationBehavior?
    var serviceTier: CodexBarServiceTier?

    init(
        accountOrder: [String]? = nil,
        accountOrderingMode: CodexBarOpenAIAccountOrderingMode? = nil,
        manualActivationBehavior: CodexBarOpenAIManualActivationBehavior? = nil,
        serviceTier: CodexBarServiceTier? = nil
    ) {
        self.accountOrder = accountOrder
        self.accountOrderingMode = accountOrderingMode
        self.manualActivationBehavior = manualActivationBehavior
        self.serviceTier = serviceTier
    }
}

struct OpenAIUsageSettingsUpdate: Equatable {
    var usageDisplayMode: CodexBarUsageDisplayMode
    var plusRelativeWeight: Double
    var proRelativeToPlusMultiplier: Double
    var teamRelativeToPlusMultiplier: Double
}

struct OpenAIGeneralSettingsUpdate: Equatable {
    var menuBarQuotaVisibility: CodexBarMenuBarQuotaVisibility
    var menuBarAPIServiceStatusVisibility: CodexBarMenuBarAPIServiceStatusVisibility
}

struct DesktopSettingsUpdate: Equatable {
    var preferredCodexAppPath: String?
    var accountActivationScopeMode: CodexBarActivationScopeMode?
    var accountActivationRootPaths: [String]?
    var codexkitUpdate: CodexBarDesktopSettings.ManagedUpdateSettings? = nil
    var cliProxyAPIUpdate: CodexBarDesktopSettings.ManagedUpdateSettings? = nil

    var containsUpdateSettingsChange: Bool {
        self.codexkitUpdate != nil || self.cliProxyAPIUpdate != nil
    }
}

struct CLIProxyAPISettingsUpdate: Equatable {
    var enabled: Bool
    var host: String
    var port: Int
    var repositoryRootPath: String?
    var managementSecretKey: String?
    var clientAPIKey: String? = nil
    var memberAccountIDs: [String]
    var restrictFreeAccounts: Bool = true
    var routingStrategy: CLIProxyAPIRoutingStrategy = .roundRobin
    var switchProjectOnQuotaExceeded: Bool = true
    var switchPreviewModelOnQuotaExceeded: Bool = true
    var requestRetry: Int = 3
    var maxRetryInterval: Int = 30
    var disableCooling: Bool = false
    var memberPrioritiesByAccountID: [String: Int] = [:]
}

struct SettingsSaveRequests: Equatable {
    var openAIAccount: OpenAIAccountSettingsUpdate?
    var openAIUsage: OpenAIUsageSettingsUpdate?
    var openAIGeneral: OpenAIGeneralSettingsUpdate?
    var desktop: DesktopSettingsUpdate?
    var cliProxyAPI: CLIProxyAPISettingsUpdate?

    init(
        openAIAccount: OpenAIAccountSettingsUpdate? = nil,
        openAIUsage: OpenAIUsageSettingsUpdate? = nil,
        openAIGeneral: OpenAIGeneralSettingsUpdate? = nil,
        desktop: DesktopSettingsUpdate? = nil,
        cliProxyAPI: CLIProxyAPISettingsUpdate? = nil
    ) {
        self.openAIAccount = openAIAccount
        self.openAIUsage = openAIUsage
        self.openAIGeneral = openAIGeneral
        self.desktop = desktop
        self.cliProxyAPI = cliProxyAPI
    }

    var isEmpty: Bool {
        self.openAIAccount == nil &&
        self.openAIUsage == nil &&
        self.openAIGeneral == nil &&
        self.desktop == nil &&
        self.cliProxyAPI == nil
    }
}

struct OpenRouterModelCatalogSnapshot: Equatable {
    var models: [CodexBarOpenRouterModel]
    var fetchedAt: Date
}

protocol OpenRouterModelCatalogFetching {
    func fetchCatalog(apiKey: String) async throws -> OpenRouterModelCatalogSnapshot
}

struct OpenRouterModelCatalogService: OpenRouterModelCatalogFetching {
    private struct ModelsResponse: Decodable {
        struct Model: Decodable {
            let id: String
            let name: String?
        }

        let data: [Model]
    }

    private let urlSession: URLSession
    private let now: () -> Date

    init(
        urlSession: URLSession? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.urlSession = urlSession ?? URLSession(configuration: .ephemeral)
        self.now = now
    }

    func fetchCatalog(apiKey: String) async throws -> OpenRouterModelCatalogSnapshot {
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedAPIKey.isEmpty == false else {
            throw TokenStoreError.invalidInput
        }

        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/models")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(trimmedAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await self.urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
        let models = decoded.data
            .map { CodexBarOpenRouterModel(id: $0.id, name: $0.name) }
            .filter { $0.id.isEmpty == false }
            .sorted { lhs, rhs in
                let left = lhs.name.lowercased()
                let right = rhs.name.lowercased()
                if left == right {
                    return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
                }
                return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
            }

        return OpenRouterModelCatalogSnapshot(models: models, fetchedAt: self.now())
    }
}

final class TokenStore: ObservableObject {
    static let shared = TokenStore()

    @Published var accounts: [TokenAccount] = []
    @Published private(set) var config: CodexBarConfig
    @Published private(set) var localCostSummary: LocalCostSummary = .empty
    @Published private(set) var cliProxyAPIState: CLIProxyAPIServiceState

    private let configStore: CodexBarConfigStore
    private let syncService: any CodexSynchronizing
    private let cliProxyAPIQuotaSnapshotStore: CLIProxyAPIQuotaSnapshotStore
    private let switchJournalStore = SwitchJournalStore()
    private let costSummaryService = LocalCostSummaryService()
    private let openRouterGatewayService: OpenRouterGatewayControlling
    private let openRouterModelCatalogService: any OpenRouterModelCatalogFetching
    private let openRouterGatewayLeaseStore: OpenRouterGatewayLeaseStoring
    private let codexRunningProcessIDs: () -> Set<pid_t>
    private let apiServiceRoutingProbeAction: @MainActor (CLIProxyAPIServiceConfig) async throws -> Void
    private let refreshStateQueue = DispatchQueue(label: "lzl.codexkit.refresh-state")
    private let usageRefreshStateQueue = DispatchQueue(label: "lzl.codexkit.usage-refresh-state")
    private var isRefreshingLocalCostSummary = false
    private var isRefreshingAllUsage = false
    private var refreshingUsageAccountIDs: Set<String> = []
    private var cancellables: Set<AnyCancellable> = []
    private var openRouterGatewayLeaseSnapshot: OpenRouterGatewayLeaseSnapshot?
    private var openRouterGatewayLeaseTimer: Timer?
    private var lastPublishedOpenRouterSelected = false

    init(
        configStore: CodexBarConfigStore = CodexBarConfigStore(),
        syncService: any CodexSynchronizing = CodexSyncService(),
        cliProxyAPIQuotaSnapshotStore: CLIProxyAPIQuotaSnapshotStore = .shared,
        openRouterGatewayService: OpenRouterGatewayControlling = OpenRouterGatewayService(),
        openRouterModelCatalogService: any OpenRouterModelCatalogFetching = OpenRouterModelCatalogService(),
        openRouterGatewayLeaseStore: OpenRouterGatewayLeaseStoring = OpenRouterGatewayLeaseStore(),
        apiServiceRoutingProbeAction: @escaping @MainActor (CLIProxyAPIServiceConfig) async throws -> Void = { config in
            try await TokenStore.defaultAPIServiceRoutingProbe(config: config)
        },
        codexRunningProcessIDs: @escaping () -> Set<pid_t> = {
            Set(NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").map(\.processIdentifier))
        }
    ) {
        self.configStore = configStore
        self.syncService = syncService
        self.cliProxyAPIQuotaSnapshotStore = cliProxyAPIQuotaSnapshotStore
        self.openRouterGatewayService = openRouterGatewayService
        self.openRouterModelCatalogService = openRouterModelCatalogService
        self.openRouterGatewayLeaseStore = openRouterGatewayLeaseStore
        self.apiServiceRoutingProbeAction = apiServiceRoutingProbeAction
        self.codexRunningProcessIDs = codexRunningProcessIDs
        self.openRouterGatewayLeaseSnapshot = openRouterGatewayLeaseStore.loadLease()

        let loadedConfig: CodexBarConfig
        if let loaded = try? self.configStore.loadOrMigrate() {
            loadedConfig = loaded
        } else {
            loadedConfig = CodexBarConfig()
        }
        self.config = loadedConfig
        self.cliProxyAPIState = CLIProxyAPIServiceState(
            config: Self.makeCLIProxyAPIServiceConfig(from: loadedConfig.desktop.cliProxyAPI),
            status: .stopped,
            lastError: nil,
            pid: nil,
            authFileCount: loadedConfig.desktop.cliProxyAPI.memberAccountIDs.count,
            modelCount: nil,
            modelIDs: [],
            totalRequests: nil,
            failedRequests: nil,
            totalTokens: nil,
            quotaSnapshot: cliProxyAPIQuotaSnapshotStore.load(),
            accountUsageItems: []
        )
        self.lastPublishedOpenRouterSelected = self.config.activeProvider()?.kind == .openRouter

        self.publishState()
        self.localCostSummary = self.loadCachedLocalCostSummary()
        self.seedSwitchJournalIfNeeded()
        try? self.syncService.synchronize(config: self.config)
    }

    var customProviders: [CodexBarProvider] {
        self.config.providers.filter { $0.kind == .openAICompatible }
    }

    var openRouterProvider: CodexBarProvider? {
        self.config.openRouterProvider()
    }

    var activeProvider: CodexBarProvider? {
        self.config.activeProvider()
    }

    var activeProviderAccount: CodexBarProviderAccount? {
        self.config.activeAccount()
    }

    var activeModel: String {
        if let activeProvider = self.config.activeProvider(),
           activeProvider.kind == .openRouter,
           let selectedModelID = activeProvider.openRouterEffectiveModelID {
            return selectedModelID
        }
        return self.config.global.defaultModel
    }

    func load() {
        if let loaded = try? self.configStore.loadOrMigrate() {
            self.config = loaded
            self.publishState()
            self.localCostSummary = self.loadCachedLocalCostSummary()
            self.syncCLIProxyAPIStateFromConfig()
        }
    }

    func addOrUpdate(_ account: TokenAccount) {
        let result = self.config.upsertOAuthAccount(account, activate: false)
        self.persistIgnoringErrors(syncCodex: result.syncCodex)
    }

    func remove(_ account: TokenAccount) {
        guard var provider = self.oauthProvider() else { return }
        provider.accounts.removeAll { $0.id == account.accountId }
        self.config.removeOpenAIAccountOrder(accountID: account.accountId)

        if provider.accounts.isEmpty {
            self.config.providers.removeAll { $0.id == provider.id }
            if self.config.active.providerId == provider.id {
                let fallback = self.config.providers.first
                self.config.active.providerId = fallback?.id
                self.config.active.accountId = fallback?.activeAccount?.id
            }
        } else {
            if provider.activeAccountId == account.accountId {
                provider.activeAccountId = provider.accounts.first?.id
            }
            if self.config.active.providerId == provider.id && self.config.active.accountId == account.accountId {
                self.config.active.accountId = provider.activeAccountId
            }
            self.upsertProvider(provider)
        }

        self.config.normalizeOpenAIAccountOrder()
        self.persistIgnoringErrors(syncCodex: self.config.active.providerId == provider.id)
    }

    func activate(
        _ account: TokenAccount,
        reason: AutoRoutingSwitchReason = .manual,
        automatic: Bool = false,
        forced: Bool = false,
        protectedByManualGrace: Bool = false
    ) throws {
        _ = try self.reconcileAuthJSONIfNeeded(accountID: account.accountId)
        let previousConfig = self.config
        let previousAccountID = self.activeAccount()?.accountId
        var updatedConfig = self.config
        _ = try updatedConfig.activateOAuthAccount(accountID: account.accountId)
        if previousConfig.desktop.cliProxyAPI.enabled {
            updatedConfig.desktop.cliProxyAPI.enabled = false
        }
        try self.commitActiveSelectionChange(
            updatedConfig: updatedConfig,
            previousConfig: previousConfig,
            intent: previousConfig.desktop.cliProxyAPI.enabled ? .disableAPIServiceAndSwitch : .directSwitch
        )
        try self.appendSwitchJournal(
            previousAccountID: previousAccountID,
            reason: reason,
            automatic: automatic,
            forced: forced,
            protectedByManualGrace: protectedByManualGrace
        )
    }

    func activeAccount() -> TokenAccount? {
        self.accounts.first(where: { $0.isActive })
    }

    func activateCustomProvider(providerID: String, accountID: String) throws {
        let previousConfig = self.config
        let previousAccountID = self.config.active.accountId
        guard var provider = self.config.providers.first(where: { $0.id == providerID && $0.kind == .openAICompatible }) else {
            throw TokenStoreError.providerNotFound
        }
        guard provider.accounts.contains(where: { $0.id == accountID }) else {
            throw TokenStoreError.accountNotFound
        }

        provider.activeAccountId = accountID
        var updatedConfig = self.config
        if let index = updatedConfig.providers.firstIndex(where: { $0.id == provider.id }) {
            updatedConfig.providers[index] = provider
        } else {
            updatedConfig.providers.append(provider)
        }
        updatedConfig.active.providerId = provider.id
        updatedConfig.active.accountId = accountID
        if previousConfig.desktop.cliProxyAPI.enabled {
            updatedConfig.desktop.cliProxyAPI.enabled = false
        }

        try self.commitActiveSelectionChange(
            updatedConfig: updatedConfig,
            previousConfig: previousConfig,
            intent: previousConfig.desktop.cliProxyAPI.enabled ? .disableAPIServiceAndSwitch : .directSwitch
        )
        try self.appendSwitchJournal(previousAccountID: previousAccountID)
    }

    func activateOpenRouterProvider(accountID: String) throws {
        let previousConfig = self.config
        let previousAccountID = self.config.active.accountId
        var updatedConfig = self.config
        _ = try updatedConfig.activateOpenRouterAccount(accountID: accountID)
        if previousConfig.desktop.cliProxyAPI.enabled {
            updatedConfig.desktop.cliProxyAPI.enabled = false
        }
        try self.commitActiveSelectionChange(
            updatedConfig: updatedConfig,
            previousConfig: previousConfig,
            intent: previousConfig.desktop.cliProxyAPI.enabled ? .disableAPIServiceAndSwitch : .directSwitch
        )
        try self.appendSwitchJournal(previousAccountID: previousAccountID)
    }

    func addCustomProvider(label: String, baseURL: String, accountLabel: String, apiKey: String) throws {
        let previousAccountID = self.config.active.accountId
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAccountLabel = accountLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedLabel.isEmpty == false,
              trimmedBaseURL.isEmpty == false,
              trimmedAPIKey.isEmpty == false else {
            throw TokenStoreError.invalidInput
        }

        let providerID = self.slug(from: trimmedLabel)
        let account = CodexBarProviderAccount(
            kind: .apiKey,
            label: trimmedAccountLabel.isEmpty ? "Default" : trimmedAccountLabel,
            apiKey: trimmedAPIKey,
            addedAt: Date()
        )
        let provider = CodexBarProvider(
            id: providerID,
            kind: .openAICompatible,
            label: trimmedLabel,
            enabled: true,
            baseURL: trimmedBaseURL,
            activeAccountId: account.id,
            accounts: [account]
        )

        self.config.providers.removeAll { $0.id == provider.id }
        self.config.providers.append(provider)
        self.config.active.providerId = provider.id
        self.config.active.accountId = account.id

        try self.persist(syncCodex: true)
        try self.appendSwitchJournal(previousAccountID: previousAccountID)
    }

    func addOpenRouterProvider(
        accountLabel: String = "",
        apiKey: String,
        selectedModelID: String? = nil,
        pinnedModelIDs: [String] = [],
        cachedModelCatalog: [CodexBarOpenRouterModel] = [],
        fetchedAt: Date? = nil
    ) throws {
        _ = try self.config.upsertOpenRouterProvider(
            accountLabel: accountLabel,
            apiKey: apiKey,
            activate: false
        )
        if selectedModelID != nil ||
            pinnedModelIDs.isEmpty == false ||
            cachedModelCatalog.isEmpty == false ||
            fetchedAt != nil {
            try self.config.setOpenRouterModelSelection(
                selectedModelID: selectedModelID,
                pinnedModelIDs: pinnedModelIDs,
                cachedModelCatalog: cachedModelCatalog,
                fetchedAt: fetchedAt
            )
        }
        try self.persist(syncCodex: false)
    }

    func addOpenRouterProviderAccount(
        label: String = "",
        apiKey: String,
        selectedModelID: String? = nil,
        pinnedModelIDs: [String] = [],
        cachedModelCatalog: [CodexBarOpenRouterModel] = [],
        fetchedAt: Date? = nil
    ) throws {
        _ = try self.config.upsertOpenRouterProvider(
            accountLabel: label,
            apiKey: apiKey,
            activate: false
        )
        if selectedModelID != nil ||
            pinnedModelIDs.isEmpty == false ||
            cachedModelCatalog.isEmpty == false ||
            fetchedAt != nil {
            try self.config.setOpenRouterModelSelection(
                selectedModelID: selectedModelID,
                pinnedModelIDs: pinnedModelIDs,
                cachedModelCatalog: cachedModelCatalog,
                fetchedAt: fetchedAt
            )
        }
        try self.persist(syncCodex: false)
    }

    func updateOpenRouterDefaultModel(_ value: String?) throws {
        try self.updateOpenRouterSelectedModel(value)
    }

    func updateOpenRouterSelectedModel(_ value: String?) throws {
        guard value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw TokenStoreError.invalidInput
        }
        try self.config.setOpenRouterSelectedModel(value)
        let shouldSyncCodex = self.config.activeProvider()?.kind == .openRouter
        try self.persist(syncCodex: shouldSyncCodex)
    }

    func updateOpenRouterModelSelection(
        selectedModelID: String?,
        pinnedModelIDs: [String],
        cachedModelCatalog: [CodexBarOpenRouterModel],
        fetchedAt: Date?
    ) throws {
        try self.config.setOpenRouterModelSelection(
            selectedModelID: selectedModelID,
            pinnedModelIDs: pinnedModelIDs,
            cachedModelCatalog: cachedModelCatalog,
            fetchedAt: fetchedAt
        )
        let shouldSyncCodex = self.config.activeProvider()?.kind == .openRouter
        try self.persist(syncCodex: shouldSyncCodex)
    }

    func refreshOpenRouterModelCatalog() async throws {
        guard let provider = self.openRouterProvider,
              let account = provider.activeAccount,
              let apiKey = account.apiKey else {
            throw TokenStoreError.accountNotFound
        }

        let snapshot = try await self.openRouterModelCatalogService.fetchCatalog(apiKey: apiKey)
        try self.config.updateOpenRouterModelCatalog(snapshot.models, fetchedAt: snapshot.fetchedAt)
        try self.persist(syncCodex: false)
    }

    func previewOpenRouterModelCatalog(apiKey: String) async throws -> OpenRouterModelCatalogSnapshot {
        try await self.openRouterModelCatalogService.fetchCatalog(apiKey: apiKey)
    }

    func addCustomProviderAccount(providerID: String, label: String, apiKey: String) throws {
        guard var provider = self.config.providers.first(where: { $0.id == providerID && $0.kind == .openAICompatible }) else {
            throw TokenStoreError.providerNotFound
        }
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedAPIKey.isEmpty == false else { throw TokenStoreError.invalidInput }

        let account = CodexBarProviderAccount(
            kind: .apiKey,
            label: label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Account \(provider.accounts.count + 1)" : label.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: trimmedAPIKey,
            addedAt: Date()
        )
        provider.accounts.append(account)
        if provider.activeAccountId == nil {
            provider.activeAccountId = account.id
        }
        self.upsertProvider(provider)
        try self.persist(syncCodex: false)
    }

    func updateCustomProvider(
        providerID: String,
        label: String,
        baseURL: String,
        accounts: [CodexBarProviderAccount],
        activeAccountID: String?
    ) throws {
        guard var provider = self.config.providers.first(where: { $0.id == providerID && $0.kind == .openAICompatible }) else {
            throw TokenStoreError.providerNotFound
        }

        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedLabel.isEmpty == false,
              trimmedBaseURL.isEmpty == false,
              accounts.isEmpty == false else {
            throw TokenStoreError.invalidInput
        }

        let existingAccountsByID = Dictionary(uniqueKeysWithValues: provider.accounts.map { ($0.id, $0) })
        let normalizedAccounts = accounts.map { account in
            var normalized = account
            let trimmedAccountLabel = normalized.label.trimmingCharacters(in: .whitespacesAndNewlines)
            normalized.label = trimmedAccountLabel.isEmpty ? normalized.label : trimmedAccountLabel
            normalized.apiKey = normalized.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let existing = existingAccountsByID[normalized.id] {
                normalized.addedAt = existing.addedAt
            }
            return normalized
        }
        guard normalizedAccounts.allSatisfy({
            ($0.apiKey?.isEmpty == false) && $0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }) else {
            throw TokenStoreError.invalidInput
        }

        provider.label = trimmedLabel
        provider.baseURL = trimmedBaseURL
        provider.accounts = normalizedAccounts
        provider.activeAccountId = normalizedAccounts.contains(where: { $0.id == activeAccountID })
            ? activeAccountID
            : normalizedAccounts.first?.id
        self.upsertProvider(provider)

        if self.config.active.providerId == providerID {
            self.config.active.accountId = provider.activeAccountId
        }

        try self.persist(syncCodex: self.config.active.providerId == providerID)
    }

    func removeCustomProviderAccount(providerID: String, accountID: String) throws {
        guard var provider = self.config.providers.first(where: { $0.id == providerID && $0.kind == .openAICompatible }) else {
            throw TokenStoreError.providerNotFound
        }
        provider.accounts.removeAll { $0.id == accountID }
        if provider.accounts.isEmpty {
            self.config.providers.removeAll { $0.id == providerID }
            if self.config.active.providerId == providerID {
                let fallback = self.config.providers.first
                self.config.active.providerId = fallback?.id
                self.config.active.accountId = fallback?.activeAccount?.id
                try self.persist(syncCodex: fallback != nil)
                return
            }
        } else {
            if provider.activeAccountId == accountID {
                provider.activeAccountId = provider.accounts.first?.id
            }
            if self.config.active.providerId == providerID && self.config.active.accountId == accountID {
                self.upsertProvider(provider)
                self.config.active.accountId = provider.activeAccountId
                try self.persist(syncCodex: true)
                return
            }
            self.upsertProvider(provider)
        }
        try self.persist(syncCodex: false)
    }

    func removeCustomProvider(providerID: String) throws {
        self.config.providers.removeAll { $0.id == providerID }
        if self.config.active.providerId == providerID {
            let fallback = self.oauthProvider() ?? self.openRouterProvider ?? self.customProviders.first
            self.config.active.providerId = fallback?.id
            self.config.active.accountId = fallback?.activeAccount?.id
            try self.persist(syncCodex: fallback != nil)
            return
        }
        try self.persist(syncCodex: false)
    }

    func removeOpenRouterProviderAccount(accountID: String) throws {
        guard var provider = self.openRouterProvider else {
            throw TokenStoreError.providerNotFound
        }

        provider.accounts.removeAll { $0.id == accountID }
        if provider.accounts.isEmpty {
            self.config.providers.removeAll { $0.id == provider.id }
            if self.config.active.providerId == provider.id {
                let fallback = self.oauthProvider() ?? self.customProviders.first
                self.config.active.providerId = fallback?.id
                self.config.active.accountId = fallback?.activeAccount?.id
                try self.persist(syncCodex: fallback != nil)
                return
            }
        } else {
            if provider.activeAccountId == accountID {
                provider.activeAccountId = provider.accounts.first?.id
            }
            if self.config.active.providerId == provider.id && self.config.active.accountId == accountID {
                self.upsertProvider(provider)
                self.config.active.accountId = provider.activeAccountId
                try self.persist(syncCodex: true)
                return
            }
            self.upsertProvider(provider)
        }

        try self.persist(syncCodex: false)
    }

    func markActiveAccount() {
        self.publishState()
    }

    func saveOpenAIAccountSettings(_ request: OpenAIAccountSettingsUpdate) throws {
        try self.saveSettings(
            SettingsSaveRequests(openAIAccount: request)
        )
    }

    func restoreActiveSelection(
        activeProviderID: String?,
        activeAccountID: String?
    ) throws {
        self.config.active.providerId = activeProviderID
        self.config.active.accountId = activeAccountID
        try self.persist(syncCodex: activeProviderID != nil)
    }

    func setAPIServiceEnabledFromMenu(_ enabled: Bool) throws {
        guard self.config.desktop.cliProxyAPI.enabled != enabled else { return }
        var updatedConfig = self.config
        updatedConfig.desktop.cliProxyAPI.enabled = enabled
        try self.configStore.save(updatedConfig)
        self.config = updatedConfig
        self.syncCLIProxyAPIStateFromConfig()
    }

    func setAPIServiceRoutingEnabledFromMenu(_ enabled: Bool) throws {
        if enabled == false,
           self.config.desktop.cliProxyAPI.enabled == false {
            return
        }

        if enabled == false {
            try self.disableAPIServiceRoutingAndRestoreDirect()
            return
        }

        let request = CLIProxyAPISettingsUpdate(
            enabled: enabled,
            host: self.config.desktop.cliProxyAPI.host,
            port: self.config.desktop.cliProxyAPI.port,
            repositoryRootPath: nil,
            managementSecretKey: self.config.desktop.cliProxyAPI.managementSecretKey,
            clientAPIKey: self.config.desktop.cliProxyAPI.clientAPIKey,
            memberAccountIDs: self.config.desktop.cliProxyAPI.memberAccountIDs,
            restrictFreeAccounts: self.config.desktop.cliProxyAPI.restrictFreeAccounts,
            routingStrategy: self.config.desktop.cliProxyAPI.routingStrategy,
            switchProjectOnQuotaExceeded: self.config.desktop.cliProxyAPI.switchProjectOnQuotaExceeded,
            switchPreviewModelOnQuotaExceeded: self.config.desktop.cliProxyAPI.switchPreviewModelOnQuotaExceeded,
            requestRetry: self.config.desktop.cliProxyAPI.requestRetry,
            maxRetryInterval: self.config.desktop.cliProxyAPI.maxRetryInterval,
            disableCooling: self.config.desktop.cliProxyAPI.disableCooling,
            memberPrioritiesByAccountID: self.config.desktop.cliProxyAPI.memberPrioritiesByAccountID
        )
        try self.saveSettings(SettingsSaveRequests(cliProxyAPI: request))
    }

    func enableAPIServiceRoutingFromMenu() async throws -> String {
        let previousConfig = self.config
        let previousDesktopSettings = previousConfig.desktop
        var updatedConfig = previousConfig
        let request = CLIProxyAPISettingsUpdate(
            enabled: true,
            host: previousConfig.desktop.cliProxyAPI.host,
            port: previousConfig.desktop.cliProxyAPI.port,
            repositoryRootPath: nil,
            managementSecretKey: previousConfig.desktop.cliProxyAPI.managementSecretKey,
            clientAPIKey: previousConfig.desktop.cliProxyAPI.clientAPIKey,
            memberAccountIDs: previousConfig.desktop.cliProxyAPI.memberAccountIDs,
            restrictFreeAccounts: previousConfig.desktop.cliProxyAPI.restrictFreeAccounts,
            routingStrategy: previousConfig.desktop.cliProxyAPI.routingStrategy,
            switchProjectOnQuotaExceeded: previousConfig.desktop.cliProxyAPI.switchProjectOnQuotaExceeded,
            switchPreviewModelOnQuotaExceeded: previousConfig.desktop.cliProxyAPI.switchPreviewModelOnQuotaExceeded,
            requestRetry: previousConfig.desktop.cliProxyAPI.requestRetry,
            maxRetryInterval: previousConfig.desktop.cliProxyAPI.maxRetryInterval,
            disableCooling: previousConfig.desktop.cliProxyAPI.disableCooling,
            memberPrioritiesByAccountID: previousConfig.desktop.cliProxyAPI.memberPrioritiesByAccountID
        )
        SettingsSaveRequestApplier.apply(request, to: &updatedConfig)
        self.configureDirectSelectionForEnablingAPIService(in: &updatedConfig)
        let synchronizedConfig = self.configForNativeSync(updatedConfig)
        let probeConfig = Self.makeCLIProxyAPIServiceConfig(from: synchronizedConfig.desktop.cliProxyAPI)
        let nativeTargets = CodexPaths.effectiveNativeTargets(for: synchronizedConfig.desktop)
        let directSnapshots = self.captureNativeSnapshots(
            for: nativeTargets,
            authURL: \.authURL,
            configURL: \.configTomlURL
        )
        let preAPISnapshots = self.captureNativeSnapshots(
            for: nativeTargets,
            authURL: \.authPreAPIBackupURL,
            configURL: \.configPreAPIBackupURL
        )

        do {
            try self.syncService.synchronize(config: synchronizedConfig, intent: .enableAPIService)
            try self.restoreNativeSnapshots(
                preAPISnapshots,
                to: nativeTargets,
                authURL: \.authPreAPIBackupURL,
                configURL: \.configPreAPIBackupURL
            )
            await MainActor.run {
                CLIProxyAPIRuntimeController.shared.applyConfiguration(synchronizedConfig.desktop.cliProxyAPI)
            }
            try await self.apiServiceRoutingProbeAction(probeConfig)
            try self.configStore.save(synchronizedConfig)
            self.config = synchronizedConfig
            self.publishState()
            self.syncCLIProxyAPIStateFromConfig()
            try self.restoreNativeSnapshots(
                directSnapshots,
                to: nativeTargets,
                authURL: \.authPreAPIBackupURL,
                configURL: \.configPreAPIBackupURL
            )
            return L.menuAPIServiceRoutingProbeSuccess
        } catch {
            let probeFailure = self.normalizeAPIServiceRoutingProbeFailure(error)
            let attemptedDesktopSettings = synchronizedConfig.desktop

            do {
                try self.rollbackFailedAPIServiceRoutingEnable(
                    previousConfig: previousConfig,
                    previousDesktopSettings: previousDesktopSettings,
                    attemptedDesktopSettings: attemptedDesktopSettings
                )
            } catch {
                let summary = self.apiServiceRoutingProbeFailureSummary(probeFailure)
                let rollbackDetail = Self.sanitizedAPIServiceRoutingProbeDetail(error.localizedDescription)
                throw TokenStoreError.apiServiceRoutingRollbackFailed("\(summary); rollback_failed: \(rollbackDetail)")
            }

            throw TokenStoreError.apiServiceRoutingProbeFailed(
                self.apiServiceRoutingProbeFailureSummary(probeFailure)
            )
        }
    }

    func disableAPIServiceRoutingAndRestoreDirect() throws {
        let previousConfig = self.config
        guard previousConfig.desktop.cliProxyAPI.enabled else { return }
        var updatedConfig = previousConfig
        updatedConfig.desktop.cliProxyAPI.enabled = false
        self.restoreDirectSelectionAfterDisablingAPIService(in: &updatedConfig)
        try self.commitActiveSelectionChange(
            updatedConfig: updatedConfig,
            previousConfig: previousConfig,
            intent: .disableAPIServiceRestoreDirect
        )
    }

    func saveOpenAIUsageSettings(_ request: OpenAIUsageSettingsUpdate) throws {
        try self.saveSettings(
            SettingsSaveRequests(openAIUsage: request)
        )
    }

    func saveDesktopSettings(_ request: DesktopSettingsUpdate) throws {
        try self.saveSettings(
            SettingsSaveRequests(desktop: request)
        )
    }

    func saveSettings(_ requests: SettingsSaveRequests) throws {
        guard requests.isEmpty == false else { return }

        let previousConfig = self.config
        let previousDesktopSettings = self.config.desktop
        let previousAPIServiceEnabled = self.config.desktop.cliProxyAPI.enabled
        let previousActiveProviderID = self.config.active.providerId
        let previousActiveAccountID = self.config.active.accountId
        var updatedConfig = self.config
        try SettingsSaveRequestApplier.apply(requests, to: &updatedConfig)
        if let cliProxyRequest = requests.cliProxyAPI {
            if previousAPIServiceEnabled == false,
               cliProxyRequest.enabled {
                self.configureDirectSelectionForEnablingAPIService(in: &updatedConfig)
            } else if previousAPIServiceEnabled,
                      cliProxyRequest.enabled == false {
                self.restoreDirectSelectionAfterDisablingAPIService(in: &updatedConfig)
            }
        }

        let shouldSyncCodex = self.shouldSyncCodexAfterSavingSettings(
            requests: requests,
            previousActiveProviderID: previousActiveProviderID,
            previousActiveAccountID: previousActiveAccountID,
            updatedConfig: updatedConfig
        )
        if let cliProxyRequest = requests.cliProxyAPI,
           previousAPIServiceEnabled,
           cliProxyRequest.enabled == false,
           shouldSyncCodex {
            try self.commitActiveSelectionChange(
                updatedConfig: updatedConfig,
                previousConfig: previousConfig,
                intent: .disableAPIServiceRestoreDirect,
                previousDesktopSettings: previousDesktopSettings,
                reconfigureRuntimeAfterCommit: true
            )
        } else {
            self.config = updatedConfig
            try self.persist(syncCodex: shouldSyncCodex)
            try self.syncService.cleanupRemovedTargets(
                previousDesktopSettings: previousDesktopSettings,
                currentDesktopSettings: updatedConfig.desktop
            )
            self.syncCLIProxyAPIStateFromConfig()
            if requests.cliProxyAPI != nil {
                Task { @MainActor in
                    CLIProxyAPIRuntimeController.shared.reconfigureIfRunning(updatedConfig.desktop.cliProxyAPI)
                }
            }
        }
        if requests.desktop?.containsUpdateSettingsChange == true {
            Task { @MainActor in
                UpdateCoordinator.shared.reloadSettings()
            }
        }
    }

    func updateCLIProxyAPIState(_ state: CLIProxyAPIServiceState) {
        self.cliProxyAPIState = state
        if let snapshot = state.quotaSnapshot {
            self.cliProxyAPIQuotaSnapshotStore.save(snapshot)
        }
    }

    private func syncCLIProxyAPIStateFromConfig() {
        let existingState = self.cliProxyAPIState
        let nextConfig = Self.makeCLIProxyAPIServiceConfig(from: self.config.desktop.cliProxyAPI)
        self.cliProxyAPIState = CLIProxyAPIServiceState(
            config: nextConfig,
            status: existingState.status,
            lastError: existingState.lastError,
            pid: existingState.pid,
            authFileCount: existingState.authFileCount ?? self.config.desktop.cliProxyAPI.memberAccountIDs.count,
            modelCount: existingState.modelCount,
            modelIDs: existingState.modelIDs,
            totalRequests: existingState.totalRequests,
            failedRequests: existingState.failedRequests,
            totalTokens: existingState.totalTokens,
            quotaSnapshot: existingState.quotaSnapshot,
            accountUsageItems: existingState.accountUsageItems,
            observedAuthFiles: existingState.observedAuthFiles
        )
    }

    private static func makeCLIProxyAPIServiceConfig(
        from settings: CodexBarDesktopSettings.CLIProxyAPISettings
    ) -> CLIProxyAPIServiceConfig {
        CLIProxyAPIServiceConfig(
            host: settings.host,
            port: settings.port,
            authDirectory: CLIProxyAPIService.authDirectoryURL,
            managementSecretKey: settings.managementSecretKey ?? "",
            clientAPIKey: settings.clientAPIKey ?? "",
            allowRemoteManagement: false,
            enabled: settings.enabled,
            routingStrategy: settings.routingStrategy,
            switchProjectOnQuotaExceeded: settings.switchProjectOnQuotaExceeded,
            switchPreviewModelOnQuotaExceeded: settings.switchPreviewModelOnQuotaExceeded,
            requestRetry: settings.requestRetry,
            maxRetryInterval: settings.maxRetryInterval,
            disableCooling: settings.disableCooling
        )
    }

    private func configForNativeSync(_ config: CodexBarConfig) -> CodexBarConfig {
        guard config.activeProvider()?.kind == .openAIOAuth else { return config }
        return self.configStore.reconcileAuthJSON(
            in: config,
            onlyAccountIDs: config.active.accountId.map { Set([$0]) }
        ).config
    }

    private func commitActiveSelectionChange(
        updatedConfig: CodexBarConfig,
        previousConfig: CodexBarConfig,
        intent: CodexSyncIntent,
        previousDesktopSettings: CodexBarDesktopSettings? = nil,
        reconfigureRuntimeAfterCommit: Bool = false
    ) throws {
        let synchronizedConfig = self.configForNativeSync(updatedConfig)
        do {
            try self.syncService.synchronize(config: synchronizedConfig, intent: intent)
            if let previousDesktopSettings {
                try self.syncService.cleanupRemovedTargets(
                    previousDesktopSettings: previousDesktopSettings,
                    currentDesktopSettings: synchronizedConfig.desktop
                )
            }
            try self.configStore.save(synchronizedConfig)
        } catch {
            _ = try? self.syncService.restoreNativeConfiguration(desktopSettings: synchronizedConfig.desktop)
            if let previousDesktopSettings {
                try? self.syncService.cleanupRemovedTargets(
                    previousDesktopSettings: synchronizedConfig.desktop,
                    currentDesktopSettings: previousDesktopSettings
                )
            }
            throw error
        }

        self.config = synchronizedConfig
        self.publishState()
        self.syncCLIProxyAPIStateFromConfig()

        if reconfigureRuntimeAfterCommit {
            Task { @MainActor in
                CLIProxyAPIRuntimeController.shared.applyConfiguration(synchronizedConfig.desktop.cliProxyAPI)
                if synchronizedConfig.desktop.cliProxyAPI.enabled == false {
                    CLIProxyAPIRuntimeController.shared.stop()
                }
            }
        } else if previousConfig.desktop.cliProxyAPI.enabled,
                  synchronizedConfig.desktop.cliProxyAPI.enabled == false {
            Task { @MainActor in
                CLIProxyAPIRuntimeController.shared.stop()
            }
        }
    }

    func hasStaleOAuthUsageSnapshot(maxAge: TimeInterval, now: Date = Date()) -> Bool {
        self.accounts.contains {
            $0.isSuspended == false &&
            $0.tokenExpired == false &&
            $0.isUsageSnapshotStale(maxAge: maxAge, now: now)
        }
    }

    func beginUsageRefresh(accountID: String) -> Bool {
        self.usageRefreshStateQueue.sync {
            self.refreshingUsageAccountIDs.insert(accountID).inserted
        }
    }

    func endUsageRefresh(accountID: String) {
        _ = self.usageRefreshStateQueue.sync {
            self.refreshingUsageAccountIDs.remove(accountID)
        }
    }

    func beginAllUsageRefresh() -> Bool {
        self.usageRefreshStateQueue.sync {
            guard self.isRefreshingAllUsage == false else { return false }
            self.isRefreshingAllUsage = true
            return true
        }
    }

    func reconcileAuthJSONIfNeeded(accountID: String? = nil) throws -> Bool {
        let changed = self.absorbNewerAuthJSONIfNeeded(accountID: accountID)
        guard changed else { return false }
        try self.configStore.save(self.config)
        self.publishState()
        return true
    }

    func oauthAccount(accountID: String) -> TokenAccount? {
        self.accounts.first(where: { $0.accountId == accountID })
    }

    func apiServicePoolServiceability(now: Date = Date()) -> APIServicePoolServiceability {
        guard self.config.desktop.cliProxyAPI.enabled else {
            return .apiServiceDisabled
        }

        guard self.cliProxyAPIState.status == .running else {
            return .apiServiceDegraded
        }

        let selectedAccountIDs = Set(self.config.desktop.cliProxyAPI.memberAccountIDs)
        let selectedObservedAuthFiles = self.cliProxyAPIState.observedAuthFiles.filter { file in
            guard let localAccountID = file.localAccountID else { return false }
            return selectedAccountIDs.contains(localAccountID)
        }

        guard selectedObservedAuthFiles.isEmpty == false else {
            return .apiServiceRunning
        }

        let allBlocked = selectedObservedAuthFiles.allSatisfy { self.isObservedAuthBlocked($0, now: now) }
        return allBlocked ? .observedPoolUnserviceable : .apiServiceRunning
    }

    func endAllUsageRefresh() {
        self.usageRefreshStateQueue.sync {
            self.isRefreshingAllUsage = false
        }
    }

    // MARK: - Private

    private func oauthProvider() -> CodexBarProvider? {
        self.config.providers.first(where: { $0.kind == .openAIOAuth })
    }

    private func isObservedAuthBlocked(
        _ authFile: CLIProxyAPIObservedAuthFile,
        now: Date
    ) -> Bool {
        if authFile.disabled {
            return true
        }
        if authFile.status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "disabled" {
            return true
        }
        if authFile.unavailable,
           let nextRetryAfter = authFile.nextRetryAfter,
           nextRetryAfter > now {
            return true
        }
        return false
    }

    private func upsertProvider(_ provider: CodexBarProvider) {
        if let index = self.config.providers.firstIndex(where: { $0.id == provider.id }) {
            self.config.providers[index] = provider
        } else {
            self.config.providers.append(provider)
        }
    }

    private func persist(syncCodex: Bool) throws {
        if syncCodex,
           self.config.activeProvider()?.kind == .openAIOAuth {
            _ = self.absorbNewerAuthJSONIfNeeded(accountID: self.config.active.accountId)
        }
        try self.configStore.save(self.config)
        if syncCodex {
            try self.syncService.synchronize(config: self.config)
        }
        self.publishState()
    }

    private func persistIgnoringErrors(syncCodex: Bool) {
        do {
            try self.persist(syncCodex: syncCodex)
        } catch {
            self.publishState()
        }
    }

    private func publishState() {
        _ = self.refreshOpenRouterGatewayLeaseState()
        self.pushPublishedState()
    }

    private func absorbNewerAuthJSONIfNeeded(accountID: String? = nil) -> Bool {
        let reconciled = self.configStore.reconcileAuthJSON(
            in: self.config,
            onlyAccountIDs: accountID.map { Set([$0]) }
        )
        guard reconciled.changed else { return false }
        self.config = reconciled.config
        return true
    }

    private func pushPublishedState() {
        self.accounts = self.config.oauthTokenAccounts()
        self.openRouterGatewayService.updateState(
            provider: self.config.openRouterProvider(),
            isActiveProvider: self.config.activeProvider()?.kind == .openRouter
        )
        self.reconcileOpenRouterGatewayLifecycle()
        self.lastPublishedOpenRouterSelected = self.config.activeProvider()?.kind == .openRouter
    }

    private func reconcileOpenRouterGatewayLifecycle() {
        if self.shouldRunOpenRouterGatewayListener {
            self.openRouterGatewayService.startIfNeeded()
        } else {
            self.openRouterGatewayService.stop()
        }
    }

    private var shouldRunOpenRouterGatewayListener: Bool {
        let hasActiveLease = self.openRouterGatewayLeaseSnapshot?.leasedProcessIDs.isEmpty == false
        let activeProviderIsOpenRouter = self.config.activeProvider()?.kind == .openRouter
        return self.openRouterServiceableProvider() != nil &&
            (activeProviderIsOpenRouter || hasActiveLease)
    }

    private func openRouterServiceableProvider() -> CodexBarProvider? {
        guard let provider = self.config.openRouterProvider(),
              provider.openRouterServiceableSelection != nil else {
            return nil
        }
        return provider
    }

    private func refreshOpenRouterGatewayLeaseState() -> Bool {
        let activeProviderIsOpenRouter = self.config.activeProvider()?.kind == .openRouter
        guard let provider = self.openRouterServiceableProvider() else {
            return self.clearOpenRouterGatewayLease()
        }

        if activeProviderIsOpenRouter {
            return self.clearOpenRouterGatewayLease()
        }

        let runningProcessIDs = self.codexRunningProcessIDs()
        let existingProcessIDs = self.openRouterGatewayLeaseSnapshot?.processIDs ?? []
        let shouldAcquireLease = self.lastPublishedOpenRouterSelected && runningProcessIDs.isEmpty == false

        if existingProcessIDs.isEmpty {
            guard shouldAcquireLease else {
                self.configureOpenRouterGatewayLeaseTimer()
                return false
            }
            self.openRouterGatewayLeaseSnapshot = OpenRouterGatewayLeaseSnapshot(
                processIDs: runningProcessIDs,
                sourceProviderId: provider.id
            )
            self.persistOpenRouterGatewayLeaseState()
            self.configureOpenRouterGatewayLeaseTimer()
            return true
        }

        let updatedProcessIDs = runningProcessIDs
        if updatedProcessIDs.isEmpty {
            return self.clearOpenRouterGatewayLease()
        }

        if updatedProcessIDs != existingProcessIDs {
            self.openRouterGatewayLeaseSnapshot = OpenRouterGatewayLeaseSnapshot(
                processIDs: updatedProcessIDs,
                sourceProviderId: provider.id
            )
            self.persistOpenRouterGatewayLeaseState()
            self.configureOpenRouterGatewayLeaseTimer()
            return true
        }

        self.configureOpenRouterGatewayLeaseTimer()
        return false
    }

    private func clearOpenRouterGatewayLease() -> Bool {
        let changed = self.openRouterGatewayLeaseSnapshot != nil
        self.openRouterGatewayLeaseSnapshot = nil
        self.persistOpenRouterGatewayLeaseState()
        self.configureOpenRouterGatewayLeaseTimer()
        return changed
    }

    private func persistOpenRouterGatewayLeaseState() {
        guard let lease = self.openRouterGatewayLeaseSnapshot,
              lease.leasedProcessIDs.isEmpty == false else {
            self.openRouterGatewayLeaseStore.clear()
            return
        }
        self.openRouterGatewayLeaseStore.saveLease(lease)
    }

    private func configureOpenRouterGatewayLeaseTimer() {
        let shouldPoll = self.config.activeProvider()?.kind != .openRouter &&
            self.openRouterGatewayLeaseSnapshot?.leasedProcessIDs.isEmpty == false

        if shouldPoll {
            if self.openRouterGatewayLeaseTimer == nil {
                let timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                    guard let self else { return }
                    if self.refreshOpenRouterGatewayLeaseState() {
                        self.pushPublishedState()
                    }
                }
                RunLoop.main.add(timer, forMode: .common)
                self.openRouterGatewayLeaseTimer = timer
            }
            return
        }

        self.openRouterGatewayLeaseTimer?.invalidate()
        self.openRouterGatewayLeaseTimer = nil
    }


    func refreshLocalCostSummary(
        force: Bool = false,
        minimumInterval: TimeInterval = 5 * 60
    ) {
        guard force else { return }
        if let updatedAt = self.localCostSummary.updatedAt,
           Date().timeIntervalSince(updatedAt) < minimumInterval {
            return
        }

        let service = self.costSummaryService
        let shouldStart = self.refreshStateQueue.sync { () -> Bool in
            guard self.isRefreshingLocalCostSummary == false else { return false }
            self.isRefreshingLocalCostSummary = true
            return true
        }
        guard shouldStart else { return }

        DispatchQueue.global(qos: .utility).async {
            let summary = service.load()
            DispatchQueue.main.async {
                self.localCostSummary = summary
                self.saveCachedLocalCostSummary(summary)
                self.refreshStateQueue.async {
                    self.isRefreshingLocalCostSummary = false
                }
            }
        }
    }

    private func appendSwitchJournal() throws {
        try self.appendSwitchJournal(previousAccountID: nil)
    }

    private func appendSwitchJournal(
        previousAccountID: String?,
        reason: AutoRoutingSwitchReason = .manual,
        automatic: Bool = false,
        forced: Bool = false,
        protectedByManualGrace: Bool = false
    ) throws {
        try self.switchJournalStore.appendActivation(
            providerID: self.config.active.providerId,
            accountID: self.config.active.accountId,
            previousAccountID: previousAccountID,
            reason: reason,
            automatic: automatic,
            forced: forced,
            protectedByManualGrace: protectedByManualGrace
        )
    }

    private func seedSwitchJournalIfNeeded() {
        guard FileManager.default.fileExists(atPath: CodexPaths.switchJournalURL.path) == false,
              self.config.active.providerId != nil else { return }
        try? self.appendSwitchJournal()
    }

    private func loadCachedLocalCostSummary() -> LocalCostSummary {
        guard let data = try? Data(contentsOf: CodexPaths.costCacheURL) else {
            return .empty
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(LocalCostSummary.self, from: data)) ?? .empty
    }

    private func saveCachedLocalCostSummary(_ summary: LocalCostSummary) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(summary) else { return }
        try? CodexPaths.writeSecureFile(data, to: CodexPaths.costCacheURL)
    }

    deinit {
        self.openRouterGatewayLeaseTimer?.invalidate()
    }

    private func slug(from label: String) -> String {
        let lowered = label.lowercased()
        let slug = lowered.replacingOccurrences(
            of: #"[^a-z0-9]+"#,
            with: "-",
            options: .regularExpression
        ).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let resolved = slug.isEmpty ? "provider-\(UUID().uuidString.lowercased())" : slug
        if resolved == "openrouter" {
            return "openrouter-custom"
        }
        return resolved
    }

    private func shouldSyncCodexAfterSavingSettings(
        requests: SettingsSaveRequests,
        previousActiveProviderID: String?,
        previousActiveAccountID: String?,
        updatedConfig: CodexBarConfig
    ) -> Bool {
        if let desktopRequest = requests.desktop,
           updatedConfig.active.providerId != nil {
            let scopeChanged =
                desktopRequest.accountActivationScopeMode != nil ||
                desktopRequest.accountActivationRootPaths != nil
            if scopeChanged {
                return true
            }
        }

        if let accountRequest = requests.openAIAccount,
           accountRequest.serviceTier != nil,
           updatedConfig.active.providerId != nil {
            return true
        }

        if requests.cliProxyAPI != nil,
           updatedConfig.active.providerId != nil {
            return true
        }

        if let cliProxyRequest = requests.cliProxyAPI,
           (updatedConfig.active.providerId != previousActiveProviderID ||
            updatedConfig.active.accountId != previousActiveAccountID) {
            if cliProxyRequest.enabled {
                return true
            }
            return updatedConfig.active.providerId != nil
        }

        if let cliProxyRequest = requests.cliProxyAPI,
           cliProxyRequest.enabled == false,
           (updatedConfig.active.providerId != previousActiveProviderID ||
            updatedConfig.active.accountId != previousActiveAccountID),
           updatedConfig.active.providerId != nil {
            return true
        }

        return false
    }

    private func configureDirectSelectionForEnablingAPIService(in config: inout CodexBarConfig) {
        let preAPIServiceDirectSelection = self.preAPIServiceDirectSelection(from: config)
        config.desktop.cliProxyAPI.preAPIServiceActiveProviderID = preAPIServiceDirectSelection.providerID
        config.desktop.cliProxyAPI.preAPIServiceActiveAccountID = preAPIServiceDirectSelection.accountID
        if let provider = config.oauthProvider() {
            config.active.providerId = provider.id
            config.active.accountId = provider.activeAccountId
        }
    }

    private func preAPIServiceDirectSelection(from config: CodexBarConfig) -> (providerID: String?, accountID: String?) {
        guard let activeProvider = config.activeProvider() else {
            return (nil, nil)
        }

        return (activeProvider.id, config.active.accountId ?? activeProvider.activeAccount?.id)
    }

    private func captureNativeSnapshots(
        for targets: [CodexNativeTarget],
        authURL: KeyPath<CodexNativeTarget, URL>,
        configURL: KeyPath<CodexNativeTarget, URL>
    ) -> [String: (auth: Data?, toml: Data?)] {
        targets.reduce(into: [:]) { partial, target in
            partial[target.canonicalRootPath] = (
                auth: try? Data(contentsOf: target[keyPath: authURL]),
                toml: try? Data(contentsOf: target[keyPath: configURL])
            )
        }
    }

    private func restoreNativeSnapshots(
        _ snapshots: [String: (auth: Data?, toml: Data?)],
        to targets: [CodexNativeTarget],
        authURL: KeyPath<CodexNativeTarget, URL>,
        configURL: KeyPath<CodexNativeTarget, URL>
    ) throws {
        for target in targets {
            let snapshot = snapshots[target.canonicalRootPath]
            try self.restoreNativeSnapshotData(snapshot?.auth, at: target[keyPath: authURL])
            try self.restoreNativeSnapshotData(snapshot?.toml, at: target[keyPath: configURL])
        }
    }

    private func restoreNativeSnapshotData(_ snapshot: Data?, at url: URL) throws {
        if let snapshot {
            try CodexPaths.writeSecureFile(snapshot, to: url)
        } else if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func rollbackFailedAPIServiceRoutingEnable(
        previousConfig: CodexBarConfig,
        previousDesktopSettings: CodexBarDesktopSettings,
        attemptedDesktopSettings: CodexBarDesktopSettings
    ) throws {
        _ = try self.syncService.restoreNativeConfiguration(desktopSettings: attemptedDesktopSettings)
        try self.syncService.cleanupRemovedTargets(
            previousDesktopSettings: attemptedDesktopSettings,
            currentDesktopSettings: previousDesktopSettings
        )
        try self.configStore.save(previousConfig)
        self.config = previousConfig
        self.publishState()
        self.syncCLIProxyAPIStateFromConfig()
        Task { @MainActor in
            CLIProxyAPIRuntimeController.shared.applyConfiguration(previousDesktopSettings.cliProxyAPI)
            if previousDesktopSettings.cliProxyAPI.enabled == false {
                CLIProxyAPIRuntimeController.shared.stop()
            }
        }
    }

    private static func defaultAPIServiceRoutingProbe(config: CLIProxyAPIServiceConfig) async throws {
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.timeoutIntervalForRequest = 8
        sessionConfig.timeoutIntervalForResource = 8
        let session = URLSession(configuration: sessionConfig)
        defer { session.invalidateAndCancel() }

        let request = try self.makeAPIServiceRoutingProbeRequest(config: config)
        var lastFailure: APIServiceRoutingProbeFailure?

        for attempt in 0 ..< 2 {
            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw APIServiceRoutingProbeFailure(
                        classification: .invalidResponse,
                        detail: "missing_http_response"
                    )
                }

                if (200 ... 299).contains(httpResponse.statusCode) {
                    guard self.isValidAPIServiceRoutingProbeResponse(data) else {
                        throw APIServiceRoutingProbeFailure(
                            classification: .invalidResponse,
                            detail: self.apiServiceRoutingProbeMessage(
                                data: data,
                                fallback: "missing_choices"
                            )
                        )
                    }
                    return
                }

                let failure = self.apiServiceRoutingProbeFailure(
                    statusCode: httpResponse.statusCode,
                    data: data
                )
                lastFailure = failure
                guard attempt == 0,
                      self.shouldRetryAPIServiceRoutingProbe(statusCode: httpResponse.statusCode) else {
                    throw failure
                }
                try await Task.sleep(nanoseconds: 250_000_000)
            } catch let urlError as URLError {
                let failure = self.apiServiceRoutingProbeFailure(urlError)
                lastFailure = failure
                guard attempt == 0,
                      self.shouldRetryAPIServiceRoutingProbe(urlError: urlError) else {
                    throw failure
                }
                try await Task.sleep(nanoseconds: 250_000_000)
            } catch let failure as APIServiceRoutingProbeFailure {
                throw failure
            } catch {
                throw APIServiceRoutingProbeFailure(
                    classification: .unknownProbeFailure,
                    detail: self.sanitizedAPIServiceRoutingProbeDetail(error.localizedDescription)
                )
            }
        }

        throw lastFailure ?? APIServiceRoutingProbeFailure(
            classification: .unknownProbeFailure,
            detail: "probe_exhausted_without_result"
        )
    }

    private static func makeAPIServiceRoutingProbeRequest(config: CLIProxyAPIServiceConfig) throws -> URLRequest {
        let url = config.baseURL.appendingPathComponent("v1/chat/completions")
        let body = try JSONSerialization.data(
            withJSONObject: [
                "model": "gpt-5.4-mini",
                "messages": [
                    [
                        "role": "user",
                        "content": "ping",
                    ],
                ],
                "max_tokens": 1,
                "temperature": 0,
            ],
            options: [.sortedKeys]
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(config.clientAPIKey ?? "")", forHTTPHeaderField: "Authorization")
        return request
    }

    private static func isValidAPIServiceRoutingProbeResponse(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        if object["error"] != nil {
            return false
        }
        if let choices = object["choices"] as? [Any], choices.isEmpty == false {
            return true
        }
        return object["id"] != nil
    }

    private static func apiServiceRoutingProbeFailure(
        statusCode: Int,
        data: Data
    ) -> APIServiceRoutingProbeFailure {
        let detail = self.apiServiceRoutingProbeMessage(
            data: data,
            fallback: "http_\(statusCode)"
        )

        switch statusCode {
        case 401, 403:
            return APIServiceRoutingProbeFailure(classification: .unauthorized, detail: detail)
        case 502, 503, 504:
            return APIServiceRoutingProbeFailure(classification: .upstreamUnavailable, detail: detail)
        case 400, 404, 422:
            if self.isUnsupportedAPIServiceRoutingProbeMessage(detail) {
                return APIServiceRoutingProbeFailure(classification: .unsupportedModel, detail: detail)
            }
            return APIServiceRoutingProbeFailure(classification: .invalidResponse, detail: detail)
        default:
            if self.isUnsupportedAPIServiceRoutingProbeMessage(detail) {
                return APIServiceRoutingProbeFailure(classification: .unsupportedModel, detail: detail)
            }
            return APIServiceRoutingProbeFailure(classification: .unknownProbeFailure, detail: detail)
        }
    }

    private static func apiServiceRoutingProbeFailure(_ error: URLError) -> APIServiceRoutingProbeFailure {
        switch error.code {
        case .timedOut, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .notConnectedToInternet:
            return APIServiceRoutingProbeFailure(
                classification: .connectivityFailed,
                detail: self.sanitizedAPIServiceRoutingProbeDetail(error.localizedDescription)
            )
        case .userAuthenticationRequired:
            return APIServiceRoutingProbeFailure(
                classification: .unauthorized,
                detail: self.sanitizedAPIServiceRoutingProbeDetail(error.localizedDescription)
            )
        default:
            return APIServiceRoutingProbeFailure(
                classification: .unknownProbeFailure,
                detail: self.sanitizedAPIServiceRoutingProbeDetail(error.localizedDescription)
            )
        }
    }

    private static func shouldRetryAPIServiceRoutingProbe(statusCode: Int) -> Bool {
        [502, 503, 504].contains(statusCode)
    }

    private static func shouldRetryAPIServiceRoutingProbe(urlError: URLError) -> Bool {
        switch urlError.code {
        case .timedOut, .networkConnectionLost:
            return true
        default:
            return false
        }
    }

    private static func apiServiceRoutingProbeMessage(data: Data, fallback: String) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let errorObject = object["error"] as? [String: Any] {
                if let message = errorObject["message"] as? String,
                   message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                    return self.sanitizedAPIServiceRoutingProbeDetail(message)
                }
                if let code = errorObject["code"] as? String,
                   code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                    return self.sanitizedAPIServiceRoutingProbeDetail(code)
                }
            }
            if let errorMessage = object["error"] as? String,
               errorMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                return self.sanitizedAPIServiceRoutingProbeDetail(errorMessage)
            }
            if let message = object["message"] as? String,
               message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                return self.sanitizedAPIServiceRoutingProbeDetail(message)
            }
        }

        if let rawMessage = String(data: data, encoding: .utf8),
           rawMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return self.sanitizedAPIServiceRoutingProbeDetail(rawMessage)
        }

        return fallback
    }

    private static func isUnsupportedAPIServiceRoutingProbeMessage(_ detail: String) -> Bool {
        let normalized = detail.lowercased()
        return normalized.contains("unsupported_model") ||
            normalized.contains("model_not_found") ||
            normalized.contains("unknown model") ||
            normalized.contains("unsupported model") ||
            normalized.contains("not support") ||
            (normalized.contains("model") && normalized.contains("not found"))
    }

    private func apiServiceRoutingProbeFailureSummary(_ failure: APIServiceRoutingProbeFailure) -> String {
        "\(failure.classification.rawValue): \(failure.detail)"
    }

    private func normalizeAPIServiceRoutingProbeFailure(_ error: Error) -> APIServiceRoutingProbeFailure {
        if let failure = error as? APIServiceRoutingProbeFailure {
            return failure
        }
        return APIServiceRoutingProbeFailure(
            classification: .unknownProbeFailure,
            detail: Self.sanitizedAPIServiceRoutingProbeDetail(error.localizedDescription)
        )
    }

    private static func sanitizedAPIServiceRoutingProbeDetail(_ detail: String) -> String {
        let collapsed = detail
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
        let trimmed = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 160 else { return trimmed }
        return String(trimmed.prefix(160))
    }

    private struct APIServiceRoutingProbeFailure: Error {
        var classification: APIServiceRoutingProbeFailureClass
        var detail: String
    }

    private enum APIServiceRoutingProbeFailureClass: String {
        case connectivityFailed = "connectivity_failed"
        case unauthorized = "unauthorized"
        case upstreamUnavailable = "upstream_unavailable"
        case invalidResponse = "invalid_response"
        case unsupportedModel = "unsupported_model"
        case unknownProbeFailure = "unknown_probe_failure"
    }

    private func restoreDirectSelectionAfterDisablingAPIService(in config: inout CodexBarConfig) {
        if self.restoreStoredPreAPIServiceDirectSelection(in: &config) {
            return
        }

        if config.activeProvider()?.kind == .openAIOAuth,
           config.activeAccount() != nil {
            return
        }

        if let oauthProvider = config.oauthProvider(),
           let activeOAuthAccountID = oauthProvider.activeAccountId ?? oauthProvider.accounts.first?.id {
            config.active.providerId = oauthProvider.id
            config.active.accountId = activeOAuthAccountID
        }
    }

    private func restoreStoredPreAPIServiceDirectSelection(in config: inout CodexBarConfig) -> Bool {
        guard let providerID = config.desktop.cliProxyAPI.preAPIServiceActiveProviderID,
              let providerIndex = config.providers.firstIndex(where: { $0.id == providerID }) else {
            return false
        }

        var provider = config.providers[providerIndex]
        let requestedAccountID = config.desktop.cliProxyAPI.preAPIServiceActiveAccountID
        let resolvedAccountID: String?
        if let requestedAccountID,
           provider.accounts.contains(where: { $0.id == requestedAccountID }) {
            resolvedAccountID = requestedAccountID
        } else {
            resolvedAccountID = provider.activeAccountId ?? provider.accounts.first?.id
        }

        guard let resolvedAccountID,
              provider.accounts.contains(where: { $0.id == resolvedAccountID }) else {
            return false
        }

        provider.activeAccountId = resolvedAccountID
        config.providers[providerIndex] = provider
        config.active.providerId = provider.id
        config.active.accountId = resolvedAccountID
        return true
    }
}

enum TokenStoreError: LocalizedError {
    case accountNotFound
    case providerNotFound
    case invalidInput
    case invalidCodexAppPath
    case missingAccountActivationPath
    case apiServiceRoutingProbeFailed(String)
    case apiServiceRoutingRollbackFailed(String)

    var errorDescription: String? {
        switch self {
        case .accountNotFound: return "未找到账号"
        case .providerNotFound: return "未找到 provider"
        case .invalidInput: return "输入无效"
        case .invalidCodexAppPath: return L.codexAppPathInvalidSelection
        case .missingAccountActivationPath: return L.accountActivationRootPathsRequired
        case .apiServiceRoutingProbeFailed(let detail): return L.menuAPIServiceRoutingProbeFailed(detail)
        case .apiServiceRoutingRollbackFailed(let detail): return L.menuAPIServiceRoutingRollbackFailed(detail)
        }
    }
}
