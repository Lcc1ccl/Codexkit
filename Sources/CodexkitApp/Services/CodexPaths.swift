import Foundation

struct CodexNativeTarget: Equatable, Hashable {
    let rootURL: URL
    let codexRootURL: URL
    let authURL: URL
    let configTomlURL: URL
    let authBackupURL: URL
    let configBackupURL: URL
    let authPreAPIBackupURL: URL
    let configPreAPIBackupURL: URL
    let canonicalRootPath: String
    let isGlobal: Bool
}

enum CLIProxyAPIRuntimeRootAuthority: String, Equatable {
    case legacyCodexkitHome = "legacy-codexkit-home"
}

enum CLIProxyAPIBundledRuntimeRole: String, Equatable {
    case launchSource = "launch-source"
}

struct CLIProxyAPIRuntimeRootPolicy: Equatable {
    let authority: CLIProxyAPIRuntimeRootAuthority
    let bundledRuntimeRole: CLIProxyAPIBundledRuntimeRole
    let bundledMutableStateAllowed: Bool
    let liveRootURL: URL
    let stagedRootURL: URL

    var liveConfigURL: URL {
        self.liveRootURL.appendingPathComponent("config.yaml")
    }

    var stagedConfigURL: URL {
        self.stagedRootURL.appendingPathComponent("config.yaml")
    }

    var liveAuthDirectoryURL: URL {
        self.liveRootURL.appendingPathComponent("auth", isDirectory: true)
    }

    var stagedAuthDirectoryURL: URL {
        self.stagedRootURL.appendingPathComponent("auth", isDirectory: true)
    }
}

enum CodexPaths {
    private static let stateSQLiteDefaultVersion = 5
    private static let logsSQLiteDefaultVersion = 2

