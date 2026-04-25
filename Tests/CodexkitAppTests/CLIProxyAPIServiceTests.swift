import Foundation
import XCTest
@testable import CodexkitApp

final class CLIProxyAPIServiceTests: CodexBarTestCase {
    func testDefaultConfigUsesCodexkitRuntimePaths() {
        let service = CLIProxyAPIService()
        let config = service.defaultConfig(
            host: "127.0.0.1",
            port: 9317,
            managementSecretKey: "secret"
        )

        XCTAssertEqual(config.host, "127.0.0.1")
        XCTAssertEqual(config.port, 9317)
        XCTAssertEqual(config.managementSecretKey, "secret")
        XCTAssertFalse((config.clientAPIKey ?? "").isEmpty)
        XCTAssertNotEqual(config.clientAPIKey, config.managementSecretKey)
        XCTAssertTrue(config.authDirectory.path.contains(".codexkit/cliproxyapi/auth"))
        XCTAssertEqual(config.healthURL.absoluteString, "http://127.0.0.1:9317/healthz")
    }

    func testGenerateRandomAvailablePortReturnsBindablePort() {
        let service = CLIProxyAPIService()
        let port = service.generateRandomAvailablePort()

        XCTAssertTrue((1...65535).contains(port))
        XCTAssertTrue(service.canBindTCPPort(host: "127.0.0.1", port: port))
    }

    func testCanBindTCPPortReturnsFalseWhenPortIsAlreadyInUse() throws {
        let service = CLIProxyAPIService()
        let port = service.generateRandomAvailablePort()
        let server = LocalhostOAuthCallbackServer(port: UInt16(port), onCallback: { _ in })
        try server.start()
        defer { server.stop() }

        XCTAssertFalse(service.canBindTCPPort(host: "127.0.0.1", port: port))
    }

    func testRenderConfigIncludesPortAuthDirManagementSecretAndClientAPIKey() {
        let service = CLIProxyAPIService()
        let config = CLIProxyAPIServiceConfig(
            host: "127.0.0.1",
            port: 8411,
            authDirectory: URL(fileURLWithPath: "/tmp/codexkit-auth"),
            managementSecretKey: "topsecret",
            clientAPIKey: "client-secret",
            allowRemoteManagement: false,
            enabled: true,
            routingStrategy: .fillFirst,
            switchProjectOnQuotaExceeded: false,
            switchPreviewModelOnQuotaExceeded: true,
            requestRetry: 5,
            maxRetryInterval: 45,
            disableCooling: true
        )

        let yaml = service.renderConfigYAML(config)
        XCTAssertTrue(yaml.contains("host: \"127.0.0.1\""))
        XCTAssertTrue(yaml.contains("port: 8411"))
        XCTAssertTrue(yaml.contains("auth-dir: \"/tmp/codexkit-auth\""))
        XCTAssertTrue(yaml.contains("api-keys:\n  - \"client-secret\""))
        XCTAssertTrue(yaml.contains("allow-remote: false"))
        XCTAssertTrue(yaml.contains("secret-key: \"topsecret\""))
        XCTAssertTrue(yaml.contains("request-retry: 5"))
        XCTAssertTrue(yaml.contains("max-retry-interval: 45"))
        XCTAssertTrue(yaml.contains("disable-cooling: true"))
        XCTAssertTrue(yaml.contains("switch-project: false"))
        XCTAssertTrue(yaml.contains("switch-preview-model: true"))
        XCTAssertTrue(yaml.contains("strategy: \"fill-first\""))
    }

    func testParseConfigYAMLExtractsHostPortSecretKeyAndClientAPIKey() {
        let service = CLIProxyAPIService()

        let parsed = service.parseConfigYAML(
            """
            host: "0.0.0.0"
            port: 57346
            auth-dir: "/tmp/auth"
            api-keys:
              - "client-key"
            request-retry: 5
            max-retry-interval: 45
            disable-cooling: true
            quota-exceeded:
              switch-project: false
              switch-preview-model: true
            routing:
              strategy: "fill-first"
            remote-management:
              allow-remote: false
              secret-key: "agt_codex_secret"
            """
        )

        XCTAssertEqual(
            parsed,
            CLIProxyAPIService.LocalConfiguration(
                host: "0.0.0.0",
                port: 57346,
                managementSecretKey: "agt_codex_secret",
                clientAPIKey: "client-key",
                authDirectoryPath: "/tmp/auth",
                routingStrategy: .fillFirst,
                switchProjectOnQuotaExceeded: false,
                switchPreviewModelOnQuotaExceeded: true,
                requestRetry: 5,
                maxRetryInterval: 45,
                disableCooling: true
            )
        )
    }

