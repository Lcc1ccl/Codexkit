import Foundation

enum CodexSyncIntent: Equatable {
    case directSwitch
    case enableAPIService
    case disableAPIServiceAndSwitch
    case disableAPIServiceRestoreDirect
}

protocol CodexSynchronizing {
    func synchronize(config: CodexBarConfig) throws
    func synchronize(config: CodexBarConfig, intent: CodexSyncIntent) throws
    func cleanupRemovedTargets(
        previousDesktopSettings: CodexBarDesktopSettings,
        currentDesktopSettings: CodexBarDesktopSettings
    ) throws
    func restoreNativeConfiguration(
        desktopSettings: CodexBarDesktopSettings
    ) throws -> CodexNativeRestoreResult
}

extension CodexSynchronizing {
    func synchronize(config: CodexBarConfig, intent _: CodexSyncIntent) throws {
        try self.synchronize(config: config)
    }

    func cleanupRemovedTargets(
        previousDesktopSettings _: CodexBarDesktopSettings,
        currentDesktopSettings _: CodexBarDesktopSettings
    ) throws {}

    func restoreNativeConfiguration(
        desktopSettings _: CodexBarDesktopSettings
    ) throws -> CodexNativeRestoreResult {
        .init(auth: .unchanged, config: .unchanged)
    }
}

enum CodexNativeRestoreDisposition: Equatable {
    case restoredFromBackup
    case removedInjectedState
    case unchanged
}

struct CodexNativeRestoreResult: Equatable {
    var auth: CodexNativeRestoreDisposition
    var config: CodexNativeRestoreDisposition

    var status: String {
        if self.auth == .restoredFromBackup || self.config == .restoredFromBackup {
            return "restored"
        }
        if self.auth == .removedInjectedState || self.config == .removedInjectedState {
            return "partial"
        }
        return "unchanged"
    }
}

enum CodexSyncError: LocalizedError {
    case missingActiveProvider
    case missingActiveAccount
    case missingOAuthTokens
    case missingAPIKey
    case missingProviderBaseURL
    case missingOpenRouterModel
    case invalidManagedConfigStructure(String)
    case invalidManagedConfigOutput(String)

    var errorDescription: String? {
        switch self {
        case .missingActiveProvider: return "未找到当前激活的 provider"
        case .missingActiveAccount: return "未找到当前激活的账号"
        case .missingOAuthTokens: return "当前 OAuth 账号缺少必要 token"
        case .missingAPIKey: return "当前 API Key 账号缺少密钥"
        case .missingProviderBaseURL: return "当前自定义 provider 缺少 base URL"
        case .missingOpenRouterModel: return "OpenRouter 需要先选择或输入模型 ID"
        case let .invalidManagedConfigStructure(message): return message
        case let .invalidManagedConfigOutput(message): return message
        }
    }
}

struct CodexSyncService: CodexSynchronizing {
    private static let managedAuthMarkerKey = "codexkit_managed"
    private static let customModelProviderKey = "custom"
    private static let customModelProviderWireAPI = "responses"
    private static let apiServiceProviderName = "codexkit"

    private enum TargetTransition {
        case restorePreAPIServiceSnapshot
        case rewriteDirect
        case rewriteAPIService
    }

    private enum NativeWriteMode {
        case officialOAuthDirect(OfficialOAuthPayload)
        case customProviderDirect(APIKeyPayload, ManagedProviderConfig)
        case apiServiceInjected(APIKeyPayload, ManagedProviderConfig)

        var authPayload: AuthPayload {
            switch self {
            case let .officialOAuthDirect(payload):
                return .officialOAuth(payload)
            case let .customProviderDirect(payload, _),
                 let .apiServiceInjected(payload, _):
                return .apiKey(payload)
            }
        }

        var managedProviderConfig: ManagedProviderConfig? {
            switch self {
            case .officialOAuthDirect:
                return nil
            case let .customProviderDirect(_, config),
                 let .apiServiceInjected(_, config):
                return config
            }
        }
    }

