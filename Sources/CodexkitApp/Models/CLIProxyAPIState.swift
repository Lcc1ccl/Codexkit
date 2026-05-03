import Foundation

struct CLIProxyAPIServiceConfig: Codable, Equatable {
    var host: String
    var port: Int
    var authDirectory: URL
    var managementSecretKey: String
    var clientAPIKey: String?
    var allowRemoteManagement: Bool
    var enabled: Bool
    var routingStrategy: CLIProxyAPIRoutingStrategy
    var switchProjectOnQuotaExceeded: Bool
    var switchPreviewModelOnQuotaExceeded: Bool
    var requestRetry: Int
    var maxRetryInterval: Int
    var disableCooling: Bool

    init(
        host: String = CLIProxyAPIService.defaultHost,
        port: Int = 8317,
        authDirectory: URL,
        managementSecretKey: String,
        clientAPIKey: String? = nil,
        allowRemoteManagement: Bool = false,
        enabled: Bool = false,
        routingStrategy: CLIProxyAPIRoutingStrategy = .roundRobin,
        switchProjectOnQuotaExceeded: Bool = true,
        switchPreviewModelOnQuotaExceeded: Bool = true,
        requestRetry: Int = 3,
        maxRetryInterval: Int = 30,
        disableCooling: Bool = false
    ) {
        self.host = host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? CLIProxyAPIService.defaultHost
            : host.trimmingCharacters(in: .whitespacesAndNewlines)
        self.port = port
        self.authDirectory = authDirectory
        self.managementSecretKey = managementSecretKey
        self.clientAPIKey = Self.normalizedSecret(clientAPIKey)
        self.allowRemoteManagement = allowRemoteManagement
        self.enabled = enabled
        self.routingStrategy = routingStrategy
        self.switchProjectOnQuotaExceeded = switchProjectOnQuotaExceeded
        self.switchPreviewModelOnQuotaExceeded = switchPreviewModelOnQuotaExceeded
        self.requestRetry = max(0, requestRetry)
        self.maxRetryInterval = max(0, maxRetryInterval)
        self.disableCooling = disableCooling
    }

    var baseURL: URL {
        URL(string: "http://\(self.host):\(self.port)")!
    }

    var healthURL: URL {
        self.baseURL.appendingPathComponent("healthz")
    }

    private static func normalizedSecret(_ secret: String?) -> String? {
        guard let trimmed = secret?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmed.isEmpty == false else {
            return nil
        }
        return trimmed
    }
}

struct CLIProxyAPIAccountUsageItem: Equatable, Identifiable {
    var id: String
    var title: String
    var email: String
    var planType: String
    var fiveHourRemainingPercent: Int?
    var weeklyRemainingPercent: Int?
    var successRequests: Int
    var failedRequests: Int
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var reasoningTokens: Int = 0
    var cachedTokens: Int = 0
    var totalTokens: Int
}

struct CLIProxyAPIObservedAuthFile: Equatable, Identifiable {
    var id: String
    var fileName: String
    var localAccountID: String?
    var remoteAccountID: String?
    var email: String?
    var planType: String?
    var authIndex: String?
    var priority: Int?
    var status: String?
    var statusMessage: String?
    var disabled: Bool
    var unavailable: Bool
    var nextRetryAfter: Date?
}

enum CLIProxyAPIQuotaRefreshStatus: String, Codable, Equatable {
    case ok
    case stale
    case failed
    case unavailable
}

struct CLIProxyAPIQuotaAccountItem: Codable, Equatable, Identifiable {
    var id: String
    var authIndex: String
    var name: String
    var provider: String
    var email: String
    var priority: Int?
    var chatGPTAccountID: String
    var localAccountID: String
    var planType: String
    var fiveHourRemainingPercent: Int?
    var weeklyRemainingPercent: Int?
    var primaryResetAt: Date?
    var secondaryResetAt: Date?
    var primaryLimitWindowSeconds: Int?
    var secondaryLimitWindowSeconds: Int?
    var lastQuotaRefreshedAt: Date?
    var refreshStatus: CLIProxyAPIQuotaRefreshStatus
    var refreshError: String?
    var source: String
}

struct CLIProxyAPIQuotaSnapshot: Codable, Equatable {
    var snapshotGeneratedAt: Date
    var refreshStatus: CLIProxyAPIQuotaRefreshStatus
    var stale: Bool
    var refreshIntervalSeconds: Int
    var staleThresholdSeconds: Int
    var accounts: [CLIProxyAPIQuotaAccountItem]

    var minimumFiveHourRemainingPercent: Int? {
        self.accounts.compactMap(\.fiveHourRemainingPercent).min()
    }

    var minimumWeeklyRemainingPercent: Int? {
        self.accounts.compactMap(\.weeklyRemainingPercent).min()
    }

    var latestRefreshDate: Date? {
        self.accounts.compactMap(\.lastQuotaRefreshedAt).max()
    }
}

