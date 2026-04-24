import Foundation
import XCTest
@testable import CodexkitApp

final class CLIProxyAPIProbeServiceTests: CodexBarTestCase {
    func testDetectExternalRepositoryRootFallsBackToBundledPathWhenOnlyBundledPathExists() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let bundledRepo = root
            .appendingPathComponent("Codexkit", isDirectory: true)
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("CodexkitApp", isDirectory: true)
            .appendingPathComponent("Bundled", isDirectory: true)
            .appendingPathComponent("CLIProxyAPIServiceBundle", isDirectory: true)
            .appendingPathComponent("CLIProxyAPI", isDirectory: true)
        let bundledMain = bundledRepo
            .appendingPathComponent("cmd", isDirectory: true)
            .appendingPathComponent("server", isDirectory: true)
            .appendingPathComponent("main.go")
        try FileManager.default.createDirectory(
            at: bundledMain.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("package main".utf8).write(to: bundledMain)

        let service = CLIProxyAPIService(
            environment: ["CLIProxyAPI_REPO_ROOT": bundledRepo.path],
            currentDirectoryURL: root.appendingPathComponent("Codexkit", isDirectory: true)
        )
        let probeService = CLIProxyAPIProbeService(service: service)

        XCTAssertEqual(probeService.detectExternalRepositoryRoot()?.path, bundledRepo.path)
    }

    func testSyncSnapshotFallsBackToLocalAuthFilesWhenManagementRequestsFail() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let service = CLIProxyAPIService(session: session)
        let managementService = CLIProxyAPIManagementService(session: session)
        let probeService = CLIProxyAPIProbeService(
            service: service,
            managementService: managementService
        )
        let runtimeConfig = service.defaultConfig(
            host: "127.0.0.1",
            port: 9317,
            managementSecretKey: "secret"
        )

        try service.ensureRuntimeDirectories()
        _ = try service.writeConfig(runtimeConfig)

        let localAuthURL = CLIProxyAPIService.authDirectoryURL.appendingPathComponent("codex-alpha.json")
        let localAuthData = Data(
            """
            {
              "type": "codex",
              "email": "alpha@example.com",
              "plan_type": "team",
              "account_id": "acct-openai-alpha",
              "priority": 9,
              "codexkit_local_account_id": "local-alpha"
            }
            """.utf8
        )
        try localAuthData.write(to: localAuthURL)

        MockURLProtocol.handler = { _ in
            throw URLError(.cannotConnectToHost)
        }

        let snapshot = try await probeService.syncSnapshot(
            host: "127.0.0.1",
            port: 9317,
            managementSecretKey: "secret",
            explicitRepoRootPath: nil,
            localAccounts: []
        )

