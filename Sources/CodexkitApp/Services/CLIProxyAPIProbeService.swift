import Foundation

struct CLIProxyAPISuggestedDraftValues: Equatable {
    var host: String
    var port: Int
    var managementSecretKey: String
    var clientAPIKey: String
    var routingStrategy: CLIProxyAPIRoutingStrategy
    var switchProjectOnQuotaExceeded: Bool
    var switchPreviewModelOnQuotaExceeded: Bool
    var requestRetry: Int
    var maxRetryInterval: Int
    var disableCooling: Bool
}

struct CLIProxyAPISyncSnapshot: Equatable {
    var values: CLIProxyAPISuggestedDraftValues
    var memberAccountIDs: [String]
    var authFileCount: Int
    var modelCount: Int
    var modelIDs: [String]
    var totalRequests: Int?
    var failedRequests: Int?
    var totalTokens: Int?
    var quotaSnapshot: CLIProxyAPIQuotaSnapshot?
    var accountUsageItems: [CLIProxyAPIAccountUsageItem]
    var observedAuthFiles: [CLIProxyAPIObservedAuthFile]
}

final class CLIProxyAPIProbeService {
    static let shared = CLIProxyAPIProbeService()

    private let service: CLIProxyAPIService
    private let managementService: CLIProxyAPIManagementService

    init(
        service: CLIProxyAPIService = .shared,
        managementService: CLIProxyAPIManagementService = CLIProxyAPIManagementService()
    ) {
        self.service = service
        self.managementService = managementService
    }

    func suggestedDraftValues(existingSettings: CodexBarDesktopSettings.CLIProxyAPISettings) -> CLIProxyAPISuggestedDraftValues {
        let runtimeConfig = self.service.loadRuntimeConfig()
        let localConfig = runtimeConfig ?? .init()
        let shouldUseLocalConfig = runtimeConfig != nil
        let shouldPreferGeneratedDefaults =
            existingSettings.port == 8317 &&
            existingSettings.managementSecretKey == nil
        let resolvedManagementSecretKey = localConfig.managementSecretKey
            ?? existingSettings.managementSecretKey
            ?? self.service.generateManagementSecretKey()
        let resolvedClientAPIKey = existingSettings.clientAPIKey
            ?? localConfig.clientAPIKey
            ?? self.service.generateDistinctClientAPIKey(managementSecretKey: resolvedManagementSecretKey)

        return CLIProxyAPISuggestedDraftValues(
            host: localConfig.host ?? existingSettings.host,
            port: shouldPreferGeneratedDefaults
                ? (localConfig.port ?? self.service.generateRandomAvailablePort())
                : existingSettings.port,
            managementSecretKey: resolvedManagementSecretKey,
            clientAPIKey: resolvedClientAPIKey,
            routingStrategy: shouldUseLocalConfig ? localConfig.routingStrategy : existingSettings.routingStrategy,
            switchProjectOnQuotaExceeded: shouldUseLocalConfig ? localConfig.switchProjectOnQuotaExceeded : existingSettings.switchProjectOnQuotaExceeded,
            switchPreviewModelOnQuotaExceeded: shouldUseLocalConfig ? localConfig.switchPreviewModelOnQuotaExceeded : existingSettings.switchPreviewModelOnQuotaExceeded,
            requestRetry: shouldUseLocalConfig ? localConfig.requestRetry : existingSettings.requestRetry,
            maxRetryInterval: shouldUseLocalConfig ? localConfig.maxRetryInterval : existingSettings.maxRetryInterval,
            disableCooling: shouldUseLocalConfig ? localConfig.disableCooling : existingSettings.disableCooling
        )
    }

    func detectExternalRepositoryRoot() -> URL? {
        if let envRoot = self.service.processEnvironment["CLIProxyAPI_REPO_ROOT"]
            .flatMap({ self.service.resolveConfiguredRepoRoot(explicitPath: $0, environment: [:]) }),
           self.isBundledRepositoryRoot(envRoot) == false {
            return envRoot
        }
        return nil
    }

    private func isBundledRepositoryRoot(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasSuffix("/CLIProxyAPIServiceBundle/CLIProxyAPI")
    }