struct CLIProxyAPIQuotaGroup: Equatable, Identifiable {
    var id: String { self.email }
    var title: String
    var email: String
    var items: [CLIProxyAPIQuotaAccountItem]
}

struct CLIProxyAPIAccountMemberItem: Equatable, Identifiable {
    var id: String
    var title: String
    var email: String
    var planType: String
    var isSelectable: Bool
    var accountIDs: [String]
}

struct CLIProxyAPIAccountGroup: Equatable, Identifiable {
    var id: String { self.email }
    var title: String
    var email: String
    var memberItems: [CLIProxyAPIAccountMemberItem]
}

struct CLIProxyAPIUsageGroup: Equatable, Identifiable {
    var id: String { self.email }
    var title: String
    var email: String
    var usageItems: [CLIProxyAPIAccountUsageItem]
}

enum CLIProxyAPIAccountGrouping {
    static func groupedQuotaItems(_ items: [CLIProxyAPIQuotaAccountItem]) -> [CLIProxyAPIQuotaGroup] {
        let grouped = Dictionary(grouping: items) { item in
            item.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        return grouped.keys.sorted().compactMap { key in
            let rows = (grouped[key] ?? []).sorted {
                let lhsRank = self.planRank($0.planType)
                let rhsRank = self.planRank($1.planType)
                if lhsRank == rhsRank {
                    return $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending
                }
                return lhsRank < rhsRank
            }
            guard let first = rows.first else { return nil }
            return CLIProxyAPIQuotaGroup(title: first.email, email: first.email, items: rows)
        }
    }

    static func groupedMemberAccounts(
        localAccounts: [TokenAccount],
        importedUsageItems: [CLIProxyAPIAccountUsageItem]
    ) -> [CLIProxyAPIAccountGroup] {
        var buckets: [String: [String: CLIProxyAPIAccountMemberItem]] = [:]
        for account in localAccounts {
            let email = account.email.trimmingCharacters(in: .whitespacesAndNewlines)
            guard email.isEmpty == false else { continue }
            let key = email.lowercased()
            let planKey = self.normalizedPlanType(account.planType)
            let memberID = self.memberRowID(email: email, planType: planKey)
            var item = buckets[key, default: [:]][memberID] ?? CLIProxyAPIAccountMemberItem(
                id: memberID,
                title: email,
                email: email,
                planType: planKey,
                isSelectable: true,
                accountIDs: []
            )
            item.title = email
            item.isSelectable = true
            if item.accountIDs.contains(account.accountId) == false {
                item.accountIDs.append(account.accountId)
            }
            buckets[key, default: [:]][memberID] = item
        }

        let localIDs = Set(localAccounts.map(\.accountId))
        let localRemoteIDs = Set(localAccounts.map(\.remoteAccountId))

        for item in importedUsageItems {
            let email = item.email.trimmingCharacters(in: .whitespacesAndNewlines)
            guard email.isEmpty == false else { continue }
            let key = email.lowercased()
            let alreadyCovered = localIDs.contains(item.id) || localRemoteIDs.contains(item.id)
            if alreadyCovered { continue }
            let planKey = self.normalizedPlanType(item.planType)
            let memberID = self.memberRowID(email: email, planType: planKey)
            let existing = buckets[key, default: [:]][memberID]
            buckets[key, default: [:]][memberID] = CLIProxyAPIAccountMemberItem(
                id: memberID,
                title: existing?.title ?? email,
                email: email,
                planType: planKey,
                isSelectable: existing?.isSelectable ?? false,
                accountIDs: existing?.accountIDs ?? []
            )
        }

        return buckets.keys.sorted().map { key in
            let items = Array((buckets[key] ?? [:]).values).sorted {
                let lhsRank = self.planRank($0.planType)
                let rhsRank = self.planRank($1.planType)
                if lhsRank == rhsRank {
                    return $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending
                }
                return lhsRank < rhsRank
            }
            let email = items.first?.email ?? key
            return CLIProxyAPIAccountGroup(
                title: email,
                email: email,
                memberItems: items
            )
        }
    }

    static func groupedUsageItems(_ items: [CLIProxyAPIAccountUsageItem]) -> [CLIProxyAPIUsageGroup] {
        let grouped = Dictionary(grouping: items) { $0.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        return grouped.keys.sorted().compactMap { key in
            let rows = grouped[key] ?? []
            let aggregated = Dictionary(grouping: rows) {
                self.memberRowID(email: $0.email, planType: self.normalizedPlanType($0.planType))
            }
            let usageItems = aggregated.values.compactMap { planItems -> CLIProxyAPIAccountUsageItem? in
                guard let first = planItems.first else { return nil }
                return CLIProxyAPIAccountUsageItem(
                    id: self.memberRowID(email: first.email, planType: self.normalizedPlanType(first.planType)),
                    title: first.title,
                    email: first.email,
                    planType: self.normalizedPlanType(first.planType),
                    fiveHourRemainingPercent: self.minimumRemainingPercent(planItems.map(\.fiveHourRemainingPercent)),
                    weeklyRemainingPercent: self.minimumRemainingPercent(planItems.map(\.weeklyRemainingPercent)),
                    successRequests: planItems.reduce(0) { $0 + $1.successRequests },
                    failedRequests: planItems.reduce(0) { $0 + $1.failedRequests },
                    inputTokens: planItems.reduce(0) { $0 + $1.inputTokens },
                    outputTokens: planItems.reduce(0) { $0 + $1.outputTokens },
                    reasoningTokens: planItems.reduce(0) { $0 + $1.reasoningTokens },
                    cachedTokens: planItems.reduce(0) { $0 + $1.cachedTokens },
                    totalTokens: planItems.reduce(0) { $0 + $1.totalTokens }
                )
            }.sorted {
                let lhsRank = self.planRank($0.planType)
                let rhsRank = self.planRank($1.planType)
                if lhsRank == rhsRank {
                    return $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending
                }
                return lhsRank < rhsRank
            }
            guard let first = usageItems.first else { return nil }
            return CLIProxyAPIUsageGroup(
                title: first.email,
                email: first.email,
                usageItems: usageItems
            )
        }
    }

    private static func memberRowID(email: String, planType: String) -> String {
        "\(email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())|\(self.normalizedPlanType(planType))"
    }

    private static func normalizedPlanType(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().nilIfEmpty ?? "free"
    }

    private static func minimumRemainingPercent(_ values: [Int?]) -> Int? {
        let normalized = values.compactMap { $0 }
        return normalized.min()
    }

    private static func planRank(_ planType: String) -> Int {
        switch self.normalizedPlanType(planType) {
        case "team": return 0
        case "plus": return 1
        case "pro": return 2
        default: return 3
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        self.isEmpty ? nil : self
    }
}

struct CLIProxyAPIServiceState: Equatable {
    enum RuntimeStatus: String, Codable, Equatable {
        case stopped
        case starting
        case running
        case degraded
        case failed
    }

    var config: CLIProxyAPIServiceConfig
    var status: RuntimeStatus
    var lastError: String?
    var pid: Int32?
    var authFileCount: Int?
    var modelCount: Int?
    var modelIDs: [String]
    var totalRequests: Int?
    var failedRequests: Int?
    var totalTokens: Int?
    var requestsByDay: [String: Int]
    var requestsByHour: [String: Int]
    var tokensByDay: [String: Int]
    var tokensByHour: [String: Int]
    var quotaSnapshot: CLIProxyAPIQuotaSnapshot?
    var accountUsageItems: [CLIProxyAPIAccountUsageItem]
    var observedAuthFiles: [CLIProxyAPIObservedAuthFile]

    init(
        config: CLIProxyAPIServiceConfig,
        status: RuntimeStatus = .stopped,
        lastError: String? = nil,
        pid: Int32? = nil,
        authFileCount: Int? = nil,
        modelCount: Int? = nil,
        modelIDs: [String] = [],
        totalRequests: Int? = nil,
        failedRequests: Int? = nil,
        totalTokens: Int? = nil,
        requestsByDay: [String: Int] = [:],
        requestsByHour: [String: Int] = [:],
        tokensByDay: [String: Int] = [:],
        tokensByHour: [String: Int] = [:],
        quotaSnapshot: CLIProxyAPIQuotaSnapshot? = nil,
        accountUsageItems: [CLIProxyAPIAccountUsageItem] = [],
        observedAuthFiles: [CLIProxyAPIObservedAuthFile] = []
    ) {
        self.config = config
        self.status = status
        self.lastError = lastError
        self.pid = pid
        self.authFileCount = authFileCount
        self.modelCount = modelCount
        self.modelIDs = modelIDs
        self.totalRequests = totalRequests
        self.failedRequests = failedRequests
        self.totalTokens = totalTokens
        self.requestsByDay = requestsByDay
        self.requestsByHour = requestsByHour
        self.tokensByDay = tokensByDay
        self.tokensByHour = tokensByHour
        self.quotaSnapshot = quotaSnapshot
        self.accountUsageItems = accountUsageItems
        self.observedAuthFiles = observedAuthFiles
    }
}

extension CLIProxyAPIServiceState {
    var runtimeProcessLikelyActive: Bool {
        self.status == .running ||
            self.status == .starting ||
            self.status == .degraded ||
            self.pid != nil
    }

    var canStopRuntimeFromSettings: Bool {
        self.status == .running ||
            self.status == .starting ||
            self.pid != nil
    }

    func canStartRuntimeFromSettings(hasSelectedMembers: Bool) -> Bool {
        hasSelectedMembers && self.canStopRuntimeFromSettings == false
    }
}
