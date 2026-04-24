import Darwin
import Foundation

struct CLIProxyAPIHealthResponse: Decodable, Equatable {
    var status: String?
}

final class CLIProxyAPIService {
    struct BundledRuntimeDescriptor: Decodable, Equatable {
        var source: String?
        var delivery: String?
        var version: String?
        var executableRelativePath: String?
        var rootURL: URL?

        enum CodingKeys: String, CodingKey {
            case source
            case delivery
            case version
            case executableRelativePath = "executable_relative_path"
            case rootURL
        }
    }

    struct LocalConfiguration: Equatable {
        var host: String?
        var port: Int?
        var managementSecretKey: String?
        var clientAPIKey: String?
        var authDirectoryPath: String?
        var routingStrategy: CLIProxyAPIRoutingStrategy
        var switchProjectOnQuotaExceeded: Bool
        var switchPreviewModelOnQuotaExceeded: Bool
        var requestRetry: Int
        var maxRetryInterval: Int
        var disableCooling: Bool

        init(
            host: String? = nil,
            port: Int? = nil,
            managementSecretKey: String? = nil,
            clientAPIKey: String? = nil,
            authDirectoryPath: String? = nil,
            routingStrategy: CLIProxyAPIRoutingStrategy = .roundRobin,
            switchProjectOnQuotaExceeded: Bool = true,
            switchPreviewModelOnQuotaExceeded: Bool = true,
            requestRetry: Int = 3,
            maxRetryInterval: Int = 30,
            disableCooling: Bool = false
        ) {
            self.host = host
            self.port = port
            self.managementSecretKey = managementSecretKey
            self.clientAPIKey = CLIProxyAPIService.normalizedSecret(clientAPIKey)
            self.authDirectoryPath = authDirectoryPath
            self.routingStrategy = routingStrategy
            self.switchProjectOnQuotaExceeded = switchProjectOnQuotaExceeded
            self.switchPreviewModelOnQuotaExceeded = switchPreviewModelOnQuotaExceeded
            self.requestRetry = max(0, requestRetry)
            self.maxRetryInterval = max(0, maxRetryInterval)
            self.disableCooling = disableCooling
        }
    }

    static let shared = CLIProxyAPIService()
    static let defaultHost = "127.0.0.1"

    private let fileManager: FileManager
    private let session: URLSession
    private let environment: [String: String]
    private let currentDirectoryURL: URL

    var processEnvironment: [String: String] { self.environment }

    init(
        fileManager: FileManager = .default,
        session: URLSession = .shared,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        currentDirectoryURL: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    ) {
        self.fileManager = fileManager
        self.session = session
        self.environment = environment
        self.currentDirectoryURL = currentDirectoryURL
    }

    static var runtimeRootURL: URL {
        CodexPaths.codexBarRoot.appendingPathComponent("cliproxyapi", isDirectory: true)
    }

    static var stagedRuntimeRootURL: URL {
        CodexPaths.codexBarRoot.appendingPathComponent("cliproxyapi-staged", isDirectory: true)
    }

    static var configURL: URL {
        self.runtimeRootURL.appendingPathComponent("config.yaml")
    }

    static var stagedConfigURL: URL {
        self.stagedRuntimeRootURL.appendingPathComponent("config.yaml")
    }

    static var authDirectoryURL: URL {
        self.runtimeRootURL.appendingPathComponent("auth", isDirectory: true)
    }

    static var stagedAuthDirectoryURL: URL {
        self.stagedRuntimeRootURL.appendingPathComponent("auth", isDirectory: true)
    }

    static var bundledServiceRelativePath: String { "CLIProxyAPIServiceBundle/CLIProxyAPI" }
    static var bundledManifestRelativePath: String { "CLIProxyAPIServiceBundle/bundle-manifest.json" }
    static var bundledExecutableRelativePath: String {
        #if arch(arm64)
        "CLIProxyAPIServiceBundle/bin/cli-proxy-api-darwin-arm64"
        #elseif arch(x86_64)
        "CLIProxyAPIServiceBundle/bin/cli-proxy-api-darwin-x86_64"
        #else
        "CLIProxyAPIServiceBundle/bin/cli-proxy-api-darwin-universal"
        #endif
    }

