import Foundation

private struct FailableDecodable<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.value = try? container.decode(Value.self)
    }
}

private extension KeyedDecodingContainer {
    func decodeLossyStringEnum<T>(
        _ type: T.Type,
        forKey key: Key,
        default defaultValue: T
    ) throws -> T where T: RawRepresentable, T.RawValue == String {
        guard let rawValue = try self.decodeIfPresent(String.self, forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              rawValue.isEmpty == false,
              let value = T(rawValue: rawValue) else {
            return defaultValue
        }
        return value
    }
}

enum CodexBarProviderKind: String, Codable {
    case openAIOAuth = "openai_oauth"
    case openAICompatible = "openai_compatible"
    case openRouter = "openrouter"
}

enum CodexBarUsageDisplayMode: String, Codable, CaseIterable, Identifiable {
    case remaining
    case used

    var id: String { self.rawValue }

    var title: String {
        switch self {
        case .remaining:
            return L.remainingUsageDisplay
        case .used:
            return L.usedQuotaDisplay
        }
    }

    var badgeTitle: String {
        switch self {
        case .remaining:
            return L.remainingShort
        case .used:
            return L.usedShort
        }
    }
}

enum CodexBarMenuBarQuotaVisibility: String, Codable, CaseIterable, Identifiable {
    case both
    case primaryOnly
    case secondaryOnly
    case hidden

    var id: String { self.rawValue }
}

enum CodexBarMenuBarAPIServiceStatusVisibility: String, Codable, CaseIterable, Identifiable {
    case availableOverTotal
    case hidden

    var id: String { self.rawValue }
}

enum CodexBarServiceTier: String, Codable, Equatable, CaseIterable, Identifiable {
    case standard
    case fast

    var id: String { self.rawValue }

    var configValue: String? {
        switch self {
        case .standard:
            return nil
        case .fast:
            return self.rawValue
        }
    }
}

enum CodexBarAccountKind: String, Codable {
    case oauthTokens = "oauth_tokens"
    case apiKey = "api_key"
}

struct CodexBarGlobalSettings: Codable {
    var defaultModel: String
    var reviewModel: String
    var reasoningEffort: String
    var serviceTier: CodexBarServiceTier?

    init(
        defaultModel: String = "gpt-5.4",
        reviewModel: String = "gpt-5.4",
        reasoningEffort: String = "xhigh",
        serviceTier: CodexBarServiceTier? = nil
    ) {
        self.defaultModel = defaultModel
        self.reviewModel = reviewModel
        self.reasoningEffort = reasoningEffort
        self.serviceTier = serviceTier
    }
}

struct CodexBarActiveSelection: Codable, Equatable {
    var providerId: String?
    var accountId: String?
}

enum CLIProxyAPIRoutingStrategy: String, Codable, Equatable, CaseIterable, Identifiable {
    case roundRobin = "round-robin"
    case fillFirst = "fill-first"

    var id: String { self.rawValue }

    init(rawValue: String) {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "fill-first", "fillfirst", "ff":
            self = .fillFirst
        default:
            self = .roundRobin
        }
    }
}

enum CodexBarActivationScopeMode: String, Codable, Equatable, CaseIterable, Identifiable {
    case global
    case specificPaths
    case globalAndSpecificPaths

    var id: String { self.rawValue }
}

enum CodexBarUpdateCheckSchedule: String, Codable, Equatable, CaseIterable, Identifiable {
    case daily
    case weekly
    case monthly

    var id: String { self.rawValue }

    var interval: TimeInterval {
        switch self {
        case .daily:
            return 24 * 60 * 60
        case .weekly:
            return 7 * 24 * 60 * 60
        case .monthly:
            return 30 * 24 * 60 * 60
        }
    }

    var title: String {
        switch self {
        case .daily:
            return L.updateScheduleDaily
        case .weekly:
            return L.updateScheduleWeekly
        case .monthly:
            return L.updateScheduleMonthly
        }
    }
}

struct CodexBarDesktopSettings: Codable, Equatable {
    struct ManagedUpdateSettings: Codable, Equatable {
        var automaticallyChecksForUpdates: Bool
        var automaticallyInstallsUpdates: Bool
        var checkSchedule: CodexBarUpdateCheckSchedule

        enum CodingKeys: String, CodingKey {
            case automaticallyChecksForUpdates
            case automaticallyInstallsUpdates
            case checkSchedule
        }

        init(
            automaticallyChecksForUpdates: Bool,
            automaticallyInstallsUpdates: Bool,
            checkSchedule: CodexBarUpdateCheckSchedule = .daily
        ) {
            self.automaticallyChecksForUpdates = automaticallyChecksForUpdates
            self.automaticallyInstallsUpdates = automaticallyInstallsUpdates
            self.checkSchedule = checkSchedule
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.automaticallyChecksForUpdates =
                try container.decodeIfPresent(Bool.self, forKey: .automaticallyChecksForUpdates) ?? false
            self.automaticallyInstallsUpdates =
                try container.decodeIfPresent(Bool.self, forKey: .automaticallyInstallsUpdates) ?? false
            self.checkSchedule =
                try container.decodeLossyStringEnum(
                    CodexBarUpdateCheckSchedule.self,
                    forKey: .checkSchedule,
                    default: .daily
                )
        }

        static var codexkitDefault: Self {
            Self(
                automaticallyChecksForUpdates: true,
                automaticallyInstallsUpdates: false,
                checkSchedule: .daily
            )
        }

        static var cliProxyAPIDefault: Self {
            Self(
                automaticallyChecksForUpdates: false,
                automaticallyInstallsUpdates: false,
                checkSchedule: .daily
            )
        }
    }

    struct AccountActivationScope: Codable, Equatable {
        var mode: CodexBarActivationScopeMode
        var rootPaths: [String]

        enum CodingKeys: String, CodingKey {
            case mode
            case rootPaths
        }

        init(
            mode: CodexBarActivationScopeMode = .global,
            rootPaths: [String] = []
        ) {
            self.mode = mode
            self.rootPaths = Self.normalizedRootPaths(rootPaths)
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.mode = try container.decodeLossyStringEnum(
                CodexBarActivationScopeMode.self,
                forKey: .mode,
                default: .global
            )
            self.rootPaths = Self.normalizedRootPaths(
                try container.decodeIfPresent([String].self, forKey: .rootPaths) ?? []
            )
        }

        private static func normalizedRootPaths(_ paths: [String]) -> [String] {
            var normalized: [String] = []
            var seen: Set<String> = []

            for rawPath in paths {
                let path = NSString(
                    string: NSString(string: rawPath.trimmingCharacters(in: .whitespacesAndNewlines))
                        .expandingTildeInPath
                ).standardizingPath
                guard path.isEmpty == false else { continue }
                guard seen.insert(path).inserted else { continue }
                normalized.append(path)
            }

            return normalized
        }
    }