        XCTAssertEqual(snapshot.authFileCount, 1)
        XCTAssertEqual(snapshot.modelCount, 0)
        XCTAssertNil(snapshot.totalRequests)
        XCTAssertNil(snapshot.failedRequests)
        XCTAssertNil(snapshot.totalTokens)
        XCTAssertNil(snapshot.quotaSnapshot)
        XCTAssertEqual(snapshot.accountUsageItems.count, 1)
        XCTAssertEqual(snapshot.accountUsageItems[0].email, "alpha@example.com")
        XCTAssertEqual(snapshot.accountUsageItems[0].planType, "team")
        XCTAssertEqual(snapshot.observedAuthFiles.count, 1)
        XCTAssertEqual(snapshot.observedAuthFiles[0].fileName, "codex-alpha.json")
        XCTAssertEqual(snapshot.observedAuthFiles[0].priority, 9)
        XCTAssertEqual(snapshot.observedAuthFiles[0].localAccountID, "local-alpha")
    }

    func testSyncSnapshotCollectsModelIDsFromManagement() async throws {
        let session = self.makeMockSession()
        let service = CLIProxyAPIService(session: session)
        let managementService = CLIProxyAPIManagementService(session: session, sleep: { _ in })
        let probeService = CLIProxyAPIProbeService(
            service: service,
            managementService: managementService
        )
        let runtimeConfig = service.defaultConfig(
            host: "127.0.0.1",
            port: 9317,
            managementSecretKey: "secret"
        )
        _ = try service.writeConfig(runtimeConfig)

        MockURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            switch path {
            case "/v0/management/config.yaml":
                let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
                return (response, Data())
            case "/v0/management/auth-files":
                let body = Data(#"{"files":[{"name":"codex-alpha.json","type":"codex","email":"alpha@example.com","auth_index":"acct-alpha"}]}"#.utf8)
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, body)
            case "/v0/management/auth-files/models":
                let body = Data(#"{"models":[{"id":"gpt-5.4"},{"id":"gpt-5.4-mini"}]}"#.utf8)
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, body)
            case "/v0/management/usage":
                let body = Data(#"{"usage":{"total_requests":2,"failure_count":0,"total_tokens":42,"apis":{}},"failed_requests":0}"#.utf8)
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, body)
            case "/v0/management/quota":
                let body = Data(#"{"snapshot_generated_at":"2026-04-21T04:20:00Z","refresh_status":"ok","stale":false,"refresh_interval_seconds":60,"stale_threshold_seconds":120,"accounts":[]}"#.utf8)
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, body)
            default:
                throw URLError(.badURL)
            }
        }

        let snapshot = try await probeService.syncSnapshot(
            host: "127.0.0.1",
            port: 9317,
            managementSecretKey: "secret",
            explicitRepoRootPath: nil,
            localAccounts: []
        )

        XCTAssertEqual(snapshot.modelCount, 2)
        XCTAssertEqual(snapshot.modelIDs, ["gpt-5.4", "gpt-5.4-mini"])
    }

    func testLocalTokenAccountsParsesCodexAuthJSON() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repoRoot = root.appendingPathComponent("external-cli-proxy", isDirectory: true)
        let authDirectory = repoRoot.appendingPathComponent("auths", isDirectory: true)
        try FileManager.default.createDirectory(at: authDirectory, withIntermediateDirectories: true)
        try Data(
            """
            host: "127.0.0.1"
            port: 57346
            auth-dir: "\(authDirectory.path)"
            request-retry: 5
            max-retry-interval: 45
            disable-cooling: true
            quota-exceeded:
              switch-project: false
              switch-preview-model: true
            routing:
              strategy: "fill-first"
            remote-management:
              secret-key: "secret"
            """.utf8
        ).write(to: repoRoot.appendingPathComponent("config.yaml"))
        try Data(
            """
            {
              "type": "codex",
              "email": "alpha@example.com",
              "account_id": "acct-alpha",
              "access_token": "access",
              "refresh_token": "refresh",
              "id_token": "id",
              "plan_type": "plus"
            }
            """.utf8
        ).write(to: authDirectory.appendingPathComponent("codex-alpha.json"))

        let probeService = CLIProxyAPIProbeService(service: CLIProxyAPIService())
        let accounts = probeService.localTokenAccounts(repoRootPath: repoRoot.path)

        XCTAssertEqual(accounts.count, 1)
        XCTAssertEqual(accounts[0].email, "alpha@example.com")
        XCTAssertEqual(accounts[0].accountId, "codex-alpha")
        XCTAssertEqual(accounts[0].remoteAccountId, "acct-alpha")
        XCTAssertEqual(accounts[0].planType, "plus")

    }

    func testLocalTokenAccountsDeduplicatesSameRemoteAccountAndPlanFromRepeatedAuthFiles() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repoRoot = root.appendingPathComponent("external-cli-proxy", isDirectory: true)
        let authDirectory = repoRoot.appendingPathComponent("auths", isDirectory: true)
        try FileManager.default.createDirectory(at: authDirectory, withIntermediateDirectories: true)
        try Data(
            """
            host: "127.0.0.1"
            port: 57346
            auth-dir: "\(authDirectory.path)"
            remote-management:
              secret-key: "secret"
            """.utf8
        ).write(to: repoRoot.appendingPathComponent("config.yaml"))
        let duplicatePayload = """
        {
          "type": "codex",
          "email": "alpha@example.com",
          "account_id": "acct-alpha",
          "access_token": "access",
          "refresh_token": "refresh",
          "id_token": "id",
          "plan_type": "team"
        }
        """
        try Data(duplicatePayload.utf8).write(to: authDirectory.appendingPathComponent("codex-alpha-1.json"))
        try Data(duplicatePayload.utf8).write(to: authDirectory.appendingPathComponent("codex-alpha-2.json"))

        let probeService = CLIProxyAPIProbeService(service: CLIProxyAPIService())
        let accounts = probeService.localTokenAccounts(repoRootPath: repoRoot.path)

        XCTAssertEqual(accounts.count, 1)
        XCTAssertEqual(accounts[0].email, "alpha@example.com")
        XCTAssertEqual(accounts[0].remoteAccountId, "acct-alpha")
        XCTAssertEqual(accounts[0].planType, "team")
    }

    func testSuggestedDraftValuesReadBundledRuntimeConfig() throws {
        let service = CLIProxyAPIService()
        let runtimeConfig = CLIProxyAPIServiceConfig(
            host: "127.0.0.1",
            port: 57346,
            authDirectory: CLIProxyAPIService.authDirectoryURL,
            managementSecretKey: "secret",
            allowRemoteManagement: false,
            enabled: true,
            routingStrategy: .fillFirst,
            switchProjectOnQuotaExceeded: false,
            switchPreviewModelOnQuotaExceeded: true,
            requestRetry: 5,
            maxRetryInterval: 45,
            disableCooling: true
        )
        _ = try service.writeConfig(runtimeConfig)

        let probeService = CLIProxyAPIProbeService(service: service)
        let suggested = probeService.suggestedDraftValues(existingSettings: .init())

        XCTAssertEqual(suggested.host, "127.0.0.1")
        XCTAssertEqual(suggested.port, 57346)
        XCTAssertEqual(suggested.managementSecretKey, "secret")
        XCTAssertEqual(suggested.routingStrategy, .fillFirst)
        XCTAssertFalse(suggested.switchProjectOnQuotaExceeded)
        XCTAssertTrue(suggested.switchPreviewModelOnQuotaExceeded)
        XCTAssertEqual(suggested.requestRetry, 5)
        XCTAssertEqual(suggested.maxRetryInterval, 45)
        XCTAssertTrue(suggested.disableCooling)
    }
}
