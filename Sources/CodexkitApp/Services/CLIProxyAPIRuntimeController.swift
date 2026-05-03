import Foundation

@MainActor
protocol CLIProxyAPIRuntimeControlling {
    @discardableResult
    func applyConfiguration(_ settings: CodexBarDesktopSettings.CLIProxyAPISettings) -> Bool
    func adoptRunningServiceIfReusable(_ settings: CodexBarDesktopSettings.CLIProxyAPISettings) async -> Bool
    func stop()
    func reconfigureIfRunning(_ settings: CodexBarDesktopSettings.CLIProxyAPISettings)
}

@MainActor
final class CLIProxyAPIRuntimeController: LifecycleControlling {
    static let shared = CLIProxyAPIRuntimeController()
    private nonisolated static let skipRuntimeEnvironmentKey = "CODEXKIT_SKIP_CLIPROXYAPI_RUNTIME"
    private nonisolated static let startupHealthCheckAttempts = 8
    private nonisolated static let startupHealthCheckRetryDelayNanoseconds: UInt64 = 250_000_000

    private let service: CLIProxyAPIService
    private let authExporter: CLIProxyAPIAuthExporter
    private let managementService: CLIProxyAPIManagementService
    private var process: Process?
    private var monitorTask: Task<Void, Never>?
    private var quotaRefreshTask: Task<Void, Never>?
    private var appliedSettings: CodexBarDesktopSettings.CLIProxyAPISettings?

    init(
        service: CLIProxyAPIService = .shared,
        authExporter: CLIProxyAPIAuthExporter = CLIProxyAPIAuthExporter(),
        managementService: CLIProxyAPIManagementService = CLIProxyAPIManagementService()
    ) {
        self.service = service
        self.authExporter = authExporter
        self.managementService = managementService
    }

    func start() {
        guard TokenStore.shared.config.desktop.cliProxyAPI.enabled else { return }
        self.applyConfiguration(TokenStore.shared.config.desktop.cliProxyAPI)
    }

    func stop() {
        self.monitorTask?.cancel()
        self.monitorTask = nil
        self.quotaRefreshTask?.cancel()
        self.quotaRefreshTask = nil
        guard let process = self.process else {
            if self.appliedSettings != nil {
                self.updateState(status: .stopped, lastError: nil, pid: nil)
                self.appliedSettings = nil
            }
            return
        }
        if process.isRunning {
            process.terminate()
        }
        AppLifecycleDiagnostics.shared.recordEvent(
            type: "cliproxyapi_stopped",
            fields: ["pid": process.processIdentifier]
        )
        self.updateState(status: .stopped, lastError: nil, pid: nil)
        self.process = nil
        self.appliedSettings = nil
    }