    func testRenderAndParseConfigYAMLRoundTripsTopLevelAPIKeys() {
        let service = CLIProxyAPIService()
        let config = CLIProxyAPIServiceConfig(
            host: "127.0.0.1",
            port: 8412,
            authDirectory: URL(fileURLWithPath: "/tmp/codexkit-auth"),
            managementSecretKey: "topsecret",
            clientAPIKey: "client-secret",
            allowRemoteManagement: false,
            enabled: true,
            routingStrategy: .fillFirst,
            switchProjectOnQuotaExceeded: false,
            switchPreviewModelOnQuotaExceeded: true,
            requestRetry: 5,
            maxRetryInterval: 45,
            disableCooling: true
        )

        let parsed = service.parseConfigYAML(service.renderConfigYAML(config))

        XCTAssertEqual(parsed.host, config.host)
        XCTAssertEqual(parsed.port, config.port)
        XCTAssertEqual(parsed.authDirectoryPath, config.authDirectory.path)
        XCTAssertEqual(parsed.clientAPIKey, config.clientAPIKey)
        XCTAssertEqual(parsed.managementSecretKey, config.managementSecretKey)
        XCTAssertEqual(parsed.routingStrategy, config.routingStrategy)
        XCTAssertEqual(parsed.switchProjectOnQuotaExceeded, config.switchProjectOnQuotaExceeded)
        XCTAssertEqual(parsed.switchPreviewModelOnQuotaExceeded, config.switchPreviewModelOnQuotaExceeded)
        XCTAssertEqual(parsed.requestRetry, config.requestRetry)
        XCTAssertEqual(parsed.maxRetryInterval, config.maxRetryInterval)
        XCTAssertEqual(parsed.disableCooling, config.disableCooling)
    }

    func testResolveBundledRepoRootFindsBundledServiceTree() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let service = CLIProxyAPIService(currentDirectoryURL: root)
        let bundledRepo = root
            .appendingPathComponent("Codexkit", isDirectory: true)
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("CodexkitApp", isDirectory: true)
            .appendingPathComponent("Bundled", isDirectory: true)
            .appendingPathComponent("CLIProxyAPIServiceBundle", isDirectory: true)
            .appendingPathComponent("CLIProxyAPI", isDirectory: true)
        let mainGo = bundledRepo
            .appendingPathComponent("cmd", isDirectory: true)
            .appendingPathComponent("server", isDirectory: true)
            .appendingPathComponent("main.go")

        try FileManager.default.createDirectory(
            at: mainGo.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("package main".utf8).write(to: mainGo)

        let detected = service.resolveBundledRepoRoot(searchRoots: [root])

        XCTAssertNotNil(detected)
    }

    func testExplicitBundledSearchRootsDoNotFallBackToPackageResources() throws {
        if ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true" {
            throw XCTSkip("GitHub-hosted macOS 15 stalls when probing an intentionally empty explicit bundled search root fixture.")
        }

        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let service = CLIProxyAPIService(currentDirectoryURL: root)

