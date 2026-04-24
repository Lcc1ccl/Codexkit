import Foundation

struct CLIProxyAPIManagementConfigResponse: Decodable, Equatable {
    struct RemoteManagement: Decodable, Equatable {
        var allowRemote: Bool?
        var secretKey: String?

        enum CodingKeys: String, CodingKey {
            case allowRemote = "allow-remote"
            case secretKey = "secret-key"
        }
    }

    struct QuotaExceeded: Decodable, Equatable {
        var switchProject: Bool?
        var switchPreviewModel: Bool?

        enum CodingKeys: String, CodingKey {
            case switchProject = "switch-project"
            case switchPreviewModel = "switch-preview-model"
        }
    }

    struct Routing: Decodable, Equatable {
        var strategy: String?
    }

    var host: String?
    var port: Int?
    var authDirectoryPath: String?
    var disableCooling: Bool?
    var requestRetry: Int?
    var maxRetryInterval: Int?
    var remoteManagement: RemoteManagement?
    var quotaExceeded: QuotaExceeded?
    var routing: Routing?

    enum CodingKeys: String, CodingKey {
        case host
        case port
        case authDirectoryPath = "auth-dir"
        case disableCooling = "disable-cooling"
        case requestRetry = "request-retry"
        case maxRetryInterval = "max-retry-interval"
        case remoteManagement = "remote-management"
        case quotaExceeded = "quota-exceeded"
        case routing
    }
}

struct CLIProxyAPIManagementListResponse: Decodable, Equatable {
    struct FileEntry: Decodable, Equatable {
        struct IDTokenClaims: Decodable, Equatable {
            var planType: String?
            var chatGPTAccountID: String?

            enum CodingKeys: String, CodingKey {
                case planType = "plan_type"
                case chatGPTAccountID = "chatgpt_account_id"
            }
        }

        var name: String
        var type: String?
        var email: String?
        var authIndex: String?
        var account: String?
        var accountType: String?
        var idToken: IDTokenClaims?
        var status: String?
        var statusMessage: String?
        var disabled: Bool?
        var unavailable: Bool?
        var nextRetryAfter: Date?
        var priority: Int?
        var localAccountID: String?

        enum CodingKeys: String, CodingKey {
            case name
            case type
            case email
            case authIndex = "auth_index"
            case account
            case accountType = "account_type"
            case idToken = "id_token"
            case status
            case statusMessage = "status_message"
            case disabled
            case unavailable
            case nextRetryAfter = "next_retry_after"
            case priority
            case localAccountID = "codexkit_local_account_id"
        }
    }

    var files: [FileEntry]
}

struct CLIProxyAPIManagementModelsResponse: Decodable, Equatable {
    struct ModelEntry: Decodable, Equatable {
        var id: String
        var display_name: String?
        var type: String?
        var owned_by: String?
    }

    var models: [ModelEntry]
}

struct CLIProxyAPIManagementUsageResponse: Decodable, Equatable {
    struct TokenStats: Decodable, Equatable {
        var totalTokens: Int?

        enum CodingKeys: String, CodingKey {
            case totalTokens = "total_tokens"
        }
    }

    struct RequestDetail: Decodable, Equatable {
        var authIndex: String?
        var failed: Bool?
        var tokens: TokenStats?

        enum CodingKeys: String, CodingKey {
            case authIndex = "auth_index"
            case failed
            case tokens
        }
    }

    struct ModelSnapshot: Decodable, Equatable {
        var total_requests: Int
        var total_tokens: Int
        var details: [RequestDetail]?
    }

    struct APISnapshot: Decodable, Equatable {
        var total_requests: Int
        var total_tokens: Int
        var models: [String: ModelSnapshot]?
    }

    struct UsageSnapshot: Decodable, Equatable {
        var total_requests: Int
        var success_count: Int?
        var failure_count: Int?
        var total_tokens: Int?
        var apis: [String: APISnapshot]?
    }

    var usage: UsageSnapshot
    var failed_requests: Int?
}

struct CLIProxyAPIManagementLogsResponse: Decodable, Equatable {
    var lines: [String]
    var lineCount: Int
    var latestTimestamp: Int64

    enum CodingKeys: String, CodingKey {
        case lines
        case lineCount = "line-count"
        case latestTimestamp = "latest-timestamp"
    }
}

enum CLIProxyAPIManagementServiceError: LocalizedError, Equatable {
    case server(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case let .server(_, message):
            return message
        }
    }
}