    @discardableResult
    func applyConfiguration(_ settings: CodexBarDesktopSettings.CLIProxyAPISettings) -> Bool {
        let nextConfig = self.makeServiceConfig(from: settings)
        if Self.shouldSkipRuntimeLaunch() {
            self.monitorTask?.cancel()
            self.monitorTask = nil
            self.quotaRefreshTask?.cancel()
            self.quotaRefreshTask = nil
            self.process = nil
            self.appliedSettings = settings
            self.updateState(status: .stopped, lastError: nil, pid: nil, config: nextConfig)
            return true
        }

        if Self.shouldRestartProcess(
            isRunning: self.process?.isRunning == true,
            appliedSettings: self.appliedSettings,
            nextSettings: settings
        ) {
            self.stop()
        } else if self.process?.isRunning == true {
            do {
                _ = try self.service.writeConfig(nextConfig)
                self.appliedSettings = settings
                self.updateState(
                    status: .running,
                    lastError: nil,
                    pid: self.process?.processIdentifier,
                    config: nextConfig
                )
                return true
            } catch {
                self.updateState(
                    status: .failed,
                    lastError: error.localizedDescription,
                    pid: self.process?.processIdentifier,
                    config: nextConfig
                )
                return false
            }
        }

        let repoRoot = self.service.resolveBundledRepoRoot()
        guard self.service.hasManagedRuntime()
            || self.service.hasBundledRuntime(searchRoots: repoRoot.map { [$0] })
            || self.service.hasBundledRuntime() else {
            self.updateState(
                status: .failed,
                lastError: "Missing managed or bundled CLIProxyAPI runtime",
                pid: nil,
                config: nextConfig
            )
            AppLifecycleDiagnostics.shared.recordEvent(
                type: "cliproxyapi_start_skipped_missing_bundled_runtime",
                fields: ["port": settings.port]
            )
            return false
        }
        let config = nextConfig

        let memberAccounts = Self.resolvedMemberAccounts(from: TokenStore.shared.accounts, settings: settings)
        guard memberAccounts.isEmpty == false else {
            self.updateState(
                status: .failed,
                lastError: "No member accounts selected",
                pid: nil,
                config: nextConfig
            )
            return false
        }

        guard self.service.canBindTCPPort(host: config.host, port: config.port) else {
            self.updateState(
                status: .failed,
                lastError: "CLIProxyAPI port \(config.port) is already in use",
                pid: nil,
                config: nextConfig
            )
            return false
        }

        self.updateState(status: .starting, lastError: nil, pid: nil, config: nextConfig)

        do {
            try? self.service.clearStagedRuntime()
            var stagedConfig = config
            stagedConfig.authDirectory = CLIProxyAPIService.stagedAuthDirectoryURL
            _ = try self.authExporter.export(
                accounts: memberAccounts,
                prioritiesByAccountID: settings.memberPrioritiesByAccountID,
                to: CLIProxyAPIService.stagedAuthDirectoryURL
            )
            _ = try self.service.writeConfig(stagedConfig, staged: true)
            try self.service.promoteStagedRuntime(liveConfig: config)
            try? self.service.clearStagedRuntime()
            let process = self.service.makeLaunchProcess(repoRoot: repoRoot)
            process.terminationHandler = { [weak self] process in
                Task { @MainActor in
                    self?.handleTermination(process)
                }
            }
            try process.run()
            self.process = process
            self.appliedSettings = settings
            self.updateState(status: .starting, lastError: nil, pid: process.processIdentifier, config: config)
            Task { @MainActor [weak self] in
                guard let self else { return }
                _ = await Self.waitForHealthyStartup(
                    maxAttempts: Self.startupHealthCheckAttempts,
                    retryDelayNanoseconds: Self.startupHealthCheckRetryDelayNanoseconds,
                    isProcessRunning: { [weak self] in
                        self?.process?.isRunning == true
                    },
                    healthCheck: { [service = self.service] in
                        try await service.checkHealth(config: config)
                    }
                )
                guard self.process?.isRunning == true else { return }
                await self.refreshHealth()
                guard self.process?.isRunning == true else { return }
                self.startMonitoring(config: TokenStore.shared.cliProxyAPIState.config)
            }
            AppLifecycleDiagnostics.shared.recordEvent(
                type: "cliproxyapi_started",
                fields: ["pid": process.processIdentifier, "port": config.port]
            )
            return true
        } catch {
            self.updateState(status: .failed, lastError: error.localizedDescription, pid: nil, config: config)
            AppLifecycleDiagnostics.shared.recordEvent(
                type: "cliproxyapi_start_failed",
                fields: ["port": config.port, "error": error.localizedDescription]
            )
            return false
        }
    }

    func adoptRunningServiceIfReusable(_ settings: CodexBarDesktopSettings.CLIProxyAPISettings) async -> Bool {
        let config = self.makeServiceConfig(from: settings)
        do {
            let healthy = try await self.service.checkHealth(config: config)
            guard healthy else {
                self.updateState(status: .failed, lastError: "Health check failed", pid: nil, config: config)
                return false
            }

            let remoteConfig = try await self.managementService.getConfig(config: config)
            let runtimeConfig = self.managementService.makeRuntimeConfiguration(
                response: remoteConfig,
                fallback: config
            )
            self.monitorTask?.cancel()
            self.monitorTask = nil
            self.quotaRefreshTask?.cancel()
            self.quotaRefreshTask = nil
            self.process = nil
            self.appliedSettings = settings
            self.updateState(status: .running, lastError: nil, pid: nil, config: runtimeConfig)
            return true
        } catch {
            self.updateState(
                status: .failed,
                lastError: self.classifyError(error),
                pid: nil,
                config: config
            )
            return false
        }
    }

    func reconfigureIfRunning(_ settings: CodexBarDesktopSettings.CLIProxyAPISettings) {
        guard self.process?.isRunning == true else { return }
        self.applyConfiguration(settings)
    }