    static var realHome: URL {
        if let override = ProcessInfo.processInfo.environment["CODEXBAR_HOME"],
           override.isEmpty == false {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        if let pw = getpwuid(getuid()), let pwDir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: pwDir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    static var codexRoot: URL {
        self.realHome.appendingPathComponent(".codex", isDirectory: true)
    }

    static var codexBarRoot: URL {
        self.realHome.appendingPathComponent(".codexkit", isDirectory: true)
    }

    static var authURL: URL { self.codexRoot.appendingPathComponent("auth.json") }
    static var tokenPoolURL: URL { self.codexRoot.appendingPathComponent("token_pool.json") }
    static var configTomlURL: URL { self.codexRoot.appendingPathComponent("config.toml") }
    static var providerSecretsURL: URL { self.codexRoot.appendingPathComponent("provider-secrets.env") }
    static var stateSQLiteURL: URL {
        self.versionedSQLiteURL(
            basename: "state",
            defaultVersion: self.stateSQLiteDefaultVersion
        )
    }
    static var logsSQLiteURL: URL {
        self.versionedSQLiteURL(
            basename: "logs",
            defaultVersion: self.logsSQLiteDefaultVersion
        )
    }
    static var oauthFlowsDirectoryURL: URL { self.codexBarRoot.appendingPathComponent("oauth-flows", isDirectory: true) }
    static var menuHostRootURL: URL { self.codexBarRoot.appendingPathComponent("menu-host", isDirectory: true) }
    static var menuHostAppURL: URL { self.menuHostRootURL.appendingPathComponent("Codexkit.app", isDirectory: true) }
    static var menuHostLeaseURL: URL { self.menuHostRootURL.appendingPathComponent("host.pid") }

    static var barConfigURL: URL { self.codexBarRoot.appendingPathComponent("config.json") }
    static var costCacheURL: URL { self.codexBarRoot.appendingPathComponent("cost-cache.json") }
    static var costSessionCacheURL: URL { self.codexBarRoot.appendingPathComponent("cost-session-cache.json") }
    static var cliProxyAPIQuotaSnapshotURL: URL { self.codexBarRoot.appendingPathComponent("cliproxyapi-quota-snapshot.json") }
    static var switchJournalURL: URL { self.codexBarRoot.appendingPathComponent("switch-journal.jsonl") }
    static var managedLaunchRootURL: URL { self.codexBarRoot.appendingPathComponent("managed-launch", isDirectory: true) }
    static var managedLaunchBinURL: URL { self.managedLaunchRootURL.appendingPathComponent("bin", isDirectory: true) }
    static var managedLaunchHitsURL: URL { self.managedLaunchRootURL.appendingPathComponent("hits", isDirectory: true) }
    static var managedLaunchStateURL: URL { self.managedLaunchRootURL.appendingPathComponent("last-launch.json") }
    static var openAIGatewayRootURL: URL { self.codexBarRoot.appendingPathComponent("openai-gateway", isDirectory: true) }
    static var openAIGatewayStateURL: URL { self.openAIGatewayRootURL.appendingPathComponent("state.json") }
    static var openAIGatewayRouteJournalURL: URL { self.openAIGatewayRootURL.appendingPathComponent("route-journal.json") }
    static var openRouterGatewayRootURL: URL { self.codexBarRoot.appendingPathComponent("openrouter-gateway", isDirectory: true) }
    static var openRouterGatewayStateURL: URL { self.openRouterGatewayRootURL.appendingPathComponent("state.json") }
    static var cliProxyAPIRuntimeRootPolicy: CLIProxyAPIRuntimeRootPolicy {
        let liveRootURL = self.codexBarRoot.appendingPathComponent("cliproxyapi", isDirectory: true)
        let stagedRootURL = self.codexBarRoot.appendingPathComponent("cliproxyapi-staged", isDirectory: true)
        return CLIProxyAPIRuntimeRootPolicy(
            authority: .legacyCodexkitHome,
            bundledRuntimeRole: .launchSource,
            bundledMutableStateAllowed: false,
            liveRootURL: liveRootURL,
            stagedRootURL: stagedRootURL
        )
    }
    static var cliProxyAPIRuntimeRootURL: URL { self.cliProxyAPIRuntimeRootPolicy.liveRootURL }
    static var cliProxyAPIStagedRuntimeRootURL: URL { self.cliProxyAPIRuntimeRootPolicy.stagedRootURL }
    static var cliProxyAPIConfigURL: URL { self.cliProxyAPIRuntimeRootPolicy.liveConfigURL }
    static var cliProxyAPIStagedConfigURL: URL { self.cliProxyAPIRuntimeRootPolicy.stagedConfigURL }
    static var cliProxyAPIAuthDirectoryURL: URL { self.cliProxyAPIRuntimeRootPolicy.liveAuthDirectoryURL }
    static var cliProxyAPIStagedAuthDirectoryURL: URL { self.cliProxyAPIRuntimeRootPolicy.stagedAuthDirectoryURL }

    static var configBackupURL: URL { self.codexRoot.appendingPathComponent("config.toml.bak-codexkit-last") }
    static var authBackupURL: URL { self.codexRoot.appendingPathComponent("auth.json.bak-codexkit-last") }
    static var configPreAPIBackupURL: URL { self.codexRoot.appendingPathComponent("config.toml.bak-codexkit-pre-api-service") }
    static var authPreAPIBackupURL: URL { self.codexRoot.appendingPathComponent("auth.json.bak-codexkit-pre-api-service") }

    static func globalNativeTarget() -> CodexNativeTarget {
        self.makeNativeTarget(rootURL: self.realHome, isGlobal: true)
    }

    static func primaryNativeTarget(for desktopSettings: CodexBarDesktopSettings) -> CodexNativeTarget {
        if desktopSettings.accountActivationScope.mode != .specificPaths {
            return self.globalNativeTarget()
        }

        if let first = self.effectiveNativeTargets(for: desktopSettings).first {
            return first
        }

        return self.globalNativeTarget()
    }

    static func effectiveNativeTargets(for desktopSettings: CodexBarDesktopSettings) -> [CodexNativeTarget] {
        var targets: [CodexNativeTarget] = []
        var seen: Set<String> = []

        func append(_ target: CodexNativeTarget) {
            guard seen.insert(target.canonicalRootPath).inserted else { return }
            targets.append(target)
        }

        if desktopSettings.accountActivationScope.mode != .specificPaths {
            append(self.globalNativeTarget())
        }

        if desktopSettings.accountActivationScope.mode != .global {
            for rootPath in desktopSettings.accountActivationScope.rootPaths {
                append(self.makeNativeTarget(rootPath: rootPath, isGlobal: false))
            }
        }

        return targets
    }

    static func removedNativeTargets(
        from previousDesktopSettings: CodexBarDesktopSettings,
        to currentDesktopSettings: CodexBarDesktopSettings
    ) -> [CodexNativeTarget] {
        let current = Set(self.effectiveNativeTargets(for: currentDesktopSettings).map(\.canonicalRootPath))
        return self.effectiveNativeTargets(for: previousDesktopSettings).filter { current.contains($0.canonicalRootPath) == false }
    }

    static func ensureDirectories() throws {
        try FileManager.default.createDirectory(at: self.codexBarRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: self.oauthFlowsDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: self.managedLaunchBinURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: self.managedLaunchHitsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: self.openAIGatewayRootURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: self.openRouterGatewayRootURL, withIntermediateDirectories: true)
    }

    static func writeSecureFile(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let tempURL = directory.appendingPathComponent("." + url.lastPathComponent + "." + UUID().uuidString + ".tmp")
        try data.write(to: tempURL, options: .atomic)
        try self.applySecurePermissions(to: tempURL)

        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.moveItem(at: tempURL, to: url)
        try self.applySecurePermissions(to: url)
    }

    static func backupFileIfPresent(from source: URL, to destination: URL) throws {
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        let data = try Data(contentsOf: source)
        try self.writeSecureFile(data, to: destination)
    }

    private static func makeNativeTarget(rootPath: String, isGlobal: Bool) -> CodexNativeTarget {
        self.makeNativeTarget(
            rootURL: URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL,
            isGlobal: isGlobal
        )
    }

    private static func makeNativeTarget(rootURL: URL, isGlobal: Bool) -> CodexNativeTarget {
        let standardizedRootURL = rootURL.standardizedFileURL
        let codexRootURL = standardizedRootURL.appendingPathComponent(".codex", isDirectory: true)
        return CodexNativeTarget(
            rootURL: standardizedRootURL,
            codexRootURL: codexRootURL,
            authURL: codexRootURL.appendingPathComponent("auth.json"),
            configTomlURL: codexRootURL.appendingPathComponent("config.toml"),
            authBackupURL: codexRootURL.appendingPathComponent("auth.json.bak-codexkit-last"),
            configBackupURL: codexRootURL.appendingPathComponent("config.toml.bak-codexkit-last"),
            authPreAPIBackupURL: codexRootURL.appendingPathComponent("auth.json.bak-codexkit-pre-api-service"),
            configPreAPIBackupURL: codexRootURL.appendingPathComponent("config.toml.bak-codexkit-pre-api-service"),
            canonicalRootPath: standardizedRootURL.path,
            isGlobal: isGlobal
        )
    }

    private static func applySecurePermissions(to url: URL) throws {
        try FileManager.default.setAttributes([
            .posixPermissions: NSNumber(value: Int16(0o600)),
        ], ofItemAtPath: url.path)
    }

    private static func versionedSQLiteURL(
        basename: String,
        defaultVersion: Int
    ) -> URL {
        let version = self.latestSQLiteVersion(basename: basename) ?? defaultVersion
        return self.codexRoot.appendingPathComponent("\(basename)_\(version).sqlite")
    }

    private static func latestSQLiteVersion(basename: String) -> Int? {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: self.codexRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let prefix = "\(basename)_"
        return urls.compactMap { url -> Int? in
            guard url.pathExtension == "sqlite" else { return nil }
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true else {
                return nil
            }

            let filename = url.deletingPathExtension().lastPathComponent
            guard filename.hasPrefix(prefix) else { return nil }
            let suffix = String(filename.dropFirst(prefix.count))
            return Int(suffix)
        }
        .max()
    }
}