    func defaultConfig(
        host: String = CLIProxyAPIService.defaultHost,
        port: Int? = nil,
        managementSecretKey: String? = nil,
        clientAPIKey: String? = nil
    ) -> CLIProxyAPIServiceConfig {
        let resolvedManagementSecretKey = managementSecretKey ?? self.generateManagementSecretKey()
        return CLIProxyAPIServiceConfig(
            host: host,
            port: port ?? self.generateRandomAvailablePort(),
            authDirectory: Self.authDirectoryURL,
            managementSecretKey: resolvedManagementSecretKey,
            clientAPIKey: clientAPIKey ?? self.generateDistinctClientAPIKey(managementSecretKey: resolvedManagementSecretKey),
            allowRemoteManagement: false,
            enabled: false
        )
    }

    func generateManagementSecretKey() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }

    func generateClientAPIKey() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }

    func generateDistinctClientAPIKey(managementSecretKey: String?) -> String {
        var generatedClientAPIKey = self.generateClientAPIKey()
        while generatedClientAPIKey == managementSecretKey {
            generatedClientAPIKey = self.generateClientAPIKey()
        }
        return generatedClientAPIKey
    }

    func generateRandomAvailablePort() -> Int {
        Int(self.reserveTCPPort(host: Self.defaultHost, requestedPort: 0) ?? UInt16.random(in: 20000...59999))
    }

    func canBindTCPPort(host: String, port: Int) -> Bool {
        guard (1...65535).contains(port) else { return false }
        return self.reserveTCPPort(host: host, requestedPort: UInt16(port)) != nil
    }

    func ensureRuntimeDirectories(staged: Bool = false) throws {
        let rootURL = staged ? Self.stagedRuntimeRootURL : Self.runtimeRootURL
        let authURL = staged ? Self.stagedAuthDirectoryURL : Self.authDirectoryURL
        try self.fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try self.fileManager.createDirectory(at: authURL, withIntermediateDirectories: true)
    }

    func renderConfigYAML(_ config: CLIProxyAPIServiceConfig) -> String {
        var lines = [
            "host: \"\(Self.escapedYAMLString(config.host))\"",
            "port: \(config.port)",
            "auth-dir: \"\(Self.escapedYAMLString(config.authDirectory.path))\""
        ]

        if let clientAPIKey = Self.normalizedSecret(config.clientAPIKey) {
            lines.append("api-keys:")
            lines.append("  - \"\(Self.escapedYAMLString(clientAPIKey))\"")
        }

        lines.append(contentsOf: [
            "request-retry: \(config.requestRetry)",
            "max-retry-interval: \(config.maxRetryInterval)",
            "disable-cooling: \(config.disableCooling ? "true" : "false")",
            "quota-exceeded:",
            "  switch-project: \(config.switchProjectOnQuotaExceeded ? "true" : "false")",
            "  switch-preview-model: \(config.switchPreviewModelOnQuotaExceeded ? "true" : "false")",
            "routing:",
            "  strategy: \"\(config.routingStrategy.rawValue)\"",
            "remote-management:",
            "  allow-remote: \(config.allowRemoteManagement ? "true" : "false")",
            "  secret-key: \"\(Self.escapedYAMLString(config.managementSecretKey))\""
        ])

        return lines.joined(separator: "\n")
    }

    @discardableResult
    func writeConfig(_ config: CLIProxyAPIServiceConfig, staged: Bool = false) throws -> URL {
        try self.ensureRuntimeDirectories(staged: staged)
        let yaml = self.renderConfigYAML(config)
        let data = Data(yaml.utf8)
        let targetURL = staged ? Self.stagedConfigURL : Self.configURL
        try CodexPaths.writeSecureFile(data, to: targetURL)
        return targetURL
    }

    func promoteStagedRuntime(liveConfig: CLIProxyAPIServiceConfig) throws {
        try self.ensureRuntimeDirectories()

        if self.fileManager.fileExists(atPath: Self.authDirectoryURL.path) {
            let existing = try self.fileManager.contentsOfDirectory(at: Self.authDirectoryURL, includingPropertiesForKeys: nil)
            for url in existing where url.pathExtension.lowercased() == "json" {
                try? self.fileManager.removeItem(at: url)
            }
        }

        if self.fileManager.fileExists(atPath: Self.stagedAuthDirectoryURL.path) {
            let stagedFiles = try self.fileManager.contentsOfDirectory(at: Self.stagedAuthDirectoryURL, includingPropertiesForKeys: nil)
            for url in stagedFiles where url.pathExtension.lowercased() == "json" {
                let data = try Data(contentsOf: url)
                try CodexPaths.writeSecureFile(data, to: Self.authDirectoryURL.appendingPathComponent(url.lastPathComponent))
            }
        }

        _ = try self.writeConfig(liveConfig, staged: false)
    }

    func clearStagedRuntime() throws {
        guard self.fileManager.fileExists(atPath: Self.stagedRuntimeRootURL.path) else { return }
        try self.fileManager.removeItem(at: Self.stagedRuntimeRootURL)
    }

    func parseConfigYAML(_ yaml: String) -> LocalConfiguration {
        var parsed = LocalConfiguration()
        var currentSection: String?

        for rawLine in yaml.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.isEmpty == false, trimmed.hasPrefix("#") == false else { continue }

            let leadingSpaces = line.prefix { $0 == " " }.count
            if leadingSpaces == 0 {
                currentSection = trimmed.hasSuffix(":") ? String(trimmed.dropLast()) : nil
            }

            let normalizedLine = trimmed.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? trimmed
            if leadingSpaces > 0,
               currentSection == "api-keys",
               let listValue = Self.listItemValue(from: normalizedLine),
               parsed.clientAPIKey == nil {
                parsed.clientAPIKey = listValue.nilIfEmpty
                continue
            }
            let keyValue = normalizedLine.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard keyValue.count == 2 else { continue }

            let key = keyValue[0].trimmingCharacters(in: .whitespaces)
            let value = Self.unquoted(keyValue[1].trimmingCharacters(in: .whitespaces))

            if leadingSpaces == 0 {
                switch key {
                case "host":
                    parsed.host = value.nilIfEmpty
                case "port":
                    parsed.port = Int(value)
                case "auth-dir":
                    parsed.authDirectoryPath = value.nilIfEmpty
                case "request-retry":
                    parsed.requestRetry = max(0, Int(value) ?? parsed.requestRetry)
                case "max-retry-interval":
                    parsed.maxRetryInterval = max(0, Int(value) ?? parsed.maxRetryInterval)
                case "disable-cooling":
                    parsed.disableCooling = Self.boolValue(value) ?? parsed.disableCooling
                default:
                    break
                }
            } else {
                switch currentSection {
                case "remote-management":
                    if key == "secret-key" {
                        parsed.managementSecretKey = value.nilIfEmpty
                    }
                case "quota-exceeded":
                    if key == "switch-project" {
                        parsed.switchProjectOnQuotaExceeded = Self.boolValue(value) ?? parsed.switchProjectOnQuotaExceeded
                    } else if key == "switch-preview-model" {
                        parsed.switchPreviewModelOnQuotaExceeded = Self.boolValue(value) ?? parsed.switchPreviewModelOnQuotaExceeded
                    }
                case "routing":
                    if key == "strategy" {
                        parsed.routingStrategy = CLIProxyAPIRoutingStrategy(rawValue: value)
                    }
                default:
                    break
                }
            }
        }

        return parsed
    }

    func loadConfig(from url: URL) -> LocalConfiguration? {
        guard let data = try? Data(contentsOf: url),
              let yaml = String(data: data, encoding: .utf8) else {
            return nil
        }
        return self.parseConfigYAML(yaml)
    }

    func loadRuntimeConfig() -> LocalConfiguration? {
        self.loadConfig(from: Self.configURL)
    }

    func resolveConfiguredRepoRoot(
        explicitPath: String? = nil,
        environment: [String: String]? = nil
    ) -> URL? {
        let env = environment ?? self.environment
        let explicitCandidate = explicitPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let explicitCandidate, let url = self.validateRepoRootCandidate(explicitCandidate) {
            return url
        }
        if let envCandidate = env["CLIProxyAPI_REPO_ROOT"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           let url = self.validateRepoRootCandidate(envCandidate) {
            return url
        }
        return self.resolveBundledRepoRoot() ?? self.resolveBundledBundleRoot()
    }

    func resolveBundledRuntimeDescriptor(searchRoots: [URL]? = nil) -> BundledRuntimeDescriptor? {
        for bundleRoot in self.bundledBundleRootCandidates(searchRoots: searchRoots) {
            let manifestURL = bundleRoot.appendingPathComponent("bundle-manifest.json")
            if let data = try? Data(contentsOf: manifestURL),
               var descriptor = try? JSONDecoder().decode(BundledRuntimeDescriptor.self, from: data) {
                let repoRoot = bundleRoot.appendingPathComponent("CLIProxyAPI", isDirectory: true)
                descriptor.rootURL = self.isCLIProxyAPIRepoRoot(repoRoot) ? repoRoot : nil
                return descriptor
            }
        }

        for candidate in self.bundledRepoCandidates(searchRoots: searchRoots) {
            guard self.isCLIProxyAPIRepoRoot(candidate) else { continue }
            return BundledRuntimeDescriptor(
                source: nil,
                delivery: "bundled-service-tree",
                version: nil,
                executableRelativePath: nil,
                rootURL: candidate
            )
        }
        return nil
    }

    func resolveBundledBundleRoot(searchRoots: [URL]? = nil) -> URL? {
        self.bundledBundleRootCandidates(searchRoots: searchRoots).first
    }

    func hasBundledRuntime(searchRoots: [URL]? = nil) -> Bool {
        self.bundledExecutableURL(searchRoots: searchRoots) != nil || self.resolveBundledRepoRoot(searchRoots: searchRoots) != nil
    }

    func bundledExecutableURL(searchRoots: [URL]? = nil) -> URL? {
        let roots = searchRoots ?? self.defaultSearchRoots()
        for root in roots {
            var current = root.standardizedFileURL
            while true {
                let codexkitCandidate = current
                    .appendingPathComponent("Codexkit", isDirectory: true)
                    .appendingPathComponent("Sources", isDirectory: true)
                    .appendingPathComponent("CodexkitApp", isDirectory: true)
                    .appendingPathComponent("Bundled", isDirectory: true)
                    .appendingPathComponent(Self.bundledExecutableRelativePath)
                if self.isExecutableFile(codexkitCandidate) {
                    return codexkitCandidate
                }

                let appCandidate = current
                    .appendingPathComponent("Sources", isDirectory: true)
                    .appendingPathComponent("CodexkitApp", isDirectory: true)
                    .appendingPathComponent("Bundled", isDirectory: true)
                    .appendingPathComponent(Self.bundledExecutableRelativePath)
                if self.isExecutableFile(appCandidate) {
                    return appCandidate
                }

                let parent = current.deletingLastPathComponent()
                if parent.path == current.path { break }
                current = parent
            }
        }

        if let bundledResourceURL = Bundle.module.resourceURL?
            .appendingPathComponent(Self.bundledExecutableRelativePath),
           self.isExecutableFile(bundledResourceURL) {
            return bundledResourceURL
        }
        return nil
    }

    func resolveBundledRepoRoot(searchRoots: [URL]? = nil) -> URL? {
        self.resolveBundledRuntimeDescriptor(searchRoots: searchRoots)?.rootURL
    }

    func makeLaunchProcess(
        repoRoot: URL? = nil,
        configURL: URL = CLIProxyAPIService.configURL
    ) -> Process {
        let process = Process()
        let searchRoots = repoRoot.map { [$0] }
        let shouldPreferBundledExecutable: Bool
        if let repoRoot {
            if let bundledRepoRoot = self.resolveBundledRepoRoot(searchRoots: searchRoots) {
                shouldPreferBundledExecutable = bundledRepoRoot.standardizedFileURL.path == repoRoot.standardizedFileURL.path
            } else {
                shouldPreferBundledExecutable = false
            }
        } else {
            shouldPreferBundledExecutable = true
        }

        if shouldPreferBundledExecutable,
           let executableURL = self.bundledExecutableURL(searchRoots: searchRoots) {
            process.executableURL = executableURL
            process.arguments = ["-config", configURL.path]
            process.currentDirectoryURL = executableURL.deletingLastPathComponent()
        } else {
            guard let repoRoot else {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/false")
                process.arguments = []
                return process
            }
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [
                "go", "run", "./cmd/server/main.go",
                "-config", configURL.path,
            ]
            process.currentDirectoryURL = repoRoot
        }
        return process
    }

    func checkHealth(config: CLIProxyAPIServiceConfig) async throws -> Bool {
        let (data, response) = try await self.session.data(from: config.healthURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return false
        }
        if data.isEmpty { return true }
        if let payload = try? JSONDecoder().decode(CLIProxyAPIHealthResponse.self, from: data) {
            return payload.status == nil || payload.status == "ok"
        }
        return true
    }

    private func defaultSearchRoots() -> [URL] {
        [self.currentDirectoryURL, URL(fileURLWithPath: Bundle.main.bundlePath, isDirectory: true)]
    }

    private func reserveTCPPort(host: String, requestedPort: UInt16) -> UInt16? {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Self.defaultHost
            : host.trimmingCharacters(in: .whitespacesAndNewlines)
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var option: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &option, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = requestedPort.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr(normalizedHost))
        memset(&address.sin_zero, 0, MemoryLayout.size(ofValue: address.sin_zero))

        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { return nil }

        var boundAddress = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }
        guard nameResult == 0 else { return nil }
        return UInt16(bigEndian: boundAddress.sin_port)
    }

    private func bundledBundleRootCandidates(searchRoots: [URL]?) -> [URL] {
        var candidates: [URL] = []
        var seen: Set<String> = []

        func append(_ url: URL?) {
            guard let url else { return }
            let standardized = url.standardizedFileURL
            guard seen.insert(standardized.path).inserted else { return }
            candidates.append(standardized)
        }

        let roots = searchRoots ?? self.defaultSearchRoots()
        for root in roots {
            var current = root.standardizedFileURL
            while true {
                append(
                    current
                        .appendingPathComponent("Codexkit", isDirectory: true)
                        .appendingPathComponent("Sources", isDirectory: true)
                        .appendingPathComponent("CodexkitApp", isDirectory: true)
                        .appendingPathComponent("Bundled", isDirectory: true)
                        .appendingPathComponent("CLIProxyAPIServiceBundle", isDirectory: true)
                )
                append(
                    current
                        .appendingPathComponent("Sources", isDirectory: true)
                        .appendingPathComponent("CodexkitApp", isDirectory: true)
                        .appendingPathComponent("Bundled", isDirectory: true)
                        .appendingPathComponent("CLIProxyAPIServiceBundle", isDirectory: true)
                )

                let parent = current.deletingLastPathComponent()
                if parent.path == current.path { break }
                current = parent
            }
        }

        append(Bundle.module.resourceURL?.appendingPathComponent("CLIProxyAPIServiceBundle", isDirectory: true))

        return candidates
    }

    private func bundledRepoCandidates(searchRoots: [URL]?) -> [URL] {
        var candidates: [URL] = []
        var seen: Set<String> = []

        func append(_ url: URL?) {
            guard let url else { return }
            let standardized = url.standardizedFileURL
            guard seen.insert(standardized.path).inserted else { return }
            candidates.append(standardized)
        }

        let roots = searchRoots ?? self.defaultSearchRoots()
        for root in roots {
            var current = root.standardizedFileURL
            while true {
                append(
                    current
                        .appendingPathComponent("Codexkit", isDirectory: true)
                        .appendingPathComponent("Sources", isDirectory: true)
                        .appendingPathComponent("CodexkitApp", isDirectory: true)
                        .appendingPathComponent("Bundled", isDirectory: true)
                        .appendingPathComponent("CLIProxyAPIServiceBundle", isDirectory: true)
                        .appendingPathComponent("CLIProxyAPI", isDirectory: true)
                )
                append(
                    current
                        .appendingPathComponent("Sources", isDirectory: true)
                        .appendingPathComponent("CodexkitApp", isDirectory: true)
                        .appendingPathComponent("Bundled", isDirectory: true)
                        .appendingPathComponent("CLIProxyAPIServiceBundle", isDirectory: true)
                        .appendingPathComponent("CLIProxyAPI", isDirectory: true)
                )

                let parent = current.deletingLastPathComponent()
                if parent.path == current.path { break }
                current = parent
            }
        }

        append(Bundle.module.resourceURL?.appendingPathComponent(Self.bundledServiceRelativePath, isDirectory: true))

        return candidates
    }

    private func validateRepoRootCandidate(_ candidate: String) -> URL? {
        guard candidate.isEmpty == false else { return nil }
        let url = URL(fileURLWithPath: candidate, isDirectory: true)
        return self.isCLIProxyAPIRepoRoot(url) ? url : nil
    }

    private func isExecutableFile(_ url: URL) -> Bool {
        self.fileManager.isExecutableFile(atPath: url.path)
    }

    private func isCLIProxyAPIRepoRoot(_ url: URL) -> Bool {
        let mainGo = url
            .appendingPathComponent("cmd", isDirectory: true)
            .appendingPathComponent("server", isDirectory: true)
            .appendingPathComponent("main.go")
        return self.fileManager.fileExists(atPath: mainGo.path)
    }

    private static func unquoted(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return trimmed }
        if (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")) || (trimmed.hasPrefix("'") && trimmed.hasSuffix("'")) {
            return String(trimmed.dropFirst().dropLast())
        }
        return trimmed
    }

    private static func escapedYAMLString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func normalizedSecret(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmed.isEmpty == false else {
            return nil
        }
        return trimmed
    }

    private static func listItemValue(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("-") else { return nil }
        return Self.unquoted(
            String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func boolValue(_ value: String) -> Bool? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "yes", "1":
            return true
        case "false", "no", "0":
            return false
        default:
            return nil
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        self.isEmpty ? nil : self
    }
}