    struct CLIProxyAPISettings: Codable, Equatable {
        var enabled: Bool
        var host: String
        var port: Int
        // Legacy compatibility only. External CPA import sources are not persisted
        // as runtime inputs anymore, so this field is always normalized to nil.
        var repositoryRootPath: String?
        var managementSecretKey: String?
        var clientAPIKey: String?
        var preAPIServiceActiveProviderID: String?
        var preAPIServiceActiveAccountID: String?
        var memberAccountIDs: [String]
        var restrictFreeAccounts: Bool
        var routingStrategy: CLIProxyAPIRoutingStrategy
        var switchProjectOnQuotaExceeded: Bool
        var switchPreviewModelOnQuotaExceeded: Bool
        var requestRetry: Int
        var maxRetryInterval: Int
        var disableCooling: Bool
        var memberPrioritiesByAccountID: [String: Int]

        enum CodingKeys: String, CodingKey {
            case enabled
            case host
            case port
            case repositoryRootPath
            case managementSecretKey
            case clientAPIKey
            case preAPIServiceActiveProviderID
            case preAPIServiceActiveAccountID
            case memberAccountIDs
            case restrictFreeAccounts
            case routingStrategy
            case switchProjectOnQuotaExceeded
            case switchPreviewModelOnQuotaExceeded
            case requestRetry
            case maxRetryInterval
            case disableCooling
            case memberPrioritiesByAccountID
        }

        init(
            enabled: Bool = false,
            host: String = CLIProxyAPIService.defaultHost,
            port: Int = 8317,
            repositoryRootPath: String? = nil,
            managementSecretKey: String? = nil,
            clientAPIKey: String? = nil,
            preAPIServiceActiveProviderID: String? = nil,
            preAPIServiceActiveAccountID: String? = nil,
            memberAccountIDs: [String] = [],
            restrictFreeAccounts: Bool = true,
            routingStrategy: CLIProxyAPIRoutingStrategy = .roundRobin,
            switchProjectOnQuotaExceeded: Bool = true,
            switchPreviewModelOnQuotaExceeded: Bool = true,
            requestRetry: Int = 3,
            maxRetryInterval: Int = 30,
            disableCooling: Bool = false,
            memberPrioritiesByAccountID: [String: Int] = [:]
        ) {
            self.enabled = enabled
            self.host = Self.normalizedHost(host)
            self.port = max(1, port)
            self.repositoryRootPath = nil
            self.managementSecretKey = Self.normalizedSecret(managementSecretKey)
            self.clientAPIKey = Self.normalizedSecret(clientAPIKey)
            self.preAPIServiceActiveProviderID = Self.normalizedIdentifier(preAPIServiceActiveProviderID)
            self.preAPIServiceActiveAccountID = Self.normalizedIdentifier(preAPIServiceActiveAccountID)
            self.memberAccountIDs = Array(Set(memberAccountIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
            self.restrictFreeAccounts = restrictFreeAccounts
            self.routingStrategy = routingStrategy
            self.switchProjectOnQuotaExceeded = switchProjectOnQuotaExceeded
            self.switchPreviewModelOnQuotaExceeded = switchPreviewModelOnQuotaExceeded
            self.requestRetry = max(0, requestRetry)
            self.maxRetryInterval = max(0, maxRetryInterval)
            self.disableCooling = disableCooling
            self.memberPrioritiesByAccountID = Self.normalizedPriorities(memberPrioritiesByAccountID)
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
            self.host = Self.normalizedHost(
                try container.decodeIfPresent(String.self, forKey: .host) ?? CLIProxyAPIService.defaultHost
            )
            self.port = max(1, try container.decodeIfPresent(Int.self, forKey: .port) ?? 8317)
            self.repositoryRootPath = nil
            let normalizedManagementSecret = Self.normalizedSecret(
                try container.decodeIfPresent(String.self, forKey: .managementSecretKey)
            )
            self.managementSecretKey = normalizedManagementSecret
            self.clientAPIKey = Self.resolvedClientAPIKey(
                try container.decodeIfPresent(String.self, forKey: .clientAPIKey),
                managementSecretKey: normalizedManagementSecret
            )
            self.preAPIServiceActiveProviderID = Self.normalizedIdentifier(
                try container.decodeIfPresent(String.self, forKey: .preAPIServiceActiveProviderID)
            )
            self.preAPIServiceActiveAccountID = Self.normalizedIdentifier(
                try container.decodeIfPresent(String.self, forKey: .preAPIServiceActiveAccountID)
            )
            self.memberAccountIDs = Array(Set((try container.decodeIfPresent([String].self, forKey: .memberAccountIDs) ?? [])
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty })).sorted()
            self.restrictFreeAccounts = try container.decodeIfPresent(Bool.self, forKey: .restrictFreeAccounts) ?? true
            self.routingStrategy = CLIProxyAPIRoutingStrategy(
                rawValue: try container.decodeIfPresent(String.self, forKey: .routingStrategy) ?? CLIProxyAPIRoutingStrategy.roundRobin.rawValue
            )
            self.switchProjectOnQuotaExceeded = try container.decodeIfPresent(Bool.self, forKey: .switchProjectOnQuotaExceeded) ?? true
            self.switchPreviewModelOnQuotaExceeded = try container.decodeIfPresent(Bool.self, forKey: .switchPreviewModelOnQuotaExceeded) ?? true
            self.requestRetry = max(0, try container.decodeIfPresent(Int.self, forKey: .requestRetry) ?? 3)
            self.maxRetryInterval = max(0, try container.decodeIfPresent(Int.self, forKey: .maxRetryInterval) ?? 30)
            self.disableCooling = try container.decodeIfPresent(Bool.self, forKey: .disableCooling) ?? false
            self.memberPrioritiesByAccountID = Self.normalizedPriorities(
                try container.decodeIfPresent([String: Int].self, forKey: .memberPrioritiesByAccountID) ?? [:]
            )
        }

        private static func normalizedHost(_ host: String?) -> String {
            let trimmed = host?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? CLIProxyAPIService.defaultHost : trimmed
        }

        private static func normalizedSecret(_ secret: String?) -> String? {
            guard let trimmed = secret?.trimmingCharacters(in: .whitespacesAndNewlines),
                  trimmed.isEmpty == false else {
                return nil
            }
            return trimmed
        }

        private static func normalizedIdentifier(_ identifier: String?) -> String? {
            guard let trimmed = identifier?.trimmingCharacters(in: .whitespacesAndNewlines),
                  trimmed.isEmpty == false else {
                return nil
            }
            return trimmed
        }

        private static func resolvedClientAPIKey(
            _ clientAPIKey: String?,
            managementSecretKey: String?
        ) -> String {
            if let normalizedClientAPIKey = Self.normalizedSecret(clientAPIKey) {
                return normalizedClientAPIKey
            }

            var generatedClientAPIKey = CLIProxyAPIService.shared.generateClientAPIKey()
            while generatedClientAPIKey == managementSecretKey {
                generatedClientAPIKey = CLIProxyAPIService.shared.generateClientAPIKey()
            }
            return generatedClientAPIKey
        }

        private static func normalizedPriorities(_ priorities: [String: Int]) -> [String: Int] {
            priorities.reduce(into: [:]) { partial, entry in
                let key = entry.key.trimmingCharacters(in: .whitespacesAndNewlines)
                guard key.isEmpty == false else { return }
                partial[key] = max(0, entry.value)
            }
        }
    }