        XCTAssertNil(service.resolveBundledRuntimeDescriptor(searchRoots: [root]))
        XCTAssertNil(service.bundledExecutableURL(searchRoots: [root]))
    }

    func testResolveBundledRuntimeDescriptorReadsManifestMetadata() throws {
        let service = CLIProxyAPIService()
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let bundleRoot = root
            .appendingPathComponent("Codexkit", isDirectory: true)
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("CodexkitApp", isDirectory: true)
            .appendingPathComponent("Bundled", isDirectory: true)
            .appendingPathComponent("CLIProxyAPIServiceBundle", isDirectory: true)
        let bundledRepo = bundleRoot.appendingPathComponent("CLIProxyAPI", isDirectory: true)
        let mainGo = bundledRepo
            .appendingPathComponent("cmd", isDirectory: true)
            .appendingPathComponent("server", isDirectory: true)
            .appendingPathComponent("main.go")

        try FileManager.default.createDirectory(
            at: mainGo.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("package main".utf8).write(to: mainGo)
        try Data(
            """
            {"source":"forks/CLIProxyAPI","delivery":"bundled-service-binary","version":"test-version","executable_relative_path":"bin/cli-proxy-api-darwin-arm64","rootURL":"/tmp/unused"}
            """.utf8
        ).write(to: bundleRoot.appendingPathComponent("bundle-manifest.json"))

        let descriptor = service.resolveBundledRuntimeDescriptor(searchRoots: [root])

        XCTAssertEqual(descriptor?.source, "forks/CLIProxyAPI")
        XCTAssertEqual(descriptor?.delivery, "bundled-service-binary")
        XCTAssertEqual(descriptor?.version, "test-version")
        XCTAssertEqual(descriptor?.executableRelativePath, "bin/cli-proxy-api-darwin-arm64")
        XCTAssertEqual(descriptor?.rootURL?.path, bundledRepo.path)
    }

    func testResolveBundledRuntimeDescriptorReadsManifestWithoutSourceTree() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let service = CLIProxyAPIService(currentDirectoryURL: root)
        let bundleRoot = root
            .appendingPathComponent("Codexkit", isDirectory: true)
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("CodexkitApp", isDirectory: true)
            .appendingPathComponent("Bundled", isDirectory: true)
            .appendingPathComponent("CLIProxyAPIServiceBundle", isDirectory: true)
        try FileManager.default.createDirectory(at: bundleRoot, withIntermediateDirectories: true)
        try Data(
            """
            {"source":"forks/CLIProxyAPI","delivery":"bundled-service-binary","version":"test-version","executable_relative_path":"bin/cli-proxy-api-darwin-arm64"}
            """.utf8
        ).write(to: bundleRoot.appendingPathComponent("bundle-manifest.json"))

        let descriptor = service.resolveBundledRuntimeDescriptor(searchRoots: [root])

        XCTAssertEqual(descriptor?.version, "test-version")
        XCTAssertNil(descriptor?.rootURL)
    }

    func testResolveConfiguredRepoRootFallsBackToBundledBundleRootWhenOnlyBinaryBundleExists() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let service = CLIProxyAPIService(currentDirectoryURL: root)
        let bundleRoot = root
            .appendingPathComponent("Codexkit", isDirectory: true)
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("CodexkitApp", isDirectory: true)
            .appendingPathComponent("Bundled", isDirectory: true)
            .appendingPathComponent("CLIProxyAPIServiceBundle", isDirectory: true)
        try FileManager.default.createDirectory(at: bundleRoot, withIntermediateDirectories: true)
        try Data(
            """
            {"source":"forks/CLIProxyAPI","delivery":"bundled-service-binary","version":"test-version","executable_relative_path":"bin/cli-proxy-api-darwin-arm64"}
            """.utf8
        ).write(to: bundleRoot.appendingPathComponent("bundle-manifest.json"))

        let detected = service.resolveConfiguredRepoRoot(explicitPath: nil, environment: [:])

        XCTAssertEqual(detected?.path, bundleRoot.path)
    }

    func testBundledExecutableURLFindsPackagedBinary() throws {
        let service = CLIProxyAPIService()
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let executable = root
            .appendingPathComponent("Codexkit", isDirectory: true)
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("CodexkitApp", isDirectory: true)
            .appendingPathComponent("Bundled", isDirectory: true)
            .appendingPathComponent("CLIProxyAPIServiceBundle", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("cli-proxy-api-darwin-arm64")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int16(0o755))], ofItemAtPath: executable.path)

        let detected = service.bundledExecutableURL(searchRoots: [root])

        XCTAssertEqual(detected?.path, executable.path)
    }

    func testEnsureRuntimeDirectoriesCreatesManagedRuntimeSubdirectories() throws {
        let service = CLIProxyAPIService()

        try service.ensureRuntimeDirectories()

        for directory in [
            CLIProxyAPIService.runtimeRootURL,
            CLIProxyAPIService.authDirectoryURL,
            CLIProxyAPIService.logsDirectoryURL,
            CLIProxyAPIService.staticDirectoryURL,
            CLIProxyAPIService.managedDownloadsDirectoryURL,
            CLIProxyAPIService.managedInstallStagingDirectoryURL,
            CLIProxyAPIService.managedVersionsDirectoryURL,
            CLIProxyAPIService.managedBinDirectoryURL,
        ] {
            var isDirectory: ObjCBool = false
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory))
            XCTAssertTrue(isDirectory.boolValue, "\(directory.path) should be a directory")
            XCTAssertTrue(directory.path.hasPrefix(CLIProxyAPIService.runtimeRootURL.path))
        }
    }

    func testResolveManagedRuntimeDescriptorReadsActiveVersionMetadata() throws {
        let service = CLIProxyAPIService()
        let executable = CLIProxyAPIService.managedVersionsDirectoryURL
            .appendingPathComponent("v9.0.0", isDirectory: true)
            .appendingPathComponent("cli-proxy-api")
        try self.writeExecutable(at: executable)
        try service.writeManagedRuntimeDescriptor(
            CLIProxyAPIService.ManagedRuntimeDescriptor(
                version: "v9.0.0",
                executableRelativePath: "versions/v9.0.0/cli-proxy-api",
                artifactName: "CLIProxyAPI_9.0.0_darwin_arm64.tar.gz",
                downloadURL: URL(string: "https://example.com/cpa.tar.gz")!,
                installedAt: nil,
                previousVersion: "v8.9.9",
                previousExecutableRelativePath: "versions/v8.9.9/cli-proxy-api"
            )
        )

        let descriptor = service.resolveManagedRuntimeDescriptor()

        XCTAssertEqual(descriptor?.version, "v9.0.0")
        XCTAssertEqual(service.managedExecutableURL()?.path, executable.path)
    }

    func testMakeLaunchProcessPrefersManagedRuntimeExecutableAndManagedCwd() throws {
        let service = CLIProxyAPIService(environment: ["PATH": "/usr/bin"])
        let executable = CLIProxyAPIService.managedVersionsDirectoryURL
            .appendingPathComponent("v9.0.1", isDirectory: true)
            .appendingPathComponent("cli-proxy-api")
        try self.writeExecutable(at: executable)
        try service.writeManagedRuntimeDescriptor(
            CLIProxyAPIService.ManagedRuntimeDescriptor(
                version: "v9.0.1",
                executableRelativePath: "versions/v9.0.1/cli-proxy-api",
                artifactName: nil,
                downloadURL: nil,
                installedAt: nil,
                previousVersion: nil,
                previousExecutableRelativePath: nil
            )
        )
        let configURL = CLIProxyAPIService.configURL

        let process = service.makeLaunchProcess(
            repoRoot: URL(fileURLWithPath: "/tmp/ignored-bundled-root", isDirectory: true),
            configURL: configURL
        )

        XCTAssertEqual(process.executableURL?.path, executable.path)
        XCTAssertEqual(process.arguments, ["-config", configURL.path])
        XCTAssertEqual(process.currentDirectoryURL?.path, CLIProxyAPIService.runtimeRootURL.path)
        XCTAssertEqual(process.environment?["WRITABLE_PATH"], CLIProxyAPIService.runtimeRootURL.path)
        XCTAssertEqual(process.environment?["CLI_PROXY_API_RUNTIME_ROOT"], CLIProxyAPIService.runtimeRootURL.path)
    }

    func testMakeLaunchProcessUsesManagedCwdForBundledExecutableFallback() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let bundleRoot = root
            .appendingPathComponent("Codexkit", isDirectory: true)
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("CodexkitApp", isDirectory: true)
            .appendingPathComponent("Bundled", isDirectory: true)
            .appendingPathComponent("CLIProxyAPIServiceBundle", isDirectory: true)
        let executable = bundleRoot
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("cli-proxy-api-darwin-arm64")
        let repoRoot = bundleRoot.appendingPathComponent("CLIProxyAPI", isDirectory: true)
        let mainGo = repoRoot
            .appendingPathComponent("cmd", isDirectory: true)
            .appendingPathComponent("server", isDirectory: true)
            .appendingPathComponent("main.go")
        try self.writeExecutable(at: executable)
        try FileManager.default.createDirectory(at: mainGo.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("package main".utf8).write(to: mainGo)
        let service = CLIProxyAPIService(environment: ["PATH": "/usr/bin"], currentDirectoryURL: root)
        let configURL = CLIProxyAPIService.configURL

        let process = service.makeLaunchProcess(repoRoot: nil, configURL: configURL)

        XCTAssertEqual(process.executableURL?.path, executable.path)
        XCTAssertEqual(process.arguments, ["-config", configURL.path])
        XCTAssertEqual(process.currentDirectoryURL?.path, CLIProxyAPIService.runtimeRootURL.path)
        XCTAssertEqual(process.environment?["WRITABLE_PATH"], CLIProxyAPIService.runtimeRootURL.path)
    }

    func testMakeLaunchProcessPrefersBundledExecutableWhenPresent() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let executable = root
            .appendingPathComponent("Codexkit", isDirectory: true)
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("CodexkitApp", isDirectory: true)
            .appendingPathComponent("Bundled", isDirectory: true)
            .appendingPathComponent("CLIProxyAPIServiceBundle", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("cli-proxy-api-darwin-arm64")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int16(0o755))], ofItemAtPath: executable.path)

        let service = CLIProxyAPIService(currentDirectoryURL: root)
        let configURL = URL(fileURLWithPath: "/tmp/config.yaml")

        let process = service.makeLaunchProcess(repoRoot: nil, configURL: configURL)

        XCTAssertEqual(process.executableURL?.path, executable.path)
        XCTAssertEqual(process.arguments, ["-config", "/tmp/config.yaml"])
        XCTAssertEqual(process.currentDirectoryURL?.path, CLIProxyAPIService.runtimeRootURL.path)
    }

    func testMakeLaunchProcessTargetsCLIProxyAPIRepoAndConfig() throws {
        if ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true" {
            throw XCTSkip("GitHub-hosted macOS 15 stalls when materializing the /usr/bin/env go-run Process fixture.")
        }

        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let service = CLIProxyAPIService(currentDirectoryURL: root)
        let repoRoot = self.makeRepoRoot(named: "CLIProxyAPI")
        let configURL = URL(fileURLWithPath: "/tmp/config.yaml")

        let process = service.makeLaunchProcess(repoRoot: repoRoot, configURL: configURL)

        XCTAssertEqual(process.executableURL?.path, "/usr/bin/env")
        XCTAssertEqual(process.arguments, ["go", "run", "./cmd/server/main.go", "-config", "/tmp/config.yaml"])
        XCTAssertEqual(process.currentDirectoryURL?.path, repoRoot.path)
    }

    func testResolveConfiguredRepoRootReadsExplicitPathFirst() {
        let service = CLIProxyAPIService()
        let explicitRoot = self.makeRepoRoot(named: "explicit-root")
        let envRoot = self.makeRepoRoot(named: "env-root")

        let repoRoot = service.resolveConfiguredRepoRoot(
            explicitPath: explicitRoot.path,
            environment: ["CLIProxyAPI_REPO_ROOT": envRoot.path]
        )

        XCTAssertEqual(repoRoot?.path, explicitRoot.path)
    }

    func testResolveConfiguredRepoRootFallsBackToEnvironmentVariable() {
        let service = CLIProxyAPIService()
        let envRoot = self.makeRepoRoot(named: "env-root")

        let repoRoot = service.resolveConfiguredRepoRoot(
            environment: ["CLIProxyAPI_REPO_ROOT": envRoot.path]
        )

        XCTAssertEqual(repoRoot?.path, envRoot.path)
    }

    func testResolveConfiguredRepoRootFallsBackToBundledRepoWithoutConfiguration() {
        let service = CLIProxyAPIService()

        XCTAssertEqual(
            service.resolveConfiguredRepoRoot(environment: [:])?.lastPathComponent,
            "CLIProxyAPI"
        )
    }

    func testPromoteStagedRuntimeCopiesAuthFilesAndWritesLiveConfig() throws {
        let service = CLIProxyAPIService()
        let stagedConfig = CLIProxyAPIServiceConfig(
            host: "127.0.0.1",
            port: 9411,
            authDirectory: CLIProxyAPIService.stagedAuthDirectoryURL,
            managementSecretKey: "stage-secret",
            clientAPIKey: "stage-client-secret",
            allowRemoteManagement: false,
            enabled: true,
            routingStrategy: .fillFirst,
            switchProjectOnQuotaExceeded: false,
            switchPreviewModelOnQuotaExceeded: true,
            requestRetry: 5,
            maxRetryInterval: 45,
            disableCooling: true
        )
        let liveConfig = CLIProxyAPIServiceConfig(
            host: "127.0.0.1",
            port: 9411,
            authDirectory: CLIProxyAPIService.authDirectoryURL,
            managementSecretKey: "live-secret",
            clientAPIKey: "live-client-secret",
            allowRemoteManagement: false,
            enabled: true,
            routingStrategy: .fillFirst,
            switchProjectOnQuotaExceeded: false,
            switchPreviewModelOnQuotaExceeded: true,
            requestRetry: 5,
            maxRetryInterval: 45,
            disableCooling: true
        )

        _ = try service.writeConfig(stagedConfig, staged: true)
        try service.ensureRuntimeDirectories(staged: true)
        try CodexPaths.writeSecureFile(
            Data(#"{"email":"alpha@example.com"}"#.utf8),
            to: CLIProxyAPIService.stagedAuthDirectoryURL.appendingPathComponent("codex-alpha.json")
        )

        try service.promoteStagedRuntime(liveConfig: liveConfig)

        let liveConfigText = try String(contentsOf: CLIProxyAPIService.configURL, encoding: .utf8)
        XCTAssertTrue(liveConfigText.contains("secret-key: \"live-secret\""))
        XCTAssertTrue(liveConfigText.contains("api-keys:\n  - \"live-client-secret\""))
        XCTAssertTrue(liveConfigText.contains("strategy: \"fill-first\""))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: CLIProxyAPIService.authDirectoryURL.appendingPathComponent("codex-alpha.json").path
            )
        )
    }

    func testCLIProxyAPISettingsGenerateDistinctClientAPIKeyWhenMissing() throws {
        let decoded = try JSONDecoder().decode(
            CodexBarDesktopSettings.CLIProxyAPISettings.self,
            from: Data(
                """
                {
                  "enabled": true,
                  "host": "127.0.0.1",
                  "port": 8317,
                  "managementSecretKey": "secret",
                  "memberAccountIDs": ["acct-a"]
                }
                """.utf8
            )
        )

        XCTAssertEqual(decoded.managementSecretKey, "secret")
        XCTAssertFalse((decoded.clientAPIKey ?? "").isEmpty)
        XCTAssertNotEqual(decoded.clientAPIKey, decoded.managementSecretKey)
    }

    func testCLIProxyAPISettingsIgnoreLegacyRepositoryRoot() throws {
        let initialized = CodexBarDesktopSettings.CLIProxyAPISettings(
            enabled: true,
            host: "127.0.0.1",
            port: 8317,
            repositoryRootPath: "/tmp/legacy-cli-proxy",
            managementSecretKey: "secret",
            memberAccountIDs: ["acct-a"]
        )
        XCTAssertNil(initialized.repositoryRootPath)

        let decoded = try JSONDecoder().decode(
            CodexBarDesktopSettings.CLIProxyAPISettings.self,
            from: Data(
                """
                {
                  "enabled": true,
                  "host": "127.0.0.1",
                  "port": 8317,
                  "repositoryRootPath": "/tmp/legacy-cli-proxy",
                  "managementSecretKey": "secret",
                  "memberAccountIDs": ["acct-a"]
                }
                """.utf8
            )
        )

        XCTAssertNil(decoded.repositoryRootPath)
        XCTAssertEqual(decoded.managementSecretKey, "secret")
        XCTAssertEqual(decoded.memberAccountIDs, ["acct-a"])
    }

    private func makeRepoRoot(named name: String) -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        let mainGo = root
            .appendingPathComponent("cmd", isDirectory: true)
            .appendingPathComponent("server", isDirectory: true)
            .appendingPathComponent("main.go")
        try? FileManager.default.createDirectory(
            at: mainGo.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? Data("package main".utf8).write(to: mainGo)
        return root
    }

    private func writeExecutable(at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: url.path
        )
    }
}