    static func shouldRestartProcess(
        isRunning: Bool,
        appliedSettings: CodexBarDesktopSettings.CLIProxyAPISettings?,
        nextSettings: CodexBarDesktopSettings.CLIProxyAPISettings
    ) -> Bool {
        guard isRunning else { return false }
        guard let appliedSettings else { return true }
        return CLIProxyAPIServiceConfig(
            host: appliedSettings.host,
            port: appliedSettings.port,
            authDirectory: CLIProxyAPIService.authDirectoryURL,
            managementSecretKey: appliedSettings.managementSecretKey ?? "",
            clientAPIKey: appliedSettings.clientAPIKey ?? "",
            allowRemoteManagement: false,
            enabled: appliedSettings.enabled,
            routingStrategy: appliedSettings.routingStrategy,
            switchProjectOnQuotaExceeded: appliedSettings.switchProjectOnQuotaExceeded,
            switchPreviewModelOnQuotaExceeded: appliedSettings.switchPreviewModelOnQuotaExceeded,
            requestRetry: appliedSettings.requestRetry,
            maxRetryInterval: appliedSettings.maxRetryInterval,
            disableCooling: appliedSettings.disableCooling
        ) != CLIProxyAPIServiceConfig(
            host: nextSettings.host,
            port: nextSettings.port,
            authDirectory: CLIProxyAPIService.authDirectoryURL,
            managementSecretKey: nextSettings.managementSecretKey ?? "",
            clientAPIKey: nextSettings.clientAPIKey ?? "",
            allowRemoteManagement: false,
            enabled: nextSettings.enabled,
            routingStrategy: nextSettings.routingStrategy,
            switchProjectOnQuotaExceeded: nextSettings.switchProjectOnQuotaExceeded,
            switchPreviewModelOnQuotaExceeded: nextSettings.switchPreviewModelOnQuotaExceeded,
            requestRetry: nextSettings.requestRetry,
            maxRetryInterval: nextSettings.maxRetryInterval,
            disableCooling: nextSettings.disableCooling
        ) || appliedSettings.memberAccountIDs != nextSettings.memberAccountIDs
            || appliedSettings.restrictFreeAccounts != nextSettings.restrictFreeAccounts
            || appliedSettings.memberPrioritiesByAccountID != nextSettings.memberPrioritiesByAccountID
    }

    static func resolvedMemberAccounts(
        from accounts: [TokenAccount],
        settings: CodexBarDesktopSettings.CLIProxyAPISettings
    ) -> [TokenAccount] {
        let selectedAccountIDs = Set(settings.memberAccountIDs)
        return accounts.filter { account in
            guard selectedAccountIDs.contains(account.accountId) else { return false }
            if settings.restrictFreeAccounts && account.isExplicitFreePlanType {
                return false
            }
            return true
        }
    }