    var preferredCodexAppPath: String?
    var accountActivationScope: AccountActivationScope
    var cliProxyAPI: CLIProxyAPISettings
    var codexkitUpdate: ManagedUpdateSettings
    var cliProxyAPIUpdate: ManagedUpdateSettings

    enum CodingKeys: String, CodingKey {
        case preferredCodexAppPath
        case accountActivationScope
        case cliProxyAPI
        case codexkitUpdate
        case cliProxyAPIUpdate
    }

    init(
        preferredCodexAppPath: String? = nil,
        accountActivationScope: AccountActivationScope = AccountActivationScope(),
        cliProxyAPI: CLIProxyAPISettings = CLIProxyAPISettings(),
        codexkitUpdate: ManagedUpdateSettings = .codexkitDefault,
        cliProxyAPIUpdate: ManagedUpdateSettings = .cliProxyAPIDefault
    ) {
        self.preferredCodexAppPath = Self.normalizedPreferredCodexAppPath(preferredCodexAppPath)
        self.accountActivationScope = accountActivationScope
        self.cliProxyAPI = cliProxyAPI
        self.codexkitUpdate = codexkitUpdate
        self.cliProxyAPIUpdate = cliProxyAPIUpdate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.preferredCodexAppPath = Self.normalizedPreferredCodexAppPath(
            try container.decodeIfPresent(String.self, forKey: .preferredCodexAppPath)
        )
        self.accountActivationScope = try container.decodeIfPresent(AccountActivationScope.self, forKey: .accountActivationScope)
            ?? AccountActivationScope()
        self.cliProxyAPI = try container.decodeIfPresent(CLIProxyAPISettings.self, forKey: .cliProxyAPI) ?? CLIProxyAPISettings()
        self.codexkitUpdate = try container.decodeIfPresent(ManagedUpdateSettings.self, forKey: .codexkitUpdate)
            ?? .codexkitDefault
        self.cliProxyAPIUpdate = try container.decodeIfPresent(ManagedUpdateSettings.self, forKey: .cliProxyAPIUpdate)
            ?? .cliProxyAPIDefault
    }

    private static func normalizedPreferredCodexAppPath(_ path: String?) -> String? {
        guard let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmed.isEmpty == false else {
            return nil
        }
        return trimmed
    }
}

enum CodexBarOpenAIManualActivationBehavior: String, Codable, CaseIterable, Identifiable {
    case updateConfigOnly
    case launchNewInstance

    var id: String { self.rawValue }
}

enum CodexBarOpenAIAccountOrderingMode: String, Codable, CaseIterable, Identifiable {
    case quotaSort
    case manual

    var id: String { self.rawValue }
}

struct CodexBarOpenAISettings: Codable, Equatable {
    struct MenuBarDisplaySettings: Codable, Equatable {
        var quotaVisibility: CodexBarMenuBarQuotaVisibility
        var apiServiceStatusVisibility: CodexBarMenuBarAPIServiceStatusVisibility

        enum CodingKeys: String, CodingKey {
            case quotaVisibility
            case apiServiceStatusVisibility
        }

        init(
            quotaVisibility: CodexBarMenuBarQuotaVisibility = .both,
            apiServiceStatusVisibility: CodexBarMenuBarAPIServiceStatusVisibility = .availableOverTotal
        ) {
            self.quotaVisibility = quotaVisibility
            self.apiServiceStatusVisibility = apiServiceStatusVisibility
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.quotaVisibility = try container.decodeLossyStringEnum(
                CodexBarMenuBarQuotaVisibility.self,
                forKey: .quotaVisibility,
                default: .both
            )
            self.apiServiceStatusVisibility = try container.decodeLossyStringEnum(
                CodexBarMenuBarAPIServiceStatusVisibility.self,
                forKey: .apiServiceStatusVisibility,
                default: .availableOverTotal
            )
        }
    }

    struct QuotaSortSettings: Codable, Equatable {
        static let plusRelativeWeightRange = 1.0...20.0
        static let proRelativeToPlusRange = 5.0...30.0
        static let teamRelativeToPlusRange = 1.0...3.0

        var plusRelativeWeight: Double
        var proRelativeToPlusMultiplier: Double
        var teamRelativeToPlusMultiplier: Double

        enum CodingKeys: String, CodingKey {
            case plusRelativeWeight
            case proRelativeToPlusMultiplier
            case teamRelativeToPlusMultiplier
        }

        nonisolated init(
            plusRelativeWeight: Double = 10,
            proRelativeToPlusMultiplier: Double = 10,
            teamRelativeToPlusMultiplier: Double = 1.5
        ) {
            self.plusRelativeWeight = Self.clamped(
                plusRelativeWeight,
                to: Self.plusRelativeWeightRange
            )
            self.proRelativeToPlusMultiplier = Self.clamped(
                proRelativeToPlusMultiplier,
                to: Self.proRelativeToPlusRange
            )
            self.teamRelativeToPlusMultiplier = Self.clamped(
                teamRelativeToPlusMultiplier,
                to: Self.teamRelativeToPlusRange
            )
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                plusRelativeWeight: try container.decodeIfPresent(Double.self, forKey: .plusRelativeWeight) ?? 10,
                proRelativeToPlusMultiplier: try container.decodeIfPresent(Double.self, forKey: .proRelativeToPlusMultiplier) ?? 10,
                teamRelativeToPlusMultiplier: try container.decodeIfPresent(Double.self, forKey: .teamRelativeToPlusMultiplier) ?? 1.5
            )
        }

        nonisolated var proAbsoluteWeight: Double {
            self.plusRelativeWeight * self.proRelativeToPlusMultiplier
        }

        nonisolated var teamAbsoluteWeight: Double {
            self.plusRelativeWeight * self.teamRelativeToPlusMultiplier
        }

        nonisolated private static func clamped(_ value: Double, to range: ClosedRange<Double>) -> Double {
            min(max(value, range.lowerBound), range.upperBound)
        }
    }

    var accountOrder: [String]
    var accountOrderingMode: CodexBarOpenAIAccountOrderingMode
    var manualActivationBehavior: CodexBarOpenAIManualActivationBehavior
    var usageDisplayMode: CodexBarUsageDisplayMode
    var menuBarDisplay: MenuBarDisplaySettings
    var quotaSort: QuotaSortSettings