struct CLIProxyAPIManagementQuotaResponse: Decodable, Equatable {
    struct Account: Decodable, Equatable {
        var id: String
        var auth_index: String
        var name: String
        var provider: String
        var email: String
        var priority: Int?
        var chatgpt_account_id: String
        var codexkit_local_account_id: String
        var plan_type: String
        var five_hour_remaining_percent: Int?
        var weekly_remaining_percent: Int?
        var primary_reset_at: Date?
        var secondary_reset_at: Date?
        var primary_limit_window_seconds: Int?
        var secondary_limit_window_seconds: Int?
        var last_quota_refreshed_at: Date?
        var quota_refresh_status: String
        var quota_refresh_error: String?
        var quota_source: String
    }

    var snapshot_generated_at: Date
    var refresh_status: String
    var stale: Bool
    var refresh_interval_seconds: Int
    var stale_threshold_seconds: Int
    var accounts: [Account]
}

final class CLIProxyAPIManagementService {
    private let session: URLSession
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private let now: @Sendable () -> Date

    private static let retryableStatusCodes: Set<Int> = [429, 500, 502, 503, 504]
    private static let retryableTransportErrors: Set<URLError.Code> = [
        .timedOut,
        .cannotConnectToHost,
        .networkConnectionLost,
        .notConnectedToInternet,
        .cannotFindHost,
    ]
    private static let retryBaseDelaySeconds: TimeInterval = 0.25
    private static let retryMaxDelaySeconds: TimeInterval = 2
    private static let retryBudgetSeconds: TimeInterval = 8
    private static let retryMaxAttempts = 3