    private enum AuthPayload {
        case officialOAuth(OfficialOAuthPayload)
        case apiKey(APIKeyPayload)
    }

    private struct OfficialOAuthPayload {
        let accessToken: String
        let refreshToken: String
        let idToken: String
        let accountID: String
        let clientID: String?
        let lastRefresh: Date
    }

    private struct APIKeyPayload {
        let apiKey: String
    }

    private struct ManagedProviderConfig {
        let name: String
        let baseURL: String
    }

    private let ensureDirectories: () throws -> Void
    private let backupFileIfPresent: (URL, URL) throws -> Void
    private let writeSecureFile: (Data, URL) throws -> Void
    private let readString: (URL) -> String?
    private let readData: (URL) -> Data?
    private let fileExists: (URL) -> Bool
    private let removeFileIfPresent: (URL) throws -> Void
    private let oauthAccountIDFromAuthData: (Data?) -> String?

    init(
        ensureDirectories: @escaping () throws -> Void = { try CodexPaths.ensureDirectories() },
        backupFileIfPresent: @escaping (URL, URL) throws -> Void = { source, destination in
            try CodexPaths.backupFileIfPresent(from: source, to: destination)
        },
        writeSecureFile: @escaping (Data, URL) throws -> Void = { data, url in
            try CodexPaths.writeSecureFile(data, to: url)
        },
        readString: @escaping (URL) -> String? = { url in
            try? String(contentsOf: url, encoding: .utf8)
        },
        readData: @escaping (URL) -> Data? = { url in
            try? Data(contentsOf: url)
        },
        fileExists: @escaping (URL) -> Bool = { url in
            FileManager.default.fileExists(atPath: url.path)
        },
        removeFileIfPresent: @escaping (URL) throws -> Void = { url in
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            try FileManager.default.removeItem(at: url)
        },
        oauthAccountIDFromAuthData: @escaping (Data?) -> String? = { data in
            CodexBarConfigStore().oauthAccountID(fromAuthJSONData: data)
        }
    ) {
        self.ensureDirectories = ensureDirectories
        self.backupFileIfPresent = backupFileIfPresent
        self.writeSecureFile = writeSecureFile
        self.readString = readString
        self.readData = readData
        self.fileExists = fileExists
        self.removeFileIfPresent = removeFileIfPresent
        self.oauthAccountIDFromAuthData = oauthAccountIDFromAuthData
    }

    func synchronize(config: CodexBarConfig) throws {
        let intent: CodexSyncIntent = config.desktop.cliProxyAPI.enabled ? .enableAPIService : .directSwitch
        try self.synchronize(config: config, intent: intent)
    }