    enum CodingKeys: String, CodingKey {
        case accountOrder
        case accountOrderingMode
        case manualActivationBehavior
        case usageDisplayMode
        case menuBarDisplay
        case quotaSort
    }

    init(
        accountOrder: [String] = [],
        accountOrderingMode: CodexBarOpenAIAccountOrderingMode = .quotaSort,
        manualActivationBehavior: CodexBarOpenAIManualActivationBehavior = .updateConfigOnly,
        usageDisplayMode: CodexBarUsageDisplayMode = .used,
        menuBarDisplay: MenuBarDisplaySettings = MenuBarDisplaySettings(),
        quotaSort: QuotaSortSettings = QuotaSortSettings()
    ) {
        self.accountOrder = accountOrder
        self.accountOrderingMode = accountOrderingMode
        self.manualActivationBehavior = manualActivationBehavior
        self.usageDisplayMode = usageDisplayMode
        self.menuBarDisplay = menuBarDisplay
        self.quotaSort = quotaSort
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.accountOrder = try container.decodeIfPresent([String].self, forKey: .accountOrder) ?? []
        self.accountOrderingMode = try container.decodeLossyStringEnum(
            CodexBarOpenAIAccountOrderingMode.self,
            forKey: .accountOrderingMode,
            default: .quotaSort
        )
        self.manualActivationBehavior = try container.decodeLossyStringEnum(
            CodexBarOpenAIManualActivationBehavior.self,
            forKey: .manualActivationBehavior,
            default: .updateConfigOnly
        )
        self.usageDisplayMode = try container.decodeLossyStringEnum(
            CodexBarUsageDisplayMode.self,
            forKey: .usageDisplayMode,
            default: .used
        )
        self.menuBarDisplay = try container.decodeIfPresent(MenuBarDisplaySettings.self, forKey: .menuBarDisplay) ?? MenuBarDisplaySettings()
        self.quotaSort = try container.decodeIfPresent(QuotaSortSettings.self, forKey: .quotaSort) ?? QuotaSortSettings()
    }

    var preferredDisplayAccountOrder: [String] {
        self.accountOrderingMode == .manual ? self.accountOrder : []
    }
}

struct CodexBarProviderAccount: Codable, Identifiable, Equatable {
    var id: String
    var kind: CodexBarAccountKind
    var label: String

    var email: String?
    var openAIAccountId: String?
    var accessToken: String?
    var refreshToken: String?
    var idToken: String?
    var expiresAt: Date?
    var oauthClientID: String?
    var tokenLastRefreshAt: Date?
    var lastRefresh: Date?

    var apiKey: String?
    var addedAt: Date?

    // Runtime quota snapshot for OAuth accounts.
    var planType: String?
    var primaryUsedPercent: Double?
    var secondaryUsedPercent: Double?
    var primaryResetAt: Date?
    var secondaryResetAt: Date?
    var primaryLimitWindowSeconds: Int?
    var secondaryLimitWindowSeconds: Int?
    var lastChecked: Date?
    var isSuspended: Bool?
    var tokenExpired: Bool?
    var organizationName: String?

    init(
        id: String = UUID().uuidString,
        kind: CodexBarAccountKind,
        label: String,
        email: String? = nil,
        openAIAccountId: String? = nil,
        accessToken: String? = nil,
        refreshToken: String? = nil,
        idToken: String? = nil,
        expiresAt: Date? = nil,
        oauthClientID: String? = nil,
        tokenLastRefreshAt: Date? = nil,
        lastRefresh: Date? = nil,
        apiKey: String? = nil,
        addedAt: Date? = nil,
        planType: String? = nil,
        primaryUsedPercent: Double? = nil,
        secondaryUsedPercent: Double? = nil,
        primaryResetAt: Date? = nil,
        secondaryResetAt: Date? = nil,
        primaryLimitWindowSeconds: Int? = nil,
        secondaryLimitWindowSeconds: Int? = nil,
        lastChecked: Date? = nil,
        isSuspended: Bool? = nil,
        tokenExpired: Bool? = nil,
        organizationName: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.email = email
        self.openAIAccountId = openAIAccountId
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.idToken = idToken
        self.expiresAt = expiresAt
        self.oauthClientID = oauthClientID
        self.tokenLastRefreshAt = tokenLastRefreshAt
        self.lastRefresh = lastRefresh
        self.apiKey = apiKey
        self.addedAt = addedAt
        self.planType = planType
        self.primaryUsedPercent = primaryUsedPercent
        self.secondaryUsedPercent = secondaryUsedPercent
        self.primaryResetAt = primaryResetAt
        self.secondaryResetAt = secondaryResetAt
        self.primaryLimitWindowSeconds = primaryLimitWindowSeconds
        self.secondaryLimitWindowSeconds = secondaryLimitWindowSeconds
        self.lastChecked = lastChecked
        self.isSuspended = isSuspended
        self.tokenExpired = tokenExpired
        self.organizationName = organizationName
    }

    var maskedAPIKey: String {
        guard let apiKey, apiKey.count > 8 else { return apiKey ?? "" }
        return String(apiKey.prefix(6)) + "..." + String(apiKey.suffix(4))
    }

    func asTokenAccount(isActive: Bool) -> TokenAccount? {
        self.rawTokenAccount(isActive: isActive)?.normalizedQuotaSnapshot()
    }

    func sanitizedQuotaSnapshot(now: Date = Date()) -> CodexBarProviderAccount {
        guard let normalized = self.rawTokenAccount(isActive: false)?.normalizedQuotaSnapshot(now: now) else {
            return self
        }

        var sanitized = self
        sanitized.planType = normalized.planType
        sanitized.primaryUsedPercent = normalized.primaryUsedPercent
        sanitized.secondaryUsedPercent = normalized.secondaryUsedPercent
        sanitized.primaryResetAt = normalized.primaryResetAt
        sanitized.secondaryResetAt = normalized.secondaryResetAt
        sanitized.primaryLimitWindowSeconds = normalized.primaryLimitWindowSeconds
        sanitized.secondaryLimitWindowSeconds = normalized.secondaryLimitWindowSeconds
        sanitized.lastChecked = normalized.lastChecked
        sanitized.isSuspended = normalized.isSuspended
        sanitized.tokenExpired = normalized.tokenExpired
        sanitized.organizationName = normalized.organizationName
        return sanitized
    }