    func syncSnapshot(
        host: String,
        port: Int,
        managementSecretKey: String,
        explicitRepoRootPath: String?,
        localAccounts: [TokenAccount]
    ) async throws -> CLIProxyAPISyncSnapshot {
        let repoRootURL = self.service.resolveConfiguredRepoRoot(explicitPath: explicitRepoRootPath)
        var config = CLIProxyAPIServiceConfig(
            host: host,
            port: port,
            authDirectory: CLIProxyAPIService.authDirectoryURL,
            managementSecretKey: managementSecretKey,
            allowRemoteManagement: false,
            enabled: true
        )

        let localConfig = self.localConfiguration(repoRootPath: repoRootURL?.path)
        var resolvedAuthDirectoryPath = localConfig.authDirectoryPath
        if let localPort = localConfig.port,
           localPort > 0 {
            config.host = localConfig.host ?? config.host
            config.port = localPort
            config.managementSecretKey = localConfig.managementSecretKey ?? config.managementSecretKey
            config.clientAPIKey = localConfig.clientAPIKey ?? config.clientAPIKey
            config.routingStrategy = localConfig.routingStrategy
            config.switchProjectOnQuotaExceeded = localConfig.switchProjectOnQuotaExceeded
            config.switchPreviewModelOnQuotaExceeded = localConfig.switchPreviewModelOnQuotaExceeded
            config.requestRetry = localConfig.requestRetry
            config.maxRetryInterval = localConfig.maxRetryInterval
            config.disableCooling = localConfig.disableCooling
        }

        if let remoteYAML = try? await self.managementService.getConfigYAML(config: config) {
            let remoteConfig = self.service.parseConfigYAML(remoteYAML)
            config.host = remoteConfig.host ?? config.host
            config.port = remoteConfig.port ?? config.port
            config.managementSecretKey = remoteConfig.managementSecretKey ?? config.managementSecretKey
            config.clientAPIKey = remoteConfig.clientAPIKey ?? config.clientAPIKey
            resolvedAuthDirectoryPath = remoteConfig.authDirectoryPath ?? resolvedAuthDirectoryPath
            config.routingStrategy = remoteConfig.routingStrategy
            config.switchProjectOnQuotaExceeded = remoteConfig.switchProjectOnQuotaExceeded
            config.switchPreviewModelOnQuotaExceeded = remoteConfig.switchPreviewModelOnQuotaExceeded
            config.requestRetry = remoteConfig.requestRetry
            config.maxRetryInterval = remoteConfig.maxRetryInterval
            config.disableCooling = remoteConfig.disableCooling
        }

        var files: [CLIProxyAPIManagementListResponse.FileEntry]
        var usage: CLIProxyAPIManagementUsageResponse?
        var quotaSnapshot: CLIProxyAPIQuotaSnapshot?
        var modelIDs: [String]

        do {
            files = try await self.managementService.listAuthFiles(config: config)
            usage = try await self.managementService.getUsageStatistics(config: config)
            quotaSnapshot = try await self.managementService.getQuotaSnapshot(config: config)
            modelIDs = try await self.resolveModelIDs(config: config, files: files)
        } catch {
            files = self.localAuthFiles(authDirectoryPath: resolvedAuthDirectoryPath)
            usage = nil
            quotaSnapshot = nil
            modelIDs = []
        }

        let items = CLIProxyAPIManagementService.makeAccountUsageItems(
            files: files,
            usage: usage,
            localAccounts: localAccounts
        )
        let observedAuthFiles = CLIProxyAPIManagementService.makeObservedAuthFiles(
            files: files,
            localAccounts: localAccounts
        )
        let memberAccountIDs = self.matchedMemberAccountIDs(files: files, localAccounts: localAccounts)

        return CLIProxyAPISyncSnapshot(
            values: CLIProxyAPISuggestedDraftValues(
                host: config.host,
                port: config.port,
                managementSecretKey: config.managementSecretKey,
                clientAPIKey: config.clientAPIKey
                    ?? self.service.generateDistinctClientAPIKey(managementSecretKey: config.managementSecretKey),
                routingStrategy: config.routingStrategy,
                switchProjectOnQuotaExceeded: config.switchProjectOnQuotaExceeded,
                switchPreviewModelOnQuotaExceeded: config.switchPreviewModelOnQuotaExceeded,
                requestRetry: config.requestRetry,
                maxRetryInterval: config.maxRetryInterval,
                disableCooling: config.disableCooling
            ),
            memberAccountIDs: memberAccountIDs,
            authFileCount: files.count,
            modelCount: modelIDs.count,
            modelIDs: modelIDs,
            totalRequests: usage?.usage.total_requests,
            failedRequests: usage?.failed_requests ?? usage?.usage.failure_count,
            totalTokens: usage?.usage.total_tokens,
            quotaSnapshot: quotaSnapshot,
            accountUsageItems: items,
            observedAuthFiles: observedAuthFiles
        )
    }

    private func localConfiguration(repoRootPath: String?) -> CLIProxyAPIService.LocalConfiguration {
        if let repoRootPath,
           repoRootPath.isEmpty == false,
           let config = self.service.loadConfig(
                from: URL(fileURLWithPath: repoRootPath, isDirectory: true)
                    .appendingPathComponent("config.yaml")
           ) {
            return config
        }

        return self.service.loadRuntimeConfig() ?? .init()
    }

