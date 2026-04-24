import Foundation

enum SettingsSaveRequestApplier {
    static func apply(
        _ requests: SettingsSaveRequests,
        to config: inout CodexBarConfig
    ) throws {
        self.apply(requests.openAIAccount, to: &config)
        self.apply(requests.openAIUsage, to: &config)
        self.apply(requests.openAIGeneral, to: &config)
        try self.apply(requests.desktop, to: &config)
        self.apply(requests.cliProxyAPI, to: &config)
    }

    static func apply(_ request: OpenAIAccountSettingsUpdate?, to config: inout CodexBarConfig) {
        guard let request else { return }
        if let accountOrder = request.accountOrder {
            config.setOpenAIAccountOrder(accountOrder)
        }
        if let accountOrderingMode = request.accountOrderingMode {
            config.setOpenAIAccountOrderingMode(accountOrderingMode)
        }
        if let manualActivationBehavior = request.manualActivationBehavior {
            config.setOpenAIManualActivationBehavior(manualActivationBehavior)
        }
        if let serviceTier = request.serviceTier {
            config.global.serviceTier = serviceTier == .standard ? nil : serviceTier
        }
    }

    static func apply(_ request: OpenAIUsageSettingsUpdate?, to config: inout CodexBarConfig) {
        guard let request else { return }
        config.openAI.usageDisplayMode = request.usageDisplayMode
        config.openAI.quotaSort = CodexBarOpenAISettings.QuotaSortSettings(
            plusRelativeWeight: request.plusRelativeWeight,
            proRelativeToPlusMultiplier: request.proRelativeToPlusMultiplier,
            teamRelativeToPlusMultiplier: request.teamRelativeToPlusMultiplier
        )
    }

    static func apply(_ request: OpenAIGeneralSettingsUpdate?, to config: inout CodexBarConfig) {
        guard let request else { return }
        config.openAI.menuBarDisplay = CodexBarOpenAISettings.MenuBarDisplaySettings(
            quotaVisibility: request.menuBarQuotaVisibility,
            apiServiceStatusVisibility: request.menuBarAPIServiceStatusVisibility
        )
    }

    static func apply(_ request: DesktopSettingsUpdate?, to config: inout CodexBarConfig) throws {
        guard let request else { return }
        config.desktop.preferredCodexAppPath = try self.validatedPreferredCodexAppPath(
            from: request.preferredCodexAppPath
        )
        if let mode = request.accountActivationScopeMode {
            config.desktop.accountActivationScope = try self.validatedAccountActivationScope(
                mode: mode,
                rootPaths: request.accountActivationRootPaths ?? config.desktop.accountActivationScope.rootPaths
            )
        } else if let rootPaths = request.accountActivationRootPaths {
            config.desktop.accountActivationScope = try self.validatedAccountActivationScope(
                mode: config.desktop.accountActivationScope.mode,
                rootPaths: rootPaths
            )
        }
        if let codexkitUpdate = request.codexkitUpdate {
            config.desktop.codexkitUpdate = codexkitUpdate
        }
        if let cliProxyAPIUpdate = request.cliProxyAPIUpdate {
            config.desktop.cliProxyAPIUpdate = cliProxyAPIUpdate
        }
    }

    static func apply(_ request: CLIProxyAPISettingsUpdate?, to config: inout CodexBarConfig) {
        guard let request else { return }
        config.desktop.cliProxyAPI.enabled = request.enabled
        config.desktop.cliProxyAPI.host = request.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? CLIProxyAPIService.defaultHost
            : request.host.trimmingCharacters(in: .whitespacesAndNewlines)
        config.desktop.cliProxyAPI.port = max(1, request.port)
        config.desktop.cliProxyAPI.repositoryRootPath = nil
        config.desktop.cliProxyAPI.managementSecretKey = request.managementSecretKey?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        if let clientAPIKey = request.clientAPIKey {
            config.desktop.cliProxyAPI.clientAPIKey = clientAPIKey
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
        }
        config.desktop.cliProxyAPI.memberAccountIDs = Array(Set(request.memberAccountIDs.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty })).sorted()
        config.desktop.cliProxyAPI.restrictFreeAccounts = request.restrictFreeAccounts
        config.desktop.cliProxyAPI.routingStrategy = request.routingStrategy
        config.desktop.cliProxyAPI.switchProjectOnQuotaExceeded = request.switchProjectOnQuotaExceeded
        config.desktop.cliProxyAPI.switchPreviewModelOnQuotaExceeded = request.switchPreviewModelOnQuotaExceeded
        config.desktop.cliProxyAPI.requestRetry = max(0, request.requestRetry)
        config.desktop.cliProxyAPI.maxRetryInterval = max(0, request.maxRetryInterval)
        config.desktop.cliProxyAPI.disableCooling = request.disableCooling
        config.desktop.cliProxyAPI.memberPrioritiesByAccountID = request.memberPrioritiesByAccountID.reduce(into: [:]) { partial, entry in
            let key = entry.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard key.isEmpty == false else { return }
            partial[key] = max(0, entry.value)
        }
        if config.desktop.cliProxyAPI.managementSecretKey == nil {
            config.desktop.cliProxyAPI.managementSecretKey = CLIProxyAPIService.shared.generateManagementSecretKey()
        }
        if config.desktop.cliProxyAPI.clientAPIKey == nil {
            config.desktop.cliProxyAPI.clientAPIKey = self.generateDistinctClientAPIKey(
                managementSecretKey: config.desktop.cliProxyAPI.managementSecretKey
            )
        }
    }

    static func validatedPreferredCodexAppPath(from preferredCodexAppPath: String?) throws -> String? {
        let trimmedPreferredPath = preferredCodexAppPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedPreferredPath.isEmpty {
            return nil
        }

        guard let validatedPath = CodexDesktopLaunchProbeService
            .validatedPreferredCodexAppURL(from: trimmedPreferredPath)?
            .path else {
            throw TokenStoreError.invalidCodexAppPath
        }

        return validatedPath
    }

    static func validatedAccountActivationScope(
        mode: CodexBarActivationScopeMode,
        rootPaths: [String]
    ) throws -> CodexBarDesktopSettings.AccountActivationScope {
        let normalizedScope = CodexBarDesktopSettings.AccountActivationScope(
            mode: mode,
            rootPaths: rootPaths
        )

        if normalizedScope.mode != .global,
           normalizedScope.rootPaths.isEmpty {
            throw TokenStoreError.missingAccountActivationPath
        }

        if normalizedScope.mode == .global {
            return CodexBarDesktopSettings.AccountActivationScope(mode: .global, rootPaths: [])
        }

        return normalizedScope
    }
}

private extension SettingsSaveRequestApplier {
    static func generateDistinctClientAPIKey(managementSecretKey: String?) -> String {
        var generatedClientAPIKey = CLIProxyAPIService.shared.generateClientAPIKey()
        while generatedClientAPIKey == managementSecretKey {
            generatedClientAPIKey = CLIProxyAPIService.shared.generateClientAPIKey()
        }
        return generatedClientAPIKey
    }
}

private extension String {
    var nilIfEmpty: String? {
        self.isEmpty ? nil : self
    }
}