    private func rawTokenAccount(isActive: Bool) -> TokenAccount? {
        guard self.kind == .oauthTokens,
              let accessToken = self.accessToken,
              let refreshToken = self.refreshToken,
              let idToken = self.idToken else { return nil }

        let localAccountID = self.id
        let remoteAccountID = self.openAIAccountId ?? localAccountID

        return TokenAccount(
            email: self.email ?? self.label,
            accountId: localAccountID,
            openAIAccountId: remoteAccountID,
            accessToken: accessToken,
            refreshToken: refreshToken,
            idToken: idToken,
            expiresAt: self.expiresAt,
            oauthClientID: self.oauthClientID,
            planType: self.planType ?? "free",
            primaryUsedPercent: self.primaryUsedPercent ?? 0,
            secondaryUsedPercent: self.secondaryUsedPercent ?? 0,
            primaryResetAt: self.primaryResetAt,
            secondaryResetAt: self.secondaryResetAt,
            primaryLimitWindowSeconds: self.primaryLimitWindowSeconds,
            secondaryLimitWindowSeconds: self.secondaryLimitWindowSeconds,
            lastChecked: self.lastChecked,
            isActive: isActive,
            isSuspended: self.isSuspended ?? false,
            tokenExpired: self.tokenExpired ?? false,
            tokenLastRefreshAt: self.tokenLastRefreshAt ?? self.lastRefresh,
            organizationName: self.organizationName
        )
    }

    static func fromTokenAccount(_ account: TokenAccount, existingID: String? = nil) -> CodexBarProviderAccount {
        let normalizedAccount = account.normalizedQuotaSnapshot()
        return CodexBarProviderAccount(
            id: existingID ?? normalizedAccount.accountId,
            kind: .oauthTokens,
            label: normalizedAccount.email.isEmpty ? normalizedAccount.accountId : normalizedAccount.email,
            email: normalizedAccount.email,
            openAIAccountId: normalizedAccount.remoteAccountId,
            accessToken: normalizedAccount.accessToken,
            refreshToken: normalizedAccount.refreshToken,
            idToken: normalizedAccount.idToken,
            expiresAt: normalizedAccount.expiresAt,
            oauthClientID: normalizedAccount.oauthClientID,
            tokenLastRefreshAt: normalizedAccount.tokenLastRefreshAt,
            lastRefresh: normalizedAccount.tokenLastRefreshAt,
            addedAt: Date(),
            planType: normalizedAccount.planType,
            primaryUsedPercent: normalizedAccount.primaryUsedPercent,
            secondaryUsedPercent: normalizedAccount.secondaryUsedPercent,
            primaryResetAt: normalizedAccount.primaryResetAt,
            secondaryResetAt: normalizedAccount.secondaryResetAt,
            primaryLimitWindowSeconds: normalizedAccount.primaryLimitWindowSeconds,
            secondaryLimitWindowSeconds: normalizedAccount.secondaryLimitWindowSeconds,
            lastChecked: normalizedAccount.lastChecked,
            isSuspended: normalizedAccount.isSuspended,
            tokenExpired: normalizedAccount.tokenExpired,
            organizationName: normalizedAccount.organizationName
        )
    }
}

struct CodexBarOpenRouterModel: Codable, Equatable, Identifiable {
    var id: String
    var name: String

    init(id: String, name: String? = nil) {
        let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = normalizedID
        self.name = normalizedName?.isEmpty == false ? normalizedName! : normalizedID
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            name: try container.decodeIfPresent(String.self, forKey: .name)
        )
    }
}

struct CodexBarProvider: Codable, Identifiable, Equatable {
    var id: String
    var kind: CodexBarProviderKind
    var label: String
    var enabled: Bool
    var baseURL: String?
    var defaultModel: String?
    var selectedModelID: String?
    var pinnedModelIDs: [String]
    var cachedModelCatalog: [CodexBarOpenRouterModel]
    var modelCatalogFetchedAt: Date?
    var activeAccountId: String?
    var accounts: [CodexBarProviderAccount]

    init(
        id: String,
        kind: CodexBarProviderKind,
        label: String,
        enabled: Bool = true,
        baseURL: String? = nil,
        defaultModel: String? = nil,
        selectedModelID: String? = nil,
        pinnedModelIDs: [String] = [],
        cachedModelCatalog: [CodexBarOpenRouterModel] = [],
        modelCatalogFetchedAt: Date? = nil,
        activeAccountId: String? = nil,
        accounts: [CodexBarProviderAccount] = []
    ) {
        let normalizedDefaultModel = Self.normalizedDefaultModel(defaultModel)
        let normalizedSelectedModelID = Self.normalizedOpenRouterModelID(selectedModelID) ?? normalizedDefaultModel
        let normalizedPinnedModelIDs = Self.normalizedOpenRouterModelIDs(pinnedModelIDs)
        let resolvedPinnedModelIDs = Self.resolvedPinnedModelIDs(
            normalizedPinnedModelIDs,
            selectedModelID: normalizedSelectedModelID
        )
        self.id = id
        self.kind = kind
        self.label = label
        self.enabled = enabled
        self.baseURL = baseURL
        self.defaultModel = kind == .openRouter ? nil : normalizedDefaultModel
        self.selectedModelID = normalizedSelectedModelID
        self.pinnedModelIDs = resolvedPinnedModelIDs
        self.cachedModelCatalog = cachedModelCatalog
        self.modelCatalogFetchedAt = modelCatalogFetchedAt
        self.activeAccountId = activeAccountId
        self.accounts = accounts
    }

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case label
        case enabled
        case baseURL
        case defaultModel
        case selectedModelID
        case pinnedModelIDs
        case cachedModelCatalog
        case modelCatalogFetchedAt
        case activeAccountId
        case accounts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedKind = try container.decode(CodexBarProviderKind.self, forKey: .kind)
        let decodedDefaultModel = Self.normalizedDefaultModel(
            try container.decodeIfPresent(String.self, forKey: .defaultModel)
        )
        let decodedSelectedModelID = Self.normalizedOpenRouterModelID(
            try container.decodeIfPresent(String.self, forKey: .selectedModelID)
        ) ?? decodedDefaultModel
        let decodedPinnedModelIDs = Self.resolvedPinnedModelIDs(
            Self.normalizedOpenRouterModelIDs(
                try container.decodeIfPresent([String].self, forKey: .pinnedModelIDs) ?? []
            ),
            selectedModelID: decodedSelectedModelID
        )
        self.id = try container.decode(String.self, forKey: .id)
        self.kind = decodedKind
        self.label = try container.decode(String.self, forKey: .label)
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        self.baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL)
        self.defaultModel = decodedKind == .openRouter ? nil : decodedDefaultModel
        self.selectedModelID = decodedSelectedModelID
        self.pinnedModelIDs = decodedPinnedModelIDs
        self.cachedModelCatalog = try container.decodeIfPresent([CodexBarOpenRouterModel].self, forKey: .cachedModelCatalog) ?? []
        self.modelCatalogFetchedAt = try container.decodeIfPresent(Date.self, forKey: .modelCatalogFetchedAt)
        self.activeAccountId = try container.decodeIfPresent(String.self, forKey: .activeAccountId)
        self.accounts = (try container.decodeIfPresent(
            [FailableDecodable<CodexBarProviderAccount>].self,
            forKey: .accounts
        ) ?? []).compactMap(\.value)
    }

    var activeAccount: CodexBarProviderAccount? {
        if let activeAccountId, let found = self.accounts.first(where: { $0.id == activeAccountId }) {
            return found
        }
        return self.accounts.first
    }

    var hostLabel: String {
        if self.kind == .openRouter {
            return "openrouter.ai"
        }
        guard let baseURL,
              let host = URL(string: baseURL)?.host,
              !host.isEmpty else { return self.label }
        return host
    }

    var baseURLBadgeLabel: String {
        guard self.kind != .openRouter else { return "openrouter.ai" }
        guard let baseURL,
              let url = URL(string: baseURL),
              let host = url.host,
              host.isEmpty == false else {
            return self.label
        }

        let normalizedPath = url.path
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard normalizedPath.isEmpty == false else {
            return host
        }

        let pathSegments = normalizedPath
            .split(separator: "/")
            .map(String.init)
        if pathSegments == ["v1"] {
            return host
        }

        return "\(host)/\(pathSegments.joined(separator: "/"))"
    }

    var usesAPIKeyAuth: Bool {
        self.kind == .openAICompatible || self.kind == .openRouter
    }

    var openRouterEffectiveModelID: String? {
        guard self.kind == .openRouter else { return nil }
        return Self.normalizedOpenRouterModelID(self.selectedModelID)
    }

    var openRouterServiceableSelection: (account: CodexBarProviderAccount, modelID: String)? {
        guard self.kind == .openRouter,
              let account = self.activeAccount,
              let apiKey = account.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              apiKey.isEmpty == false,
              let modelID = self.openRouterEffectiveModelID?.trimmingCharacters(in: .whitespacesAndNewlines),
              modelID.isEmpty == false else {
            return nil
        }
        return (account, modelID)
    }

    fileprivate static func normalizedDefaultModel(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmed.isEmpty == false else {
            return nil
        }
        return trimmed
    }

    fileprivate static func normalizedOpenRouterModelID(_ value: String?) -> String? {
        self.normalizedDefaultModel(value)
    }

    static func normalizedOpenRouterModelIDs(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.compactMap { value in
            guard let normalized = self.normalizedOpenRouterModelID(value),
                  seen.insert(normalized).inserted else {
                return nil
            }
            return normalized
        }
    }

    static func resolvedPinnedModelIDs(
        _ pinnedModelIDs: [String],
        selectedModelID: String?
    ) -> [String] {
        var normalized = self.normalizedOpenRouterModelIDs(pinnedModelIDs)
        if let selectedModelID = self.normalizedOpenRouterModelID(selectedModelID),
           normalized.contains(selectedModelID) == false {
            normalized.insert(selectedModelID, at: 0)
        }
        return normalized
    }
}