    private func resolveModelIDs(
        config: CLIProxyAPIServiceConfig,
        files: [CLIProxyAPIManagementListResponse.FileEntry]
    ) async throws -> [String] {
        var modelIDs: Set<String> = []
        for file in files {
            let models = try await self.managementService.listModels(config: config, authFileName: file.name)
            models.forEach { modelIDs.insert($0.id) }
        }
        return modelIDs.sorted()
    }

    private func matchedMemberAccountIDs(
        files: [CLIProxyAPIManagementListResponse.FileEntry],
        localAccounts: [TokenAccount]
    ) -> [String] {
        Array(
            Set(
                files.compactMap { file in
                    localAccounts.first {
                        if let remoteID = file.idToken?.chatGPTAccountID,
                           remoteID.isEmpty == false,
                           $0.remoteAccountId == remoteID {
                            return true
                        }

                        guard let email = file.email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                              email.isEmpty == false else {
                            return false
                        }
                        return $0.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == email
                    }?.accountId
                }
            )
        ).sorted()
    }

    private func localAuthFiles(authDirectoryPath: String?) -> [CLIProxyAPIManagementListResponse.FileEntry] {
        guard let authDirectoryPath, authDirectoryPath.isEmpty == false else { return [] }
        let directoryURL = URL(fileURLWithPath: authDirectoryPath, isDirectory: true)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        struct LocalAuthPayload: Decodable {
            var type: String?
            var email: String?
            var plan_type: String?
            var account_id: String?
            var priority: Int?
            var codexkit_local_account_id: String?
        }

        return urls.compactMap { url in
            guard url.pathExtension.lowercased() == "json",
                  let data = try? Data(contentsOf: url),
                  let payload = try? JSONDecoder().decode(LocalAuthPayload.self, from: data) else {
                return nil
            }

            return CLIProxyAPIManagementListResponse.FileEntry(
                name: url.lastPathComponent,
                type: payload.type,
                email: payload.email,
                authIndex: nil,
                account: nil,
                accountType: nil,
                idToken: .init(
                    planType: payload.plan_type,
                    chatGPTAccountID: payload.account_id
                ),
                status: nil,
                statusMessage: nil,
                disabled: nil,
                unavailable: nil,
                nextRetryAfter: nil,
                priority: payload.priority,
                localAccountID: payload.codexkit_local_account_id
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func localTokenAccounts(repoRootPath: String?) -> [TokenAccount] {
        guard let authDirectoryPath = self.localConfiguration(repoRootPath: repoRootPath).authDirectoryPath,
              authDirectoryPath.isEmpty == false else {
            return []
        }
        let directoryURL = URL(fileURLWithPath: authDirectoryPath, isDirectory: true)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        struct LocalTokenPayload: Decodable {
            var type: String?
            var email: String?
            var plan_type: String?
            var account_id: String?
            var access_token: String?
            var refresh_token: String?
            var id_token: String?
            var expired: String?
        }

        let formatter = ISO8601DateFormatter()
        var accountsByIdentity: [String: TokenAccount] = [:]

        for url in urls.sorted(by: { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }) {
            guard url.pathExtension.lowercased() == "json",
                  let data = try? Data(contentsOf: url),
                  let payload = try? JSONDecoder().decode(LocalTokenPayload.self, from: data),
                  payload.type?.lowercased() == "codex",
                  let email = payload.email,
                  let accessToken = payload.access_token,
                  let refreshToken = payload.refresh_token,
                  let idToken = payload.id_token else {
                continue
            }

            let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let normalizedPlanType = payload.plan_type?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .nilIfEmpty ?? "free"
            let accountId = url.deletingPathExtension().lastPathComponent
            let remoteAccountId = payload.account_id ?? accountId
            let account = TokenAccount(
                email: email,
                accountId: accountId,
                openAIAccountId: remoteAccountId,
                accessToken: accessToken,
                refreshToken: refreshToken,
                idToken: idToken,
                expiresAt: payload.expired.flatMap { formatter.date(from: $0) },
                planType: normalizedPlanType
            )
            let identity = "\(normalizedEmail)|\(remoteAccountId.lowercased())|\(normalizedPlanType)"
            accountsByIdentity[identity] = accountsByIdentity[identity] ?? account
        }

        return Array(accountsByIdentity.values).sorted {
            let left = $0.email.localizedCaseInsensitiveCompare($1.email)
            if left != .orderedSame {
                return left == .orderedAscending
            }
            return $0.accountId.localizedCaseInsensitiveCompare($1.accountId) == .orderedAscending
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        self.isEmpty ? nil : self
    }
}