    func synchronize(config: CodexBarConfig, intent: CodexSyncIntent) throws {
        guard let provider = config.activeProvider() else { throw CodexSyncError.missingActiveProvider }
        guard let account = config.activeAccount() else { throw CodexSyncError.missingActiveAccount }
        let writeMode = try self.resolveWriteMode(
            config: config,
            provider: provider,
            account: account,
            intent: intent
        )
        let targets = CodexPaths.effectiveNativeTargets(for: config.desktop)
        let previousSnapshots = targets.reduce(into: [String: (auth: Data?, toml: Data?)]()) { partial, target in
            partial[target.canonicalRootPath] = (
                auth: self.readData(target.authURL),
                toml: self.readData(target.configTomlURL)
            )
        }
        let previousPreAPISnapshots = targets.reduce(into: [String: (auth: Data?, toml: Data?)]()) { partial, target in
            partial[target.canonicalRootPath] = (
                auth: self.readData(target.authPreAPIBackupURL),
                toml: self.readData(target.configPreAPIBackupURL)
            )
        }

        for target in targets {
            try self.backupFileIfPresent(target.configTomlURL, target.configBackupURL)
            try self.backupFileIfPresent(target.authURL, target.authBackupURL)
        }

        do {
            for target in targets {
                switch self.transition(for: target, intent: intent, targetAccountID: account.id) {
                case .restorePreAPIServiceSnapshot:
                    try self.restoreSnapshot(self.readData(target.authPreAPIBackupURL), at: target.authURL)
                    try self.restoreSnapshot(self.readData(target.configPreAPIBackupURL), at: target.configTomlURL)
                case .rewriteDirect, .rewriteAPIService:
                    let renderedToml = try self.renderConfigTOML(
                        existingText: self.readString(target.configTomlURL) ?? "",
                        global: config.global,
                        mode: writeMode
                    )
                    guard let tomlData = renderedToml.data(using: .utf8) else { continue }
                    let authData = try self.renderAuthJSON(mode: writeMode)
                    try self.writeSecureFile(authData, target.authURL)
                    try self.writeSecureFile(tomlData, target.configTomlURL)
                }
            }

            if intent == .enableAPIService {
                try self.refreshPreAPIServiceSnapshots(from: previousSnapshots, targets: targets)
            }
        } catch {
            for target in targets {
                let snapshot = previousSnapshots[target.canonicalRootPath]
                try? self.restoreSnapshot(snapshot?.auth, at: target.authURL)
                try? self.restoreSnapshot(snapshot?.toml, at: target.configTomlURL)
                let preAPISnapshot = previousPreAPISnapshots[target.canonicalRootPath]
                try? self.restoreSnapshot(preAPISnapshot?.auth, at: target.authPreAPIBackupURL)
                try? self.restoreSnapshot(preAPISnapshot?.toml, at: target.configPreAPIBackupURL)
            }
            throw error
        }
    }

    func restoreNativeConfiguration() throws -> CodexNativeRestoreResult {
        try self.restoreNativeConfiguration(desktopSettings: CodexBarDesktopSettings())
    }

    func restoreNativeConfiguration(
        desktopSettings: CodexBarDesktopSettings
    ) throws -> CodexNativeRestoreResult {
        return try self.restoreTargets(CodexPaths.effectiveNativeTargets(for: desktopSettings))
    }

    func cleanupRemovedTargets(
        previousDesktopSettings: CodexBarDesktopSettings,
        currentDesktopSettings: CodexBarDesktopSettings
    ) throws {
        let removedTargets = CodexPaths.removedNativeTargets(
            from: previousDesktopSettings,
            to: currentDesktopSettings
        )
        guard removedTargets.isEmpty == false else { return }
        _ = try self.restoreTargets(removedTargets)
    }

    private func restoreSnapshot(_ snapshot: Data?, at url: URL) throws {
        if let snapshot {
            try self.writeSecureFile(snapshot, url)
        } else if self.fileExists(url) {
            try self.removeFileIfPresent(url)
        }
    }

    private func refreshPreAPIServiceSnapshots(
        from snapshots: [String: (auth: Data?, toml: Data?)],
        targets: [CodexNativeTarget]
    ) throws {
        for target in targets {
            let snapshot = snapshots[target.canonicalRootPath]
            try self.restoreSnapshot(snapshot?.auth, at: target.authPreAPIBackupURL)
            try self.restoreSnapshot(snapshot?.toml, at: target.configPreAPIBackupURL)
        }
    }

    private func transition(
        for target: CodexNativeTarget,
        intent: CodexSyncIntent,
        targetAccountID: String
    ) -> TargetTransition {
        switch intent {
        case .directSwitch:
            return .rewriteDirect
        case .enableAPIService:
            return .rewriteAPIService
        case .disableAPIServiceAndSwitch, .disableAPIServiceRestoreDirect:
            guard let preAPIAuthData = self.readData(target.authPreAPIBackupURL),
                  self.readData(target.configPreAPIBackupURL) != nil,
                  self.oauthAccountIDFromAuthData(preAPIAuthData) == targetAccountID else {
                return .rewriteDirect
            }
            return .restorePreAPIServiceSnapshot
        }
    }