struct CodexBarConfig: Codable {
    var version: Int
    var global: CodexBarGlobalSettings
    var active: CodexBarActiveSelection
    var desktop: CodexBarDesktopSettings
    var openAI: CodexBarOpenAISettings
    var providers: [CodexBarProvider]

    init(
        version: Int = 1,
        global: CodexBarGlobalSettings = CodexBarGlobalSettings(),
        active: CodexBarActiveSelection = CodexBarActiveSelection(),
        desktop: CodexBarDesktopSettings = CodexBarDesktopSettings(),
        openAI: CodexBarOpenAISettings = CodexBarOpenAISettings(),
        providers: [CodexBarProvider] = []
    ) {
        self.version = version
        self.global = global
        self.active = active
        self.desktop = desktop
        self.openAI = openAI
        self.providers = providers
    }

    enum CodingKeys: String, CodingKey {
        case version
        case global
        case active
        case desktop
        case openAI
        case providers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        self.global = try container.decodeIfPresent(CodexBarGlobalSettings.self, forKey: .global) ?? CodexBarGlobalSettings()
        self.active = try container.decodeIfPresent(CodexBarActiveSelection.self, forKey: .active) ?? CodexBarActiveSelection()
        self.desktop = try container.decodeIfPresent(CodexBarDesktopSettings.self, forKey: .desktop) ?? CodexBarDesktopSettings()
        self.openAI = try container.decodeIfPresent(CodexBarOpenAISettings.self, forKey: .openAI) ?? CodexBarOpenAISettings()
        self.providers = (try container.decodeIfPresent(
            [FailableDecodable<CodexBarProvider>].self,
            forKey: .providers
        ) ?? []).compactMap(\.value)
    }

    func provider(id: String?) -> CodexBarProvider? {
        guard let id else { return nil }
        return self.providers.first(where: { $0.id == id })
    }

    func activeProvider() -> CodexBarProvider? {
        self.provider(id: self.active.providerId)
    }

    func activeAccount() -> CodexBarProviderAccount? {
        self.activeProvider()?.accounts.first(where: { $0.id == self.active.accountId }) ?? self.activeProvider()?.activeAccount
    }

    func oauthProvider() -> CodexBarProvider? {
        self.providers.first(where: { $0.kind == .openAIOAuth })
    }

    func openRouterProvider() -> CodexBarProvider? {
        self.providers.first(where: { $0.kind == .openRouter })
    }
}

extension CodexBarConfig {
    mutating func upsertOAuthAccount(_ account: TokenAccount, activate: Bool) -> (storedAccount: CodexBarProviderAccount, syncCodex: Bool) {
        var provider = self.ensureOAuthProvider()
        let existingStoredAccount = provider.accounts.first(where: { $0.id == account.accountId })
        let storedAccountID: String

        if let index = provider.accounts.firstIndex(where: { $0.id == account.accountId }) {
            let existing = provider.accounts[index]
            var updated = CodexBarProviderAccount.fromTokenAccount(account, existingID: existing.id)
            updated.addedAt = existing.addedAt ?? Date()
            updated.label = existing.label
            updated.expiresAt = updated.expiresAt ?? existing.expiresAt
            updated.oauthClientID = updated.oauthClientID ?? existing.oauthClientID
            updated.tokenLastRefreshAt = updated.tokenLastRefreshAt ?? existing.tokenLastRefreshAt ?? existing.lastRefresh
            updated.lastRefresh = updated.tokenLastRefreshAt ?? existing.lastRefresh
            provider.accounts[index] = updated
            storedAccountID = updated.id
        } else {
            let created = CodexBarProviderAccount.fromTokenAccount(account, existingID: account.accountId)
            provider.accounts.append(created)
            storedAccountID = created.id
            self.appendOpenAIAccountOrderIfNeeded(accountID: created.id)
        }

        if provider.activeAccountId == nil {
            provider.activeAccountId = storedAccountID
        }

        if activate {
            provider.activeAccountId = storedAccountID
            self.active.providerId = provider.id
            self.active.accountId = storedAccountID
        }

        self.upsertProvider(provider)
        _ = self.normalizeSharedOpenAITeamOrganizationNames()
        self.normalizeOpenAIAccountOrder()

        let storedAccount = self.oauthProvider()?.accounts.first(where: { $0.id == storedAccountID })
            ?? provider.accounts.first(where: { $0.id == storedAccountID })
            ?? CodexBarProviderAccount.fromTokenAccount(account, existingID: storedAccountID)

        let credentialsChanged = self.oauthCredentialsChanged(
            existing: existingStoredAccount,
            updated: storedAccount
        )
        let syncCodex = activate || (
            self.active.providerId == provider.id &&
            self.active.accountId == storedAccount.id &&
            credentialsChanged
        )
        return (storedAccount, syncCodex)
    }