    static func waitForHealthyStartup(
        maxAttempts: Int,
        retryDelayNanoseconds: UInt64,
        isProcessRunning: @escaping () -> Bool,
        healthCheck: @escaping () async throws -> Bool,
        sleep: @escaping (UInt64) async -> Void = { nanoseconds in
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    ) async -> Bool {
        let attempts = max(1, maxAttempts)

        for attempt in 0 ..< attempts {
            guard isProcessRunning() else { return false }
            if (try? await healthCheck()) == true {
                return true
            }

            guard attempt < attempts - 1 else { break }
            await sleep(retryDelayNanoseconds)
        }

        return false
    }

    func refreshHealth() async {
        let state = TokenStore.shared.cliProxyAPIState
        do {
            let healthy = try await self.service.checkHealth(config: state.config)
            let runtimeConfig = healthy
                ? (try? await self.managementService.getConfig(config: state.config)).map {
                    self.managementService.makeRuntimeConfiguration(response: $0, fallback: state.config)
                } ?? state.config
                : state.config
            let files = healthy ? (try? await self.managementService.listAuthFiles(config: runtimeConfig)) : nil
            let usage = healthy ? (try? await self.managementService.getUsageStatistics(config: runtimeConfig)) : nil
            let quotaSnapshot = healthy ? (try? await self.managementService.getQuotaSnapshot(config: runtimeConfig)) : state.quotaSnapshot
            let modelIDs = try? await self.resolveModelIDs(config: runtimeConfig, files: files ?? [])
            let accountUsageItems = healthy
                ? CLIProxyAPIManagementService.makeAccountUsageItems(
                    files: files ?? [],
                    usage: usage,
                    localAccounts: TokenStore.shared.accounts
                )
                : state.accountUsageItems
            let observedAuthFiles = healthy
                ? CLIProxyAPIManagementService.makeObservedAuthFiles(
                    files: files ?? [],
                    localAccounts: TokenStore.shared.accounts
                )
                : state.observedAuthFiles
            self.updateState(
                status: healthy ? .running : .degraded,
                lastError: healthy ? nil : "Health check failed",
                pid: self.process?.processIdentifier,
                authFileCount: files?.count ?? state.authFileCount,
                modelCount: modelIDs?.count ?? state.modelCount,
                modelIDs: modelIDs ?? state.modelIDs,
                totalRequests: usage?.usage.total_requests ?? state.totalRequests,
                failedRequests: usage?.failed_requests ?? usage?.usage.failure_count ?? state.failedRequests,
                totalTokens: usage?.usage.total_tokens ?? state.totalTokens,
                requestsByDay: usage?.usage.requests_by_day ?? state.requestsByDay,
                requestsByHour: usage?.usage.requests_by_hour ?? state.requestsByHour,
                tokensByDay: usage?.usage.tokens_by_day ?? state.tokensByDay,
                tokensByHour: usage?.usage.tokens_by_hour ?? state.tokensByHour,
                config: runtimeConfig,
                quotaSnapshot: quotaSnapshot,
                accountUsageItems: accountUsageItems,
                observedAuthFiles: observedAuthFiles
            )
        } catch {
            self.updateState(
                status: .failed,
                lastError: self.classifyError(error),
                pid: self.process?.processIdentifier,
                authFileCount: state.authFileCount,
                modelCount: state.modelCount,
                modelIDs: state.modelIDs,
                totalRequests: state.totalRequests,
                failedRequests: state.failedRequests,
                totalTokens: state.totalTokens,
                requestsByDay: state.requestsByDay,
                requestsByHour: state.requestsByHour,
                tokensByDay: state.tokensByDay,
                tokensByHour: state.tokensByHour,
                quotaSnapshot: state.quotaSnapshot,
                accountUsageItems: state.accountUsageItems,
                observedAuthFiles: state.observedAuthFiles
            )
        }
    }

    func refreshQuotaSnapshot(trigger _: String = "manual") async {
        let state = TokenStore.shared.cliProxyAPIState
        guard state.config.enabled else { return }
        guard let process, process.isRunning else {
            await self.refreshHealth()
            return
        }
        guard self.quotaRefreshTask == nil else {
            await self.quotaRefreshTask?.value
            return
        }

        let config = state.config
        self.quotaRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.quotaRefreshTask = nil }
            do {
                let snapshot = try await self.managementService.refreshQuotaSnapshot(config: config)
                self.updateState(
                    status: TokenStore.shared.cliProxyAPIState.status,
                    lastError: nil,
                    pid: self.process?.processIdentifier,
                    quotaSnapshot: snapshot,
                    accountUsageItems: TokenStore.shared.cliProxyAPIState.accountUsageItems,
                    observedAuthFiles: TokenStore.shared.cliProxyAPIState.observedAuthFiles
                )
            } catch {
                let current = TokenStore.shared.cliProxyAPIState
                self.updateState(
                    status: current.status == .running ? .degraded : current.status,
                    lastError: self.classifyError(error),
                    pid: self.process?.processIdentifier,
                    quotaSnapshot: current.quotaSnapshot,
                    accountUsageItems: current.accountUsageItems,
                    observedAuthFiles: current.observedAuthFiles
                )
            }
        }