    private func restoreTargets(_ targets: [CodexNativeTarget]) throws -> CodexNativeRestoreResult {
        var authResult: CodexNativeRestoreDisposition = .unchanged
        var configResult: CodexNativeRestoreDisposition = .unchanged

        for target in targets {
            let nextAuthResult: CodexNativeRestoreDisposition
            if let backupAuth = self.readData(target.authBackupURL) {
                try self.writeSecureFile(backupAuth, target.authURL)
                nextAuthResult = .restoredFromBackup
            } else if self.isManagedAuthFile(at: target.authURL) {
                try self.removeFileIfPresent(target.authURL)
                nextAuthResult = .removedInjectedState
            } else {
                nextAuthResult = .unchanged
            }

            let nextConfigResult: CodexNativeRestoreDisposition
            if let backupConfig = self.readData(target.configBackupURL) {
                try self.writeSecureFile(backupConfig, target.configTomlURL)
                nextConfigResult = .restoredFromBackup
            } else if let existingText = self.readString(target.configTomlURL) {
                let sanitized = self.removeInjectedSettings(from: existingText)
                if sanitized != existingText {
                    try self.writeSecureFile(Data(sanitized.utf8), target.configTomlURL)
                    nextConfigResult = .removedInjectedState
                } else {
                    nextConfigResult = .unchanged
                }
            } else {
                nextConfigResult = .unchanged
            }

            authResult = self.mergeDisposition(authResult, with: nextAuthResult)
            configResult = self.mergeDisposition(configResult, with: nextConfigResult)
        }

        return CodexNativeRestoreResult(auth: authResult, config: configResult)
    }

    private func mergeDisposition(
        _ current: CodexNativeRestoreDisposition,
        with next: CodexNativeRestoreDisposition
    ) -> CodexNativeRestoreDisposition {
        if current == .restoredFromBackup || next == .restoredFromBackup {
            return .restoredFromBackup
        }
        if current == .removedInjectedState || next == .removedInjectedState {
            return .removedInjectedState
        }
        return .unchanged
    }