    init(
        session: URLSession = .shared,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
            try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
        },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.session = session
        self.sleep = sleep
        self.now = now
    }

    func getConfigYAML(config: CLIProxyAPIServiceConfig) async throws -> String {
        let url = config.baseURL.appendingPathComponent("v0/management/config.yaml")
        let data = try await self.performGET(url: url, secret: config.managementSecretKey)
        guard let yaml = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeRawData)
        }
        return yaml
    }

    func getConfig(config: CLIProxyAPIServiceConfig) async throws -> CLIProxyAPIManagementConfigResponse {
        let url = config.baseURL.appendingPathComponent("v0/management/config")
        let data = try await self.performGET(url: url, secret: config.managementSecretKey)
        return try JSONDecoder().decode(CLIProxyAPIManagementConfigResponse.self, from: data)
    }

    func getRoutingStrategy(config: CLIProxyAPIServiceConfig) async throws -> CLIProxyAPIRoutingStrategy {
        struct Response: Decodable { var strategy: String }
        let url = config.baseURL.appendingPathComponent("v0/management/routing/strategy")
        let data = try await self.performGET(url: url, secret: config.managementSecretKey)
        return CLIProxyAPIRoutingStrategy(rawValue: try JSONDecoder().decode(Response.self, from: data).strategy)
    }

    func putRoutingStrategy(config: CLIProxyAPIServiceConfig, strategy: CLIProxyAPIRoutingStrategy) async throws {
        let url = config.baseURL.appendingPathComponent("v0/management/routing/strategy")
        try await self.performPUTJSON(url: url, secret: config.managementSecretKey, body: ["value": strategy.rawValue])
    }

    func getSwitchProjectOnQuotaExceeded(config: CLIProxyAPIServiceConfig) async throws -> Bool {
        struct Response: Decodable {
            var value: Bool
            enum CodingKeys: String, CodingKey { case value = "switch-project" }
        }
        let url = config.baseURL.appendingPathComponent("v0/management/quota-exceeded/switch-project")
        let data = try await self.performGET(url: url, secret: config.managementSecretKey)
        return try JSONDecoder().decode(Response.self, from: data).value
    }

    func putSwitchProjectOnQuotaExceeded(config: CLIProxyAPIServiceConfig, enabled: Bool) async throws {
        let url = config.baseURL.appendingPathComponent("v0/management/quota-exceeded/switch-project")
        try await self.performPUTJSON(url: url, secret: config.managementSecretKey, body: ["value": enabled])
    }

    func getSwitchPreviewModelOnQuotaExceeded(config: CLIProxyAPIServiceConfig) async throws -> Bool {
        struct Response: Decodable {
            var value: Bool
            enum CodingKeys: String, CodingKey { case value = "switch-preview-model" }
        }
        let url = config.baseURL.appendingPathComponent("v0/management/quota-exceeded/switch-preview-model")
        let data = try await self.performGET(url: url, secret: config.managementSecretKey)
        return try JSONDecoder().decode(Response.self, from: data).value
    }

    func putSwitchPreviewModelOnQuotaExceeded(config: CLIProxyAPIServiceConfig, enabled: Bool) async throws {
        let url = config.baseURL.appendingPathComponent("v0/management/quota-exceeded/switch-preview-model")
        try await self.performPUTJSON(url: url, secret: config.managementSecretKey, body: ["value": enabled])
    }

    func getRequestRetry(config: CLIProxyAPIServiceConfig) async throws -> Int {
        struct Response: Decodable {
            var value: Int
            enum CodingKeys: String, CodingKey { case value = "request-retry" }
        }
        let url = config.baseURL.appendingPathComponent("v0/management/request-retry")
        let data = try await self.performGET(url: url, secret: config.managementSecretKey)
        return try JSONDecoder().decode(Response.self, from: data).value
    }

    func putRequestRetry(config: CLIProxyAPIServiceConfig, value: Int) async throws {
        let url = config.baseURL.appendingPathComponent("v0/management/request-retry")
        try await self.performPUTJSON(url: url, secret: config.managementSecretKey, body: ["value": max(0, value)])
    }

    func getMaxRetryInterval(config: CLIProxyAPIServiceConfig) async throws -> Int {
        struct Response: Decodable {
            var value: Int
            enum CodingKeys: String, CodingKey { case value = "max-retry-interval" }
        }
        let url = config.baseURL.appendingPathComponent("v0/management/max-retry-interval")
        let data = try await self.performGET(url: url, secret: config.managementSecretKey)
        return try JSONDecoder().decode(Response.self, from: data).value
    }

    func putMaxRetryInterval(config: CLIProxyAPIServiceConfig, value: Int) async throws {
        let url = config.baseURL.appendingPathComponent("v0/management/max-retry-interval")
        try await self.performPUTJSON(url: url, secret: config.managementSecretKey, body: ["value": max(0, value)])
    }

    func putConfigYAML(config: CLIProxyAPIServiceConfig, yaml: String) async throws {
        let url = config.baseURL.appendingPathComponent("v0/management/config.yaml")
        try await self.performPUTRaw(url: url, secret: config.managementSecretKey, body: Data(yaml.utf8), contentType: "application/yaml; charset=utf-8")
    }

    func makeRuntimeConfiguration(
        response: CLIProxyAPIManagementConfigResponse,
        fallback: CLIProxyAPIServiceConfig
    ) -> CLIProxyAPIServiceConfig {
        CLIProxyAPIServiceConfig(
            host: response.host ?? fallback.host,
            port: response.port ?? fallback.port,
            authDirectory: response.authDirectoryPath.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? fallback.authDirectory,
            managementSecretKey: response.remoteManagement?.secretKey ?? fallback.managementSecretKey,
            allowRemoteManagement: response.remoteManagement?.allowRemote ?? fallback.allowRemoteManagement,
            enabled: fallback.enabled,
            routingStrategy: CLIProxyAPIRoutingStrategy(rawValue: response.routing?.strategy ?? fallback.routingStrategy.rawValue),
            switchProjectOnQuotaExceeded: response.quotaExceeded?.switchProject ?? fallback.switchProjectOnQuotaExceeded,
            switchPreviewModelOnQuotaExceeded: response.quotaExceeded?.switchPreviewModel ?? fallback.switchPreviewModelOnQuotaExceeded,
            requestRetry: response.requestRetry ?? fallback.requestRetry,
            maxRetryInterval: response.maxRetryInterval ?? fallback.maxRetryInterval,
            disableCooling: response.disableCooling ?? fallback.disableCooling
        )
    }

    func listAuthFiles(config: CLIProxyAPIServiceConfig) async throws -> [CLIProxyAPIManagementListResponse.FileEntry] {
        let url = config.baseURL.appendingPathComponent("v0/management/auth-files")
        let data = try await self.performGET(url: url, secret: config.managementSecretKey)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CLIProxyAPIManagementListResponse.self, from: data).files
    }

    func listModels(config: CLIProxyAPIServiceConfig, authFileName: String) async throws -> [CLIProxyAPIManagementModelsResponse.ModelEntry] {
        var components = URLComponents(url: config.baseURL.appendingPathComponent("v0/management/auth-files/models"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "name", value: authFileName)]
        let data = try await self.performGET(url: components.url!, secret: config.managementSecretKey)
        return try JSONDecoder().decode(CLIProxyAPIManagementModelsResponse.self, from: data).models
    }

    func getUsageStatistics(config: CLIProxyAPIServiceConfig) async throws -> CLIProxyAPIManagementUsageResponse {
        let url = config.baseURL.appendingPathComponent("v0/management/usage")
        let data = try await self.performGET(url: url, secret: config.managementSecretKey)
        return try JSONDecoder().decode(CLIProxyAPIManagementUsageResponse.self, from: data)
    }

    func getLogs(
        config: CLIProxyAPIServiceConfig,
        afterTimestamp: Int?,
        limit: Int
    ) async throws -> CLIProxyAPIManagementLogsResponse {
        var components = URLComponents(url: config.baseURL.appendingPathComponent("v0/management/logs"), resolvingAgainstBaseURL: false)!
        var queryItems = [URLQueryItem(name: "limit", value: String(max(1, limit)))]
        if let afterTimestamp {
            queryItems.append(URLQueryItem(name: "after", value: String(afterTimestamp)))
        }
        components.queryItems = queryItems
        let data = try await self.performGET(url: components.url!, secret: config.managementSecretKey)
        return try JSONDecoder().decode(CLIProxyAPIManagementLogsResponse.self, from: data)
    }

    func getQuotaSnapshot(config: CLIProxyAPIServiceConfig) async throws -> CLIProxyAPIQuotaSnapshot {
        let url = config.baseURL.appendingPathComponent("v0/management/quota")
        let data = try await self.performGET(url: url, secret: config.managementSecretKey)
        return try self.makeQuotaSnapshot(data: data)
    }

    func refreshQuotaSnapshot(config: CLIProxyAPIServiceConfig) async throws -> CLIProxyAPIQuotaSnapshot {
        let url = config.baseURL.appendingPathComponent("v0/management/quota/refresh")
        let data = try await self.performPOST(url: url, secret: config.managementSecretKey)
        return try self.makeQuotaSnapshot(data: data)
    }

    func makeQuotaSnapshot(data: Data) throws -> CLIProxyAPIQuotaSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response = try decoder.decode(CLIProxyAPIManagementQuotaResponse.self, from: data)
        return CLIProxyAPIQuotaSnapshot(
            snapshotGeneratedAt: response.snapshot_generated_at,
            refreshStatus: CLIProxyAPIQuotaRefreshStatus(rawValue: response.refresh_status) ?? .failed,
            stale: response.stale,
            refreshIntervalSeconds: response.refresh_interval_seconds,
            staleThresholdSeconds: response.stale_threshold_seconds,
            accounts: response.accounts.map {
                CLIProxyAPIQuotaAccountItem(
                    id: $0.id,
                    authIndex: $0.auth_index,
                    name: $0.name,
                    provider: $0.provider,
                    email: $0.email,
                    priority: $0.priority,
                    chatGPTAccountID: $0.chatgpt_account_id,
                    localAccountID: $0.codexkit_local_account_id,
                    planType: $0.plan_type,
                    fiveHourRemainingPercent: $0.five_hour_remaining_percent,
                    weeklyRemainingPercent: $0.weekly_remaining_percent,
                    primaryResetAt: $0.primary_reset_at,
                    secondaryResetAt: $0.secondary_reset_at,
                    primaryLimitWindowSeconds: $0.primary_limit_window_seconds,
                    secondaryLimitWindowSeconds: $0.secondary_limit_window_seconds,
                    lastQuotaRefreshedAt: $0.last_quota_refreshed_at,
                    refreshStatus: CLIProxyAPIQuotaRefreshStatus(rawValue: $0.quota_refresh_status) ?? .failed,
                    refreshError: $0.quota_refresh_error,
                    source: $0.quota_source
                )
            }
        )
    }

    static func makeAccountUsageItems(
        files: [CLIProxyAPIManagementListResponse.FileEntry],
        usage: CLIProxyAPIManagementUsageResponse?,
        localAccounts: [TokenAccount]
    ) -> [CLIProxyAPIAccountUsageItem] {
        var statsByAuthIndex: [String: (success: Int, failed: Int, tokens: Int)] = [:]

        if let usage {
            for apiSnapshot in usage.usage.apis?.values ?? [:].values {
                for modelSnapshot in apiSnapshot.models?.values ?? [:].values {
                    for detail in modelSnapshot.details ?? [] {
                        guard let authIndex = detail.authIndex, authIndex.isEmpty == false else { continue }
                        var aggregate = statsByAuthIndex[authIndex] ?? (0, 0, 0)
                        if detail.failed == true {
                            aggregate.failed += 1
                        } else {
                            aggregate.success += 1
                        }
                        aggregate.tokens += detail.tokens?.totalTokens ?? 0
                        statsByAuthIndex[authIndex] = aggregate
                    }
                }
            }
        }

        return files.map { file in
            let matchedAccount = self.matchLocalAccount(for: file, localAccounts: localAccounts)

            let stats = file.authIndex.flatMap { statsByAuthIndex[$0] } ?? (0, 0, 0)
            let email = matchedAccount?.email ?? file.email ?? file.account ?? file.name
            let planType = self.normalizedPlanType(file.idToken?.planType)
                ?? matchedAccount?.planType
                ?? "free"

            return CLIProxyAPIAccountUsageItem(
                id: file.authIndex ?? file.name,
                title: matchedAccount?.organizationName ?? email,
                email: email,
                planType: planType,
                fiveHourRemainingPercent: matchedAccount.map { max(0, Int(round(100 - $0.primaryUsedPercent))) },
                weeklyRemainingPercent: matchedAccount.map { max(0, Int(round(100 - $0.secondaryUsedPercent))) },
                successRequests: stats.success,
                failedRequests: stats.failed,
                totalTokens: stats.tokens
            )
        }
        .sorted {
            $0.email.localizedCaseInsensitiveCompare($1.email) == .orderedAscending
        }
    }

    static func makeObservedAuthFiles(
        files: [CLIProxyAPIManagementListResponse.FileEntry],
        localAccounts: [TokenAccount]
    ) -> [CLIProxyAPIObservedAuthFile] {
        files.map { file in
            let matchedAccount = self.matchLocalAccount(for: file, localAccounts: localAccounts)
            return CLIProxyAPIObservedAuthFile(
                id: file.authIndex ?? file.name,
                fileName: file.name,
                localAccountID: file.localAccountID ?? matchedAccount?.accountId,
                remoteAccountID: self.normalizedRemoteAccountID(file.idToken?.chatGPTAccountID) ?? matchedAccount?.remoteAccountId,
                email: file.email ?? matchedAccount?.email,
                planType: self.normalizedPlanType(file.idToken?.planType) ?? matchedAccount?.planType,
                authIndex: file.authIndex,
                priority: file.priority,
                status: file.status,
                statusMessage: file.statusMessage,
                disabled: file.disabled ?? false,
                unavailable: file.unavailable ?? false,
                nextRetryAfter: file.nextRetryAfter
            )
        }
        .sorted {
            $0.fileName.localizedCaseInsensitiveCompare($1.fileName) == .orderedAscending
        }
    }

    private func performGET(url: URL, secret: String) async throws -> Data {
        try await self.performRequest(
            url: url,
            secret: secret,
            method: "GET",
            expectedStatusCodes: 200 ... 200
        )
    }

    private func performPUTJSON(url: URL, secret: String, body: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        try await self.performPUTRaw(url: url, secret: secret, body: data, contentType: "application/json")
    }

    private func performPUTRaw(url: URL, secret: String, body: Data, contentType: String) async throws {
        _ = try await self.performRequest(
            url: url,
            secret: secret,
            method: "PUT",
            body: body,
            contentType: contentType,
            expectedStatusCodes: 200 ... 299
        )
    }

    private func performPOST(url: URL, secret: String) async throws -> Data {
        try await self.performRequest(
            url: url,
            secret: secret,
            method: "POST",
            body: Data("{}".utf8),
            contentType: "application/json",
            expectedStatusCodes: 200 ... 299
        )
    }

    private func performRequest(
        url: URL,
        secret: String,
        method: String,
        body: Data? = nil,
        contentType: String? = nil,
        expectedStatusCodes: ClosedRange<Int>
    ) async throws -> Data {
        let startedAt = self.now()
        var attempt = 0

        while true {
            do {
                let (data, response) = try await self.session.data(for: self.makeRequest(
                    url: url,
                    secret: secret,
                    method: method,
                    body: body,
                    contentType: contentType
                ))
                guard let http = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                guard expectedStatusCodes.contains(http.statusCode) else {
                    let error = self.serverError(statusCode: http.statusCode, data: data)
                    guard let delay = self.retryDelay(for: http, attempt: attempt, startedAt: startedAt) else {
                        throw error
                    }
                    attempt += 1
                    try await self.sleep(delay)
                    continue
                }
                return data
            } catch {
                guard let delay = self.retryDelay(for: error, attempt: attempt, startedAt: startedAt) else {
                    throw error
                }
                attempt += 1
                try await self.sleep(delay)
            }
        }
    }

    private func makeRequest(
        url: URL,
        secret: String,
        method: String,
        body: Data?,
        contentType: String?
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func retryDelay(
        for response: HTTPURLResponse,
        attempt: Int,
        startedAt: Date
    ) -> TimeInterval? {
        guard attempt < Self.retryMaxAttempts else { return nil }
        guard Self.retryableStatusCodes.contains(response.statusCode) else { return nil }

        let fallbackDelay = min(
            Self.retryBaseDelaySeconds * pow(2, Double(attempt)),
            Self.retryMaxDelaySeconds
        )
        let responseDelay = self.retryAfterDelay(from: response)
        let delay = max(0, responseDelay ?? fallbackDelay)
        let elapsed = self.now().timeIntervalSince(startedAt)
        guard elapsed + delay <= Self.retryBudgetSeconds else { return nil }
        return delay
    }

    private func retryDelay(
        for error: Error,
        attempt: Int,
        startedAt: Date
    ) -> TimeInterval? {
        guard attempt < Self.retryMaxAttempts else { return nil }
        guard let urlError = error as? URLError,
              Self.retryableTransportErrors.contains(urlError.code) else {
            return nil
        }

        let delay = min(
            Self.retryBaseDelaySeconds * pow(2, Double(attempt)),
            Self.retryMaxDelaySeconds
        )
        let elapsed = self.now().timeIntervalSince(startedAt)
        guard elapsed + delay <= Self.retryBudgetSeconds else { return nil }
        return delay
    }

    private func retryAfterDelay(from response: HTTPURLResponse) -> TimeInterval? {
        guard let rawValue = response.value(forHTTPHeaderField: "Retry-After")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              rawValue.isEmpty == false else {
            return nil
        }

        if let seconds = TimeInterval(rawValue) {
            return max(0, seconds)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        guard let date = formatter.date(from: rawValue) else { return nil }
        return max(0, date.timeIntervalSince(self.now()))
    }

    private static func matchLocalAccount(
        for file: CLIProxyAPIManagementListResponse.FileEntry,
        localAccounts: [TokenAccount]
    ) -> TokenAccount? {
        if let remoteID = normalizedRemoteAccountID(file.idToken?.chatGPTAccountID),
           let remoteMatch = localAccounts.first(where: { normalizedRemoteAccountID($0.remoteAccountId) == remoteID }) {
            return remoteMatch
        }

        guard let normalizedTargetEmail = normalizedEmail(file.email) else {
            return nil
        }

        let emailMatches = localAccounts.filter {
            normalizedEmail($0.email) == normalizedTargetEmail
        }
        guard emailMatches.isEmpty == false else {
            return nil
        }

        if let planType = normalizedPlanType(file.idToken?.planType),
           let planMatch = emailMatches.first(where: { normalizedPlanType($0.planType) == planType }) {
            return planMatch
        }

        return emailMatches.first
    }

    private static func normalizedEmail(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              trimmed.isEmpty == false else {
            return nil
        }
        return trimmed
    }

    private static func normalizedRemoteAccountID(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmed.isEmpty == false else {
            return nil
        }
        return trimmed
    }

    private static func normalizedPlanType(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              trimmed.isEmpty == false else {
            return nil
        }
        return trimmed
    }

    private func serverError(statusCode: Int, data: Data) -> Error {
        struct ErrorResponse: Decodable {
            var error: String?
            var message: String?
        }

        if let decoded = try? JSONDecoder().decode(ErrorResponse.self, from: data),
           let message = decoded.error ?? decoded.message,
           message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return CLIProxyAPIManagementServiceError.server(statusCode: statusCode, message: message)
        }

        if let rawMessage = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           rawMessage.isEmpty == false {
            return CLIProxyAPIManagementServiceError.server(statusCode: statusCode, message: rawMessage)
        }

        return URLError(.badServerResponse)
    }
}