    mutating func activateOAuthAccount(accountID: String) throws -> CodexBarProviderAccount {
        guard var provider = self.oauthProvider() else {
            throw TokenStoreError.providerNotFound
        }
        guard let stored = self.oauthStoredAccount(in: provider, matching: accountID) else {
            throw TokenStoreError.accountNotFound
        }

        provider.activeAccountId = stored.id
        self.upsertProvider(provider)
        self.active.providerId = provider.id
        self.active.accountId = stored.id
        return stored
    }

    mutating func setOAuthPreferredAccount(accountID: String) throws {
        guard var provider = self.oauthProvider() else {
            throw TokenStoreError.providerNotFound
        }
        guard let stored = self.oauthStoredAccount(in: provider, matching: accountID) else {
            throw TokenStoreError.accountNotFound
        }

        provider.activeAccountId = stored.id
        self.upsertProvider(provider)
    }

    func oauthTokenAccounts() -> [TokenAccount] {
        guard let provider = self.oauthProvider() else { return [] }
        let isOAuthActive = self.active.providerId == provider.id

        return provider.accounts.compactMap { stored in
            stored.asTokenAccount(isActive: isOAuthActive && self.active.accountId == stored.id)
        }.sorted { lhs, rhs in
            if lhs.isActive != rhs.isActive { return lhs.isActive }
            return lhs.email < rhs.email
        }
    }

    mutating func setOpenAIAccountOrder(_ accountOrder: [String]) {
        self.openAI.accountOrder = Self.uniqueAccountIDs(from: accountOrder)
        self.normalizeOpenAIAccountOrder()
    }

    mutating func upsertOpenRouterProvider(
        accountLabel: String,
        apiKey: String,
        activate: Bool
    ) throws -> CodexBarProviderAccount {
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedAPIKey.isEmpty == false else {
            throw TokenStoreError.invalidInput
        }

        var provider = self.ensureOpenRouterProvider()

        let trimmedLabel = accountLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedLabel: String
        if trimmedLabel.isEmpty == false {
            resolvedLabel = trimmedLabel
        } else {
            let suffix = trimmedAPIKey.suffix(4)
            resolvedLabel = suffix.isEmpty ? "OpenRouter Key" : "Key ...\(suffix)"
        }
        let account = CodexBarProviderAccount(
            kind: .apiKey,
            label: resolvedLabel,
            apiKey: trimmedAPIKey,
            addedAt: Date()
        )

        provider.accounts.append(account)
        provider.activeAccountId = account.id
        self.upsertProvider(provider)

        if activate {
            self.active.providerId = provider.id
            self.active.accountId = account.id
        } else if self.active.providerId == provider.id, self.active.accountId == nil {
            self.active.accountId = account.id
        }

        return account
    }

    mutating func activateOpenRouterAccount(accountID: String) throws -> CodexBarProviderAccount {
        guard var provider = self.openRouterProvider() else {
            throw TokenStoreError.providerNotFound
        }
        guard let stored = provider.accounts.first(where: { $0.id == accountID }) else {
            throw TokenStoreError.accountNotFound
        }

        provider.activeAccountId = stored.id
        self.upsertProvider(provider)
        self.active.providerId = provider.id
        self.active.accountId = stored.id
        return stored
    }

    mutating func setOpenRouterDefaultModel(_ value: String?) throws {
        try self.setOpenRouterSelectedModel(value)
    }

    mutating func setOpenRouterSelectedModel(_ value: String?) throws {
        guard var provider = self.openRouterProvider() else {
            throw TokenStoreError.providerNotFound
        }
        provider.selectedModelID = CodexBarProvider.normalizedOpenRouterModelID(value)
        provider.pinnedModelIDs = CodexBarProvider.resolvedPinnedModelIDs(
            provider.pinnedModelIDs,
            selectedModelID: provider.selectedModelID
        )
        self.upsertProvider(provider)
    }

    mutating func setOpenRouterModelSelection(
        selectedModelID: String?,
        pinnedModelIDs: [String],
        cachedModelCatalog: [CodexBarOpenRouterModel]? = nil,
        fetchedAt: Date? = nil
    ) throws {
        guard var provider = self.openRouterProvider() else {
            throw TokenStoreError.providerNotFound
        }

        let normalizedSelectedModelID = CodexBarProvider.normalizedOpenRouterModelID(selectedModelID)
        provider.selectedModelID = normalizedSelectedModelID
        provider.pinnedModelIDs = CodexBarProvider.resolvedPinnedModelIDs(
            pinnedModelIDs,
            selectedModelID: normalizedSelectedModelID
        )
        if let cachedModelCatalog {
            provider.cachedModelCatalog = Self.uniqueOpenRouterModelCatalog(cachedModelCatalog)
        }
        if let fetchedAt {
            provider.modelCatalogFetchedAt = fetchedAt
        }
        self.upsertProvider(provider)
    }

    mutating func updateOpenRouterModelCatalog(
        _ models: [CodexBarOpenRouterModel],
        fetchedAt: Date
    ) throws {
        guard var provider = self.openRouterProvider() else {
            throw TokenStoreError.providerNotFound
        }
        provider.cachedModelCatalog = Self.uniqueOpenRouterModelCatalog(models)
        provider.modelCatalogFetchedAt = fetchedAt
        provider.pinnedModelIDs = CodexBarProvider.resolvedPinnedModelIDs(
            provider.pinnedModelIDs,
            selectedModelID: provider.selectedModelID
        )
        self.upsertProvider(provider)
    }

    mutating func setOpenAIManualActivationBehavior(_ behavior: CodexBarOpenAIManualActivationBehavior) {
        self.openAI.manualActivationBehavior = behavior
    }

    mutating func setOpenAIAccountOrderingMode(_ mode: CodexBarOpenAIAccountOrderingMode) {
        self.openAI.accountOrderingMode = mode
    }

    mutating func removeOpenAIAccountOrder(accountID: String) {
        self.openAI.accountOrder.removeAll { $0 == accountID }
    }