    private func isManagedAuthFile(at url: URL) -> Bool {
        guard let data = self.readData(url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object[Self.managedAuthMarkerKey] as? Bool == true else {
            return false
        }
        return true
    }

    private func resolveWriteMode(
        config: CodexBarConfig,
        provider: CodexBarProvider,
        account: CodexBarProviderAccount,
        intent: CodexSyncIntent
    ) throws -> NativeWriteMode {
        if intent == .enableAPIService {
            guard let clientAPIKey = config.desktop.cliProxyAPI.clientAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines),
                  clientAPIKey.isEmpty == false else {
                throw CodexSyncError.missingAPIKey
            }
            return .apiServiceInjected(
                APIKeyPayload(apiKey: clientAPIKey),
                ManagedProviderConfig(
                    name: Self.apiServiceProviderName,
                    baseURL: "http://\(config.desktop.cliProxyAPI.host):\(config.desktop.cliProxyAPI.port)/v1"
                )
            )
        }

        switch provider.kind {
        case .openAIOAuth:
            guard let accessToken = account.accessToken,
                  let refreshToken = account.refreshToken,
                  let idToken = account.idToken,
                  let accountID = account.openAIAccountId else {
                throw CodexSyncError.missingOAuthTokens
            }
            let clientID = account.oauthClientID?.trimmingCharacters(in: .whitespacesAndNewlines)
            return .officialOAuthDirect(
                OfficialOAuthPayload(
                    accessToken: accessToken,
                    refreshToken: refreshToken,
                    idToken: idToken,
                    accountID: accountID,
                    clientID: clientID?.isEmpty == false ? clientID : nil,
                    lastRefresh: account.tokenLastRefreshAt ?? account.lastRefresh ?? Date()
                )
            )
        case .openAICompatible:
            guard let apiKey = account.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines),
                  apiKey.isEmpty == false else {
                throw CodexSyncError.missingAPIKey
            }
            guard let baseURL = provider.baseURL?.trimmingCharacters(in: .whitespacesAndNewlines),
                  baseURL.isEmpty == false else {
                throw CodexSyncError.missingProviderBaseURL
            }
            return .customProviderDirect(
                APIKeyPayload(apiKey: apiKey),
                ManagedProviderConfig(
                    name: self.normalizedProviderName(
                        provider.label,
                        fallback: "Custom"
                    ),
                    baseURL: baseURL
                )
            )
        case .openRouter:
            guard let apiKey = account.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines),
                  apiKey.isEmpty == false else {
                throw CodexSyncError.missingAPIKey
            }
            let trimmedBaseURL = provider.baseURL?.trimmingCharacters(in: .whitespacesAndNewlines)
            let baseURL = (trimmedBaseURL?.isEmpty == false ? trimmedBaseURL : nil) ?? "https://openrouter.ai/api/v1"
            return .customProviderDirect(
                APIKeyPayload(apiKey: apiKey),
                ManagedProviderConfig(
                    name: self.normalizedProviderName(
                        provider.label,
                        fallback: "OpenRouter"
                    ),
                    baseURL: baseURL
                )
            )
        }
    }

    private func renderAuthJSON(mode: NativeWriteMode) throws -> Data {
        let object: [String: Any]
        switch mode.authPayload {
        case let .officialOAuth(payload):
            var authObject: [String: Any] = [
                Self.managedAuthMarkerKey: true,
                "auth_mode": "chatgpt",
                "OPENAI_API_KEY": NSNull(),
                "last_refresh": ISO8601DateFormatter().string(from: payload.lastRefresh),
                "tokens": [
                    "access_token": payload.accessToken,
                    "refresh_token": payload.refreshToken,
                    "id_token": payload.idToken,
                    "account_id": payload.accountID,
                ],
            ]
            if let clientID = payload.clientID, clientID.isEmpty == false {
                authObject["client_id"] = clientID
            }
            object = authObject
        case let .apiKey(payload):
            object = [
                Self.managedAuthMarkerKey: true,
                "auth_mode": "apikey",
                "OPENAI_API_KEY": payload.apiKey,
            ]
        }

        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    private func renderConfigTOML(
        existingText: String,
        global: CodexBarGlobalSettings,
        mode: NativeWriteMode
    ) throws -> String {
        try self.validateManagedConfigStructure(existingText)

        var text = existingText
        for key in [
            "model_provider",
            "service_tier",
            "openai_base_url",
            "model",
            "review_model",
            "model_reasoning_effort",
            "oss_provider",
            "model_catalog_json",
            "preferred_auth_method",
        ] {
            text = self.removeTopLevelSetting(text, key: key)
        }

        text = self.removeBlock(text, key: "OpenAI")
        text = self.removeBlock(text, key: "openai")
        text = self.removeBlock(text, key: Self.customModelProviderKey)

        if let serviceTier = global.serviceTier?.configValue {
            text = self.upsertTopLevelSetting(text, key: "service_tier", value: self.quote(serviceTier))
        }

        if let providerConfiguration = mode.managedProviderConfig {
            text = self.upsertTopLevelSetting(
                text,
                key: "model_provider",
                value: self.quote(Self.customModelProviderKey)
            )
            text = self.upsertModelProviderBlock(
                text,
                key: Self.customModelProviderKey,
                name: providerConfiguration.name,
                baseURL: providerConfiguration.baseURL
            )
        }

        let normalized = self.normalizeManagedConfigText(text)
        try self.validateManagedConfigOutput(
            normalized,
            mode: mode,
            serviceTierValue: global.serviceTier?.configValue
        )
        return normalized
    }

    private func quote(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func normalizedProviderName(_ rawValue: String, fallback: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func validateManagedConfigStructure(_ text: String) throws {
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[[model_providers") {
                throw CodexSyncError.invalidManagedConfigStructure("config.toml 中的 [[model_providers]] 结构不受支持")
            }
            if self.matchesTopLevelSettingLine(line, key: "model_providers") {
                throw CodexSyncError.invalidManagedConfigStructure("config.toml 中的 model_providers 顶层键与受管写入冲突")
            }
        }
    }

    private func upsertTopLevelSetting(_ text: String, key: String, value: String) -> String {
        let line = "\(key) = \(value)"
        var lines = text.components(separatedBy: "\n")
        var firstHeaderIndex: Int?
        var didReplace = false
        var currentHeader: String?
        var index = 0

        while index < lines.count {
            let currentLine = lines[index]
            if let header = self.tableHeader(from: currentLine) {
                currentHeader = header
                firstHeaderIndex = firstHeaderIndex ?? index
            }

            if currentHeader == nil, self.matchesTopLevelSettingLine(currentLine, key: key) {
                if didReplace == false {
                    lines[index] = line
                    didReplace = true
                    index += 1
                } else {
                    lines.remove(at: index)
                }
                continue
            }

            index += 1
        }

        guard didReplace == false else {
            return lines.joined(separator: "\n")
        }

        let insertionIndex = firstHeaderIndex ?? lines.count
        lines.insert(line, at: insertionIndex)
        return lines.joined(separator: "\n")
    }

    private func removeTopLevelSetting(_ text: String, key: String) -> String {
        var lines = text.components(separatedBy: "\n")
        var currentHeader: String?
        var index = 0

        while index < lines.count {
            let currentLine = lines[index]
            if let header = self.tableHeader(from: currentLine) {
                currentHeader = header
            }

            if currentHeader == nil, self.matchesTopLevelSettingLine(currentLine, key: key) {
                lines.remove(at: index)
                continue
            }
            index += 1
        }

        return lines.joined(separator: "\n")
    }

    private func removeBlock(_ text: String, key: String) -> String {
        let exactHeader = "[model_providers.\(key)]"
        let nestedPrefix = "[model_providers.\(key)."
        var filtered: [String] = []
        var skipping = false

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("["),
               trimmed.hasSuffix("]") {
                if trimmed == exactHeader || trimmed.hasPrefix(nestedPrefix) {
                    skipping = true
                    continue
                }
                if skipping {
                    skipping = false
                }
            }

            if skipping == false {
                filtered.append(String(line))
            }
        }

        return filtered.joined(separator: "\n")
    }

    private func removeInjectedSettings(from text: String) -> String {
        var sanitized = text
        sanitized = self.removeTopLevelSetting(sanitized, key: "model_provider")
        sanitized = self.removeTopLevelSetting(sanitized, key: "model")
        sanitized = self.removeTopLevelSetting(sanitized, key: "review_model")
        sanitized = self.removeTopLevelSetting(sanitized, key: "model_reasoning_effort")
        sanitized = self.removeTopLevelSetting(sanitized, key: "service_tier")
        sanitized = self.removeTopLevelSetting(sanitized, key: "oss_provider")
        sanitized = self.removeTopLevelSetting(sanitized, key: "openai_base_url")
        sanitized = self.removeTopLevelSetting(sanitized, key: "model_catalog_json")
        sanitized = self.removeTopLevelSetting(sanitized, key: "preferred_auth_method")
        sanitized = self.removeBlock(sanitized, key: "OpenAI")
        sanitized = self.removeBlock(sanitized, key: "openai")
        sanitized = self.removeBlock(sanitized, key: Self.customModelProviderKey)
        return self.normalizeManagedConfigText(sanitized)
    }

    private func upsertModelProviderBlock(
        _ text: String,
        key: String,
        name: String,
        baseURL: String
    ) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Custom"
            : name.trimmingCharacters(in: .whitespacesAndNewlines)
        let block = """
        [model_providers.\(key)]
        name = \(self.quote(trimmedName))
        wire_api = \(self.quote(Self.customModelProviderWireAPI))
        base_url = \(self.quote(baseURL))
        requires_openai_auth = true
        """

        let sanitized = self.removeBlock(text, key: key)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard sanitized.isEmpty == false else {
            return block + "\n"
        }
        return sanitized + "\n\n" + block + "\n"
    }

    private func validateManagedConfigOutput(
        _ text: String,
        mode: NativeWriteMode,
        serviceTierValue: String?
    ) throws {
        try self.validateManagedConfigStructure(text)

        for forbiddenKey in ["model", "review_model", "model_reasoning_effort"] {
            if self.hasTopLevelSetting(text, key: forbiddenKey) {
                throw CodexSyncError.invalidManagedConfigOutput("config.toml 仍包含禁止写入的 \(forbiddenKey)")
            }
        }

        if let serviceTierValue {
            guard self.hasTopLevelSetting(text, key: "service_tier", value: self.quote(serviceTierValue)) else {
                throw CodexSyncError.invalidManagedConfigOutput("config.toml 未按预期写入 service_tier")
            }
        } else if self.hasTopLevelSetting(text, key: "service_tier") {
            throw CodexSyncError.invalidManagedConfigOutput("config.toml 不应写入 service_tier")
        }

        switch mode {
        case .officialOAuthDirect:
            if self.hasTopLevelSetting(text, key: "model_provider") {
                throw CodexSyncError.invalidManagedConfigOutput("官方 OAuth 直连不应写入 model_provider")
            }
            if text.contains("[model_providers.\(Self.customModelProviderKey)]") {
                throw CodexSyncError.invalidManagedConfigOutput("官方 OAuth 直连不应写入 custom provider block")
            }
        case let .customProviderDirect(_, provider), let .apiServiceInjected(_, provider):
            guard self.hasTopLevelSetting(text, key: "model_provider", value: self.quote(Self.customModelProviderKey)) else {
                throw CodexSyncError.invalidManagedConfigOutput("config.toml 未按预期写入 model_provider = custom")
            }
            let expectedBlock = """
            [model_providers.\(Self.customModelProviderKey)]
            name = \(self.quote(provider.name))
            wire_api = \(self.quote(Self.customModelProviderWireAPI))
            base_url = \(self.quote(provider.baseURL))
            requires_openai_auth = true
            """
            guard text.contains(expectedBlock) else {
                throw CodexSyncError.invalidManagedConfigOutput("config.toml 未按预期写入受管 custom provider block")
            }
        }
    }

    private func normalizeManagedConfigText(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n\n\n", with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? "" : normalized + "\n"
    }

    private func tableHeader(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("["),
              trimmed.hasSuffix("]"),
              trimmed.hasPrefix("[[") == false,
              trimmed.contains("=") == false else {
            return nil
        }
        return String(trimmed.dropFirst().dropLast())
    }

    private func matchesTopLevelSettingLine(_ line: String, key: String) -> Bool {
        guard let regex = try? NSRegularExpression(
            pattern: #"^\s*#(key)\s*="#.replacingOccurrences(
                of: "#(key)",
                with: NSRegularExpression.escapedPattern(for: key)
            )
        ) else {
            return false
        }
        let range = NSRange(line.startIndex..., in: line)
        return regex.firstMatch(in: line, range: range) != nil
    }

    private func hasTopLevelSetting(_ text: String, key: String, value: String? = nil) -> Bool {
        for line in text.components(separatedBy: "\n") {
            if self.matchesTopLevelSettingLine(line, key: key) == false {
                continue
            }
            guard let value else { return true }
            return line.trimmingCharacters(in: .whitespaces) == "\(key) = \(value)"
        }
        return false
    }
}