        await self.quotaRefreshTask?.value
    }

    private func startMonitoring(config: CLIProxyAPIServiceConfig) {
        self.monitorTask?.cancel()
        self.monitorTask = Task { [weak self] in
            guard let self else { return }
            while Task.isCancelled == false {
                try? await Task.sleep(for: .seconds(5))
                guard Task.isCancelled == false else { return }
                if self.process?.isRunning != true {
                    self.updateState(status: .degraded, lastError: "Process stopped", pid: nil)
                    return
                }
                do {
                    let healthy = try await self.service.checkHealth(config: config)
                    let runtimeConfig = healthy
                        ? (try? await self.managementService.getConfig(config: config)).map {
                            self.managementService.makeRuntimeConfiguration(response: $0, fallback: config)
                        } ?? config
                        : config
                    let files = healthy ? (try? await self.managementService.listAuthFiles(config: runtimeConfig)) : nil
                    let usage = healthy ? (try? await self.managementService.getUsageStatistics(config: runtimeConfig)) : nil
                    let quotaSnapshot = healthy
                        ? (try? await self.managementService.getQuotaSnapshot(config: runtimeConfig))
                            ?? TokenStore.shared.cliProxyAPIState.quotaSnapshot
                        : TokenStore.shared.cliProxyAPIState.quotaSnapshot
                    let modelIDs = try? await self.resolveModelIDs(config: runtimeConfig, files: files ?? [])
                    let accountUsageItems = healthy
                        ? CLIProxyAPIManagementService.makeAccountUsageItems(
                            files: files ?? [],
                            usage: usage,
                            localAccounts: TokenStore.shared.accounts
                        )
                        : TokenStore.shared.cliProxyAPIState.accountUsageItems
                    let observedAuthFiles = healthy
                        ? CLIProxyAPIManagementService.makeObservedAuthFiles(
                            files: files ?? [],
                            localAccounts: TokenStore.shared.accounts
                        )
                        : TokenStore.shared.cliProxyAPIState.observedAuthFiles
                    self.updateState(
                        status: healthy ? .running : .degraded,
                        lastError: healthy ? nil : "Health check failed",
                        pid: self.process?.processIdentifier,
                        authFileCount: files?.count ?? TokenStore.shared.cliProxyAPIState.authFileCount,
                        modelCount: modelIDs?.count ?? TokenStore.shared.cliProxyAPIState.modelCount,
                        modelIDs: modelIDs ?? TokenStore.shared.cliProxyAPIState.modelIDs,
                        totalRequests: usage?.usage.total_requests ?? TokenStore.shared.cliProxyAPIState.totalRequests,
                        failedRequests: usage?.failed_requests ?? usage?.usage.failure_count ?? TokenStore.shared.cliProxyAPIState.failedRequests,
                        totalTokens: usage?.usage.total_tokens ?? TokenStore.shared.cliProxyAPIState.totalTokens,
                        requestsByDay: usage?.usage.requests_by_day ?? TokenStore.shared.cliProxyAPIState.requestsByDay,
                        requestsByHour: usage?.usage.requests_by_hour ?? TokenStore.shared.cliProxyAPIState.requestsByHour,
                        tokensByDay: usage?.usage.tokens_by_day ?? TokenStore.shared.cliProxyAPIState.tokensByDay,
                        tokensByHour: usage?.usage.tokens_by_hour ?? TokenStore.shared.cliProxyAPIState.tokensByHour,
                        config: runtimeConfig,
                        quotaSnapshot: quotaSnapshot,
                        accountUsageItems: accountUsageItems,
                        observedAuthFiles: observedAuthFiles
                    )
                } catch {
                    self.updateState(
                        status: .degraded,
                        lastError: self.classifyError(error),
                        pid: self.process?.processIdentifier,
                        authFileCount: TokenStore.shared.cliProxyAPIState.authFileCount,
                        modelCount: TokenStore.shared.cliProxyAPIState.modelCount,
                        modelIDs: TokenStore.shared.cliProxyAPIState.modelIDs,
                        totalRequests: TokenStore.shared.cliProxyAPIState.totalRequests,
                        failedRequests: TokenStore.shared.cliProxyAPIState.failedRequests,
                        totalTokens: TokenStore.shared.cliProxyAPIState.totalTokens,
                        requestsByDay: TokenStore.shared.cliProxyAPIState.requestsByDay,
                        requestsByHour: TokenStore.shared.cliProxyAPIState.requestsByHour,
                        tokensByDay: TokenStore.shared.cliProxyAPIState.tokensByDay,
                        tokensByHour: TokenStore.shared.cliProxyAPIState.tokensByHour,
                        quotaSnapshot: TokenStore.shared.cliProxyAPIState.quotaSnapshot,
                        accountUsageItems: TokenStore.shared.cliProxyAPIState.accountUsageItems,
                        observedAuthFiles: TokenStore.shared.cliProxyAPIState.observedAuthFiles
                    )
                }
            }
        }
    }

    private func handleTermination(_ process: Process) {
        self.monitorTask?.cancel()
        self.monitorTask = nil
        self.process = nil
        let reason = self.terminationDescription(process)
        let nextStatus: CLIProxyAPIServiceState.RuntimeStatus = process.terminationStatus == 0 ? .stopped : .failed
        self.updateState(status: nextStatus, lastError: reason, pid: nil)
    }

    private func updateState(
        status: CLIProxyAPIServiceState.RuntimeStatus,
        lastError: String?,
        pid: Int32?,
        authFileCount: Int? = nil,
        modelCount: Int? = nil,
        modelIDs: [String]? = nil,
        totalRequests: Int? = nil,
        failedRequests: Int? = nil,
        totalTokens: Int? = nil,
        requestsByDay: [String: Int]? = nil,
        requestsByHour: [String: Int]? = nil,
        tokensByDay: [String: Int]? = nil,
        tokensByHour: [String: Int]? = nil,
        config: CLIProxyAPIServiceConfig? = nil,
        quotaSnapshot: CLIProxyAPIQuotaSnapshot? = nil,
        accountUsageItems: [CLIProxyAPIAccountUsageItem]? = nil,
        observedAuthFiles: [CLIProxyAPIObservedAuthFile]? = nil
    ) {
        let current = TokenStore.shared.cliProxyAPIState
        TokenStore.shared.updateCLIProxyAPIState(
            CLIProxyAPIServiceState(
                config: config ?? current.config,
                status: status,
                lastError: lastError,
                pid: pid,
                authFileCount: authFileCount ?? current.authFileCount,
                modelCount: modelCount ?? current.modelCount,
                modelIDs: modelIDs ?? current.modelIDs,
                totalRequests: totalRequests ?? current.totalRequests,
                failedRequests: failedRequests ?? current.failedRequests,
                totalTokens: totalTokens ?? current.totalTokens,
                requestsByDay: requestsByDay ?? current.requestsByDay,
                requestsByHour: requestsByHour ?? current.requestsByHour,
                tokensByDay: tokensByDay ?? current.tokensByDay,
                tokensByHour: tokensByHour ?? current.tokensByHour,
                quotaSnapshot: quotaSnapshot ?? current.quotaSnapshot,
                accountUsageItems: accountUsageItems ?? current.accountUsageItems,
                observedAuthFiles: observedAuthFiles ?? current.observedAuthFiles
            )
        )
    }

    private func resolveModelIDs(
        config: CLIProxyAPIServiceConfig,
        files: [CLIProxyAPIManagementListResponse.FileEntry]
    ) async throws -> [String] {
        guard files.isEmpty == false else { return [] }
        var allModelIDs: Set<String> = []
        for file in files {
            let models = try await self.managementService.listModels(config: config, authFileName: file.name)
            models.forEach { allModelIDs.insert($0.id) }
        }
        return allModelIDs.sorted()
    }

    private func classifyError(_ error: Error) -> String {
        if let managementError = error as? CLIProxyAPIManagementServiceError {
            switch managementError {
            case let .server(statusCode, message):
                if statusCode == 401 || statusCode == 403 {
                    return "Management authentication required"
                }
                return message
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotConnectToHost:
                return "Cannot connect to CLIProxyAPI"
            case .userAuthenticationRequired:
                return "Management authentication required"
            case .badServerResponse:
                return "CLIProxyAPI returned an invalid response"
            case .timedOut:
                return "CLIProxyAPI request timed out"
            default:
                return urlError.localizedDescription
            }
        }
        return error.localizedDescription
    }

    private func terminationDescription(_ process: Process) -> String? {
        if process.terminationStatus == 0 {
            return nil
        }
        switch process.terminationReason {
        case .uncaughtSignal:
            return "CLIProxyAPI terminated by signal \(process.terminationStatus)"
        case .exit:
            return "CLIProxyAPI exited with status \(process.terminationStatus)"
        @unknown default:
            return "CLIProxyAPI terminated unexpectedly"
        }
    }

    private static func shouldSkipRuntimeLaunch(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        guard let rawValue = environment[self.skipRuntimeEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            rawValue.isEmpty == false else {
            return false
        }

        switch rawValue {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
    }

    private func makeServiceConfig(
        from settings: CodexBarDesktopSettings.CLIProxyAPISettings
    ) -> CLIProxyAPIServiceConfig {
        let managementSecretKey = settings.managementSecretKey ?? self.service.generateManagementSecretKey()
        return CLIProxyAPIServiceConfig(
            host: settings.host,
            port: settings.port,
            authDirectory: CLIProxyAPIService.authDirectoryURL,
            managementSecretKey: managementSecretKey,
            clientAPIKey: settings.clientAPIKey ?? self.service.generateDistinctClientAPIKey(
                managementSecretKey: managementSecretKey
            ),
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
}

extension CLIProxyAPIRuntimeController: CLIProxyAPIRuntimeControlling {}

extension CLIProxyAPIRuntimeControlling {
    func adoptRunningServiceIfReusable(_ settings: CodexBarDesktopSettings.CLIProxyAPISettings) async -> Bool {
        false
    }
}