    mutating func normalizeOpenAIAccountOrder() {
        let availableAccountIDs = self.oauthProvider()?.accounts.map(\.id) ?? []
        let availableAccountIDSet = Set(availableAccountIDs)

        var normalized: [String] = []
        var seen: Set<String> = []

        for accountID in self.openAI.accountOrder where availableAccountIDSet.contains(accountID) {
            guard seen.insert(accountID).inserted else { continue }
            normalized.append(accountID)
        }

        for accountID in availableAccountIDs where seen.insert(accountID).inserted {
            normalized.append(accountID)
        }

        self.openAI.accountOrder = normalized
    }

    @discardableResult
    mutating func normalizeSharedOpenAITeamOrganizationNames() -> Bool {
        guard let providerIndex = self.providers.firstIndex(where: { $0.kind == .openAIOAuth }) else {
            return false
        }

        var provider = self.providers[providerIndex]
        let groupedIndices = Dictionary(
            grouping: provider.accounts.indices.compactMap { index -> (String, Int)? in
                let account = provider.accounts[index]
                guard Self.isSharedOpenAITeamAccount(account),
                      let sharedAccountID = Self.normalizedSharedOpenAIAccountID(for: account) else {
                    return nil
                }
                return (sharedAccountID, index)
            },
            by: \.0
        )

        var changed = false
        for indices in groupedIndices.values.map({ $0.map(\.1) }) {
            let sharedNames = Set(
                indices.compactMap { index in
                    Self.normalizedSharedOrganizationName(provider.accounts[index].organizationName)
                }
            )
            guard sharedNames.count == 1,
                  let sharedName = sharedNames.first else {
                continue
            }

            for index in indices {
                let account = provider.accounts[index]
                let normalizedName = Self.normalizedSharedOrganizationName(account.organizationName)

                if normalizedName == sharedName {
                    if account.organizationName != sharedName {
                        provider.accounts[index].organizationName = sharedName
                        changed = true
                    }
                    continue
                }

                guard normalizedName == nil else { continue }
                provider.accounts[index].organizationName = sharedName
                changed = true
            }
        }

        guard changed else { return false }
        self.providers[providerIndex] = provider
        return true
    }

    mutating func remapOAuthAccountReferences(using accountIDMapping: [String: String]) {
        guard accountIDMapping.isEmpty == false else { return }

        if let providerIndex = self.providers.firstIndex(where: { $0.kind == .openAIOAuth }) {
            var provider = self.providers[providerIndex]
            provider.accounts = provider.accounts.map { stored in
                var updated = stored
                if let remappedID = accountIDMapping[stored.id] {
                    updated.id = remappedID
                }
                return updated
            }
            if let activeAccountId = provider.activeAccountId,
               let remappedID = accountIDMapping[activeAccountId] {
                provider.activeAccountId = remappedID
            }
            self.providers[providerIndex] = provider

            if self.active.providerId == provider.id,
               let activeAccountId = self.active.accountId,
               let remappedID = accountIDMapping[activeAccountId] {
                self.active.accountId = remappedID
            }
        }

        self.openAI.accountOrder = Self.uniqueAccountIDs(
            from: self.openAI.accountOrder.map { accountIDMapping[$0] ?? $0 }
        )
        self.normalizeOpenAIAccountOrder()
    }

    private mutating func ensureOAuthProvider() -> CodexBarProvider {
        if let provider = self.oauthProvider() {
            return provider
        }
        let provider = CodexBarProvider(
            id: "openai-oauth",
            kind: .openAIOAuth,
            label: "OpenAI",
            enabled: true,
            baseURL: nil
        )
        self.providers.append(provider)
        return provider
    }

    private mutating func ensureOpenRouterProvider() -> CodexBarProvider {
        if let provider = self.openRouterProvider() {
            return provider
        }
        let provider = CodexBarProvider(
            id: "openrouter",
            kind: .openRouter,
            label: "OpenRouter",
            enabled: true
        )
        self.providers.append(provider)
        return provider
    }

    private mutating func upsertProvider(_ provider: CodexBarProvider) {
        if let index = self.providers.firstIndex(where: { $0.id == provider.id }) {
            self.providers[index] = provider
        } else {
            self.providers.append(provider)
        }
    }

    private mutating func appendOpenAIAccountOrderIfNeeded(accountID: String) {
        guard self.openAI.accountOrder.contains(accountID) == false else { return }
        self.openAI.accountOrder.append(accountID)
    }

    private func oauthStoredAccount(in provider: CodexBarProvider, matching accountID: String) -> CodexBarProviderAccount? {
        if let stored = provider.accounts.first(where: { $0.id == accountID }) {
            return stored
        }

        let remoteMatches = provider.accounts.filter { $0.openAIAccountId == accountID }
        if remoteMatches.count == 1 {
            return remoteMatches[0]
        }
        return nil
    }

    private func oauthCredentialsChanged(
        existing: CodexBarProviderAccount?,
        updated: CodexBarProviderAccount
    ) -> Bool {
        guard let existing else { return true }
        return existing.accessToken != updated.accessToken ||
            existing.refreshToken != updated.refreshToken ||
            existing.idToken != updated.idToken ||
            existing.expiresAt != updated.expiresAt ||
            existing.oauthClientID != updated.oauthClientID ||
            existing.tokenLastRefreshAt != updated.tokenLastRefreshAt ||
            existing.openAIAccountId != updated.openAIAccountId
    }

    private static func uniqueAccountIDs(from accountIDs: [String]) -> [String] {
        var seen: Set<String> = []
        return accountIDs.filter { seen.insert($0).inserted }
    }

    private static func uniqueOpenRouterModelCatalog(
        _ models: [CodexBarOpenRouterModel]
    ) -> [CodexBarOpenRouterModel] {
        var seen: Set<String> = []
        return models.compactMap { model in
            guard let normalizedID = CodexBarProvider.normalizedOpenRouterModelID(model.id),
                  seen.insert(normalizedID).inserted else {
                return nil
            }
            return CodexBarOpenRouterModel(id: normalizedID, name: model.name)
        }
    }

    private static func isSharedOpenAITeamAccount(_ account: CodexBarProviderAccount) -> Bool {
        guard account.kind == .oauthTokens else { return false }
        return self.normalizedPlanType(account.planType) == "team"
    }

    private static func normalizedPlanType(_ planType: String?) -> String {
        planType?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }

    private static func normalizedSharedOpenAIAccountID(
        for account: CodexBarProviderAccount
    ) -> String? {
        let accountID = (account.openAIAccountId ?? account.id)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return accountID.isEmpty ? nil : accountID
    }

    private static func normalizedSharedOrganizationName(_ organizationName: String?) -> String? {
        guard let organizationName = organizationName?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              organizationName.isEmpty == false else {
            return nil
        }
        return organizationName
    }
}
