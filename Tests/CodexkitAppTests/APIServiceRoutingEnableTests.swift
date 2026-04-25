import Foundation
import XCTest
@testable import CodexkitApp

@MainActor
final class APIServiceRoutingEnableTests: CodexBarTestCase {
    func testEnableRoutingRunsProbeAndReturnsSuccessMessage() async throws {
        let originalLanguageOverride = L.languageOverride
        L.languageOverride = false
        defer { L.languageOverride = originalLanguageOverride }

        let oauthAccount = try self.makeOAuthAccount(
            accountID: "acct-probe-success",
            email: "probe-success@example.com"
        )
        let storedOAuthAccount = CodexBarProviderAccount.fromTokenAccount(
            oauthAccount,
            existingID: oauthAccount.accountId
        )
        try self.writeConfig(
            CodexBarConfig(
                active: CodexBarActiveSelection(
                    providerId: "openai-oauth",
                    accountId: storedOAuthAccount.id
                ),
                desktop: CodexBarDesktopSettings(
                    cliProxyAPI: .init(
                        enabled: false,
                        host: "127.0.0.1",
                        port: 8317,
                        repositoryRootPath: "/tmp/CLIProxyAPI",
                        managementSecretKey: "secret",
                        memberAccountIDs: [storedOAuthAccount.id]
                    )
                ),
                providers: [
                    CodexBarProvider(
                        id: "openai-oauth",
                        kind: .openAIOAuth,
                        label: "OpenAI",
                        activeAccountId: storedOAuthAccount.id,
                        accounts: [storedOAuthAccount]
                    ),
                ]
            )
        )

        let syncService = RoutingProbeSyncService()
        var probeCallCount = 0
        let store = TokenStore(
            configStore: CodexBarConfigStore(),
            syncService: syncService,
            openRouterGatewayService: OpenRouterGatewayControllerSpy(),
            apiServiceRuntimeController: { RuntimeControllerSpy() },
            apiServiceRoutingProbeAction: { _ in
                probeCallCount += 1
            },
            codexRunningProcessIDs: { [] }
        )

        let message = try await store.enableAPIServiceRoutingFromMenu()

        XCTAssertEqual(message, L.menuAPIServiceRoutingProbeSuccess)
        XCTAssertTrue(store.config.desktop.cliProxyAPI.enabled)
        XCTAssertEqual(probeCallCount, 1)
        XCTAssertEqual(syncService.restoreCallCount, 0)
    }

    func testEnableRoutingReusesAdoptableRunningServiceBeforeProbe() async throws {
        let oauthAccount = try self.makeOAuthAccount(
            accountID: "acct-probe-reuse",
            email: "probe-reuse@example.com"
        )
        let storedOAuthAccount = CodexBarProviderAccount.fromTokenAccount(
            oauthAccount,
            existingID: oauthAccount.accountId
        )
        try self.writeConfig(self.makeRoutingConfig(storedOAuthAccount))

        let syncService = RoutingProbeSyncService()
        let runtimeController = RuntimeControllerSpy()
        runtimeController.nextApplyResult = false
        runtimeController.nextAdoptResult = true
        var probeCallCount = 0
        let store = TokenStore(
            configStore: CodexBarConfigStore(),
            syncService: syncService,
            openRouterGatewayService: OpenRouterGatewayControllerSpy(),
            apiServiceRuntimeController: { runtimeController },
            apiServiceRoutingProbeAction: { _ in
                probeCallCount += 1
            },
            codexRunningProcessIDs: { [] }
        )

        let message = try await store.enableAPIServiceRoutingFromMenu()

        XCTAssertEqual(message, L.menuAPIServiceRoutingProbeSuccess)
        XCTAssertTrue(store.config.desktop.cliProxyAPI.enabled)
        XCTAssertEqual(runtimeController.appliedSettings.count, 1)
        XCTAssertEqual(runtimeController.adoptRequests.count, 1)
        XCTAssertEqual(probeCallCount, 1)
        XCTAssertEqual(syncService.restoreCallCount, 0)
    }

    func testEnableRoutingProbeFailureRollsBackAndDisablesRouting() async throws {
        let originalLanguageOverride = L.languageOverride
        L.languageOverride = false
        defer { L.languageOverride = originalLanguageOverride }

        let oauthAccount = try self.makeOAuthAccount(
            accountID: "acct-probe-failure",
            email: "probe-failure@example.com"
        )
        let storedOAuthAccount = CodexBarProviderAccount.fromTokenAccount(
            oauthAccount,
            existingID: oauthAccount.accountId
        )
        try self.writeConfig(
            CodexBarConfig(
                active: CodexBarActiveSelection(
                    providerId: "openai-oauth",
                    accountId: storedOAuthAccount.id
                ),
                desktop: CodexBarDesktopSettings(
                    cliProxyAPI: .init(
                        enabled: false,
                        host: "127.0.0.1",
                        port: 8317,
                        repositoryRootPath: "/tmp/CLIProxyAPI",
                        managementSecretKey: "secret",
                        memberAccountIDs: [storedOAuthAccount.id]
                    )
                ),
                providers: [
                    CodexBarProvider(
                        id: "openai-oauth",
                        kind: .openAIOAuth,
                        label: "OpenAI",
                        activeAccountId: storedOAuthAccount.id,
                        accounts: [storedOAuthAccount]
                    ),
                ]
            )
        )

        let syncService = RoutingProbeSyncService()
        var probeCallCount = 0
        let store = TokenStore(
            configStore: CodexBarConfigStore(),
            syncService: syncService,
            openRouterGatewayService: OpenRouterGatewayControllerSpy(),
            apiServiceRuntimeController: { RuntimeControllerSpy() },
            apiServiceRoutingProbeAction: { _ in
                probeCallCount += 1
                throw URLError(.timedOut)
            },
            codexRunningProcessIDs: { [] }
        )

        do {
            _ = try await store.enableAPIServiceRoutingFromMenu()
            XCTFail("Expected probe failure")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Routing probe failed"))
        }

        XCTAssertFalse(store.config.desktop.cliProxyAPI.enabled)
        XCTAssertEqual(probeCallCount, 1)
        XCTAssertEqual(syncService.restoreCallCount, 1)
    }

    func testEnableRoutingRuntimeApplyFailureStaysDirectErrorInsteadOfUnknownProbeFailure() async throws {
        let oauthAccount = try self.makeOAuthAccount(
            accountID: "acct-probe-runtime-failure",
            email: "probe-runtime-failure@example.com"
        )
        let storedOAuthAccount = CodexBarProviderAccount.fromTokenAccount(
            oauthAccount,
            existingID: oauthAccount.accountId
        )
        try self.writeConfig(self.makeRoutingConfig(storedOAuthAccount))

        let syncService = RoutingProbeSyncService()
        let runtimeController = RuntimeControllerSpy()
        runtimeController.nextApplyResult = false
        runtimeController.nextAdoptResult = false
        let store = TokenStore(
            configStore: CodexBarConfigStore(),
            syncService: syncService,
            openRouterGatewayService: OpenRouterGatewayControllerSpy(),
            apiServiceRuntimeController: { runtimeController },
            apiServiceRoutingProbeAction: { _ in
                XCTFail("Probe should not run when runtime apply fails")
            },
            codexRunningProcessIDs: { [] }
        )
        store.updateCLIProxyAPIState(
            CLIProxyAPIServiceState(
                config: CLIProxyAPIServiceConfig(
                    host: "127.0.0.1",
                    port: 8317,
                    authDirectory: CLIProxyAPIService.authDirectoryURL,
                    managementSecretKey: "secret",
                    enabled: false
                ),
                status: .failed,
                lastError: "Management authentication required"
            )
        )

        do {
            _ = try await store.enableAPIServiceRoutingFromMenu()
            XCTFail("Expected runtime apply failure")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Management authentication required")
            XCTAssertFalse(error.localizedDescription.contains("unknown_probe_failure"))
            XCTAssertFalse(error.localizedDescription.contains("Routing probe failed"))
        }

        XCTAssertEqual(runtimeController.adoptRequests.count, 1)
        XCTAssertEqual(syncService.restoreCallCount, 1)
        XCTAssertFalse(store.config.desktop.cliProxyAPI.enabled)
    }

    func testEnableRoutingWritesCodexkitManagedConfigBeforeProbeAndRefreshesPreAPISnapshotOnlyAfterSuccess() async throws {
        let oauthAccount = try self.makeOAuthAccount(
            accountID: "acct-probe-order",
            email: "probe-order@example.com"
        )
        let storedOAuthAccount = CodexBarProviderAccount.fromTokenAccount(
            oauthAccount,
            existingID: oauthAccount.accountId
        )
        try self.writeConfig(self.makeRoutingConfig(storedOAuthAccount))
        let seededDirectAuth = Data(#"{"auth_mode":"chatgpt","tokens":{"account_id":"acct-probe-order"}}"#.utf8)
        let seededDirectToml = Data("custom_keep = \"yes\"\n".utf8)
        try CodexPaths.writeSecureFile(seededDirectAuth, to: CodexPaths.authURL)
        try CodexPaths.writeSecureFile(seededDirectToml, to: CodexPaths.configTomlURL)
        try CodexPaths.writeSecureFile(Data("old-pre-api-auth".utf8), to: CodexPaths.authPreAPIBackupURL)
        try CodexPaths.writeSecureFile(Data("old-pre-api-config".utf8), to: CodexPaths.configPreAPIBackupURL)

        var store: TokenStore!
        var enabledBeforeCommit = true
        var authKeySeenDuringProbe: String?
        var tomlSeenDuringProbe = ""
        var preAPIAuthSeenDuringProbe: Data?
        var preAPIConfigSeenDuringProbe: Data?
        let expectation = XCTestExpectation(description: "probe called")

        store = TokenStore(
            configStore: CodexBarConfigStore(),
            syncService: CodexSyncService(),
            openRouterGatewayService: OpenRouterGatewayControllerSpy(),
            apiServiceRuntimeController: { RuntimeControllerSpy() },
            apiServiceRoutingProbeAction: { config in
                enabledBeforeCommit = store.config.desktop.cliProxyAPI.enabled
                let authObject = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: CodexPaths.authURL)) as? [String: Any])
                authKeySeenDuringProbe = authObject["OPENAI_API_KEY"] as? String
                tomlSeenDuringProbe = try String(contentsOf: CodexPaths.configTomlURL, encoding: .utf8)
                preAPIAuthSeenDuringProbe = try Data(contentsOf: CodexPaths.authPreAPIBackupURL)
                preAPIConfigSeenDuringProbe = try Data(contentsOf: CodexPaths.configPreAPIBackupURL)
                XCTAssertNil(authObject["tokens"])
                XCTAssertEqual(authObject["auth_mode"] as? String, "apikey")
                XCTAssertEqual(authObject["OPENAI_API_KEY"] as? String, config.clientAPIKey)
                expectation.fulfill()
            },
            codexRunningProcessIDs: { [] }
        )
        let directSnapshotBeforeEnableAuth = try Data(contentsOf: CodexPaths.authURL)
        let directSnapshotBeforeEnableToml = try Data(contentsOf: CodexPaths.configTomlURL)

        let message = try await store.enableAPIServiceRoutingFromMenu()
        await fulfillment(of: [expectation], timeout: 1)

        XCTAssertEqual(message, L.menuAPIServiceRoutingProbeSuccess)
        XCTAssertFalse(enabledBeforeCommit)
        XCTAssertEqual(authKeySeenDuringProbe, store.config.desktop.cliProxyAPI.clientAPIKey)
        XCTAssertEqual(preAPIAuthSeenDuringProbe, Data("old-pre-api-auth".utf8))
        XCTAssertEqual(preAPIConfigSeenDuringProbe, Data("old-pre-api-config".utf8))
        XCTAssertTrue(tomlSeenDuringProbe.contains(#"model_provider = "custom""#))
        XCTAssertTrue(tomlSeenDuringProbe.contains("[model_providers.custom]"))
        XCTAssertTrue(tomlSeenDuringProbe.contains(#"name = "codexkit""#))
        XCTAssertTrue(tomlSeenDuringProbe.contains(#"wire_api = "responses""#))
        XCTAssertTrue(tomlSeenDuringProbe.contains(#"base_url = "http://127.0.0.1:8317/v1""#))
        XCTAssertTrue(tomlSeenDuringProbe.contains("requires_openai_auth = true"))
        XCTAssertFalse(tomlSeenDuringProbe.contains("openai_base_url"))
        XCTAssertEqual(try Data(contentsOf: CodexPaths.authPreAPIBackupURL), directSnapshotBeforeEnableAuth)
        XCTAssertEqual(try Data(contentsOf: CodexPaths.configPreAPIBackupURL), directSnapshotBeforeEnableToml)
        XCTAssertTrue(store.config.desktop.cliProxyAPI.enabled)
    }

    func testEnableRoutingProbeFailureRollsBackWithoutRefreshingPreAPISnapshot() async throws {
        let oauthAccount = try self.makeOAuthAccount(
            accountID: "acct-probe-rollback",
            email: "probe-rollback@example.com"
        )
        let storedOAuthAccount = CodexBarProviderAccount.fromTokenAccount(
            oauthAccount,
            existingID: oauthAccount.accountId
        )
        try self.writeConfig(self.makeRoutingConfig(storedOAuthAccount))
        let originalAuth = Data(#"{"auth_mode":"chatgpt","tokens":{"account_id":"acct-probe-rollback"}}"#.utf8)
        let originalToml = Data("custom_keep = \"yes\"\n".utf8)
        try CodexPaths.writeSecureFile(originalAuth, to: CodexPaths.authURL)
        try CodexPaths.writeSecureFile(originalToml, to: CodexPaths.configTomlURL)
        try CodexPaths.writeSecureFile(Data("old-pre-api-auth".utf8), to: CodexPaths.authPreAPIBackupURL)
        try CodexPaths.writeSecureFile(Data("old-pre-api-config".utf8), to: CodexPaths.configPreAPIBackupURL)

        let store = TokenStore(
            configStore: CodexBarConfigStore(),
            syncService: CodexSyncService(),
            openRouterGatewayService: OpenRouterGatewayControllerSpy(),
            apiServiceRuntimeController: { RuntimeControllerSpy() },
            apiServiceRoutingProbeAction: { config in
                let authObject = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: CodexPaths.authURL)) as? [String: Any])
                XCTAssertEqual(authObject["auth_mode"] as? String, "apikey")
                XCTAssertEqual(authObject["OPENAI_API_KEY"] as? String, config.clientAPIKey)
                throw URLError(.timedOut)
            },
            codexRunningProcessIDs: { [] }
        )
        let baselineAuth = try Data(contentsOf: CodexPaths.authURL)
        let baselineToml = try Data(contentsOf: CodexPaths.configTomlURL)

        await XCTAssertThrowsErrorAsync(try await store.enableAPIServiceRoutingFromMenu())

        XCTAssertFalse(store.config.desktop.cliProxyAPI.enabled)
        XCTAssertEqual(try Data(contentsOf: CodexPaths.authURL), baselineAuth)
        XCTAssertEqual(try Data(contentsOf: CodexPaths.configTomlURL), baselineToml)
        XCTAssertEqual(try Data(contentsOf: CodexPaths.authPreAPIBackupURL), Data("old-pre-api-auth".utf8))
        XCTAssertEqual(try Data(contentsOf: CodexPaths.configPreAPIBackupURL), Data("old-pre-api-config".utf8))
    }

    func testEnableRoutingCapturesCompatibleSelectionForLaterDirectRestore() async throws {
        let oauthAccount = try self.makeOAuthAccount(
            accountID: "acct-probe-capture-oauth",
            email: "probe-capture-oauth@example.com"
        )
        let storedOAuthAccount = CodexBarProviderAccount.fromTokenAccount(
            oauthAccount,
            existingID: oauthAccount.accountId
        )
        let compatible = self.makeCompatibleProvider()
        try self.writeConfig(
            CodexBarConfig(
                active: CodexBarActiveSelection(
                    providerId: compatible.provider.id,
                    accountId: compatible.account.id
                ),
                desktop: CodexBarDesktopSettings(
                    cliProxyAPI: .init(
                        enabled: false,
                        host: "127.0.0.1",
                        port: 8317,
                        repositoryRootPath: nil,
                        managementSecretKey: "secret",
                        clientAPIKey: "client-key",
                        memberAccountIDs: [storedOAuthAccount.id]
                    )
                ),
                providers: [
                    CodexBarProvider(
                        id: "openai-oauth",
                        kind: .openAIOAuth,
                        label: "OpenAI",
                        activeAccountId: storedOAuthAccount.id,
                        accounts: [storedOAuthAccount]
                    ),
                    compatible.provider,
                ]
            )
        )

        let store = TokenStore(
            configStore: CodexBarConfigStore(),
            syncService: CodexSyncService(),
            openRouterGatewayService: OpenRouterGatewayControllerSpy(),
            apiServiceRuntimeController: { RuntimeControllerSpy() },
            apiServiceRoutingProbeAction: { _ in },
            codexRunningProcessIDs: { [] }
        )

        _ = try await store.enableAPIServiceRoutingFromMenu()

        XCTAssertTrue(store.config.desktop.cliProxyAPI.enabled)
        XCTAssertEqual(store.config.desktop.cliProxyAPI.preAPIServiceActiveProviderID, compatible.provider.id)
        XCTAssertEqual(store.config.desktop.cliProxyAPI.preAPIServiceActiveAccountID, compatible.account.id)
        XCTAssertEqual(store.config.active.providerId, "openai-oauth")
        XCTAssertEqual(store.config.active.accountId, storedOAuthAccount.id)

        try await store.setAPIServiceRoutingEnabledFromMenu(false)

        XCTAssertFalse(store.config.desktop.cliProxyAPI.enabled)
        XCTAssertEqual(store.config.active.providerId, compatible.provider.id)
        XCTAssertEqual(store.config.active.accountId, compatible.account.id)
    }
}

private final class RoutingProbeSyncService: CodexSynchronizing {
    private(set) var callCount = 0
    private(set) var restoreCallCount = 0

    func synchronize(config _: CodexBarConfig) throws {
        self.callCount += 1
    }

    func restoreNativeConfiguration(
        desktopSettings _: CodexBarDesktopSettings
    ) throws -> CodexNativeRestoreResult {
        self.restoreCallCount += 1
        return .init(auth: .unchanged, config: .unchanged)
    }
}

private final class OpenRouterGatewayControllerSpy: OpenRouterGatewayControlling {
    func startIfNeeded() {}
    func stop() {}
    func updateState(provider _: CodexBarProvider?, isActiveProvider _: Bool) {}
}

@MainActor
private final class RuntimeControllerSpy: CLIProxyAPIRuntimeControlling {
    var nextApplyResult = true
    var nextAdoptResult = false
    var appliedSettings: [CodexBarDesktopSettings.CLIProxyAPISettings] = []
    var adoptRequests: [CodexBarDesktopSettings.CLIProxyAPISettings] = []

    @discardableResult
    func applyConfiguration(_ settings: CodexBarDesktopSettings.CLIProxyAPISettings) -> Bool {
        self.appliedSettings.append(settings)
        return self.nextApplyResult
    }

    func adoptRunningServiceIfReusable(_ settings: CodexBarDesktopSettings.CLIProxyAPISettings) async -> Bool {
        self.adoptRequests.append(settings)
        return self.nextAdoptResult
    }

    func stop() {}

    func reconfigureIfRunning(_ settings: CodexBarDesktopSettings.CLIProxyAPISettings) {}
}

private extension APIServiceRoutingEnableTests {
    func makeCompatibleProvider() -> (provider: CodexBarProvider, account: CodexBarProviderAccount) {
        let account = CodexBarProviderAccount(
            id: "acct-compatible-routing",
            kind: .apiKey,
            label: "Compatible",
            apiKey: "sk-compatible-routing"
        )
        let provider = CodexBarProvider(
            id: "compatible-provider-routing",
            kind: .openAICompatible,
            label: "Compatible",
            enabled: true,
            baseURL: "https://example.invalid/v1",
            activeAccountId: account.id,
            accounts: [account]
        )
        return (provider, account)
    }

    func makeRoutingConfig(_ storedOAuthAccount: CodexBarProviderAccount) -> CodexBarConfig {
        CodexBarConfig(
            active: CodexBarActiveSelection(
                providerId: "openai-oauth",
                accountId: storedOAuthAccount.id
            ),
            desktop: CodexBarDesktopSettings(
                cliProxyAPI: .init(
                    enabled: false,
                    host: "127.0.0.1",
                    port: 8317,
                    repositoryRootPath: "/tmp/CLIProxyAPI",
                    managementSecretKey: "secret",
                    clientAPIKey: "client-key",
                    memberAccountIDs: [storedOAuthAccount.id]
                )
            ),
            providers: [
                CodexBarProvider(
                    id: "openai-oauth",
                    kind: .openAIOAuth,
                    label: "OpenAI",
                    activeAccountId: storedOAuthAccount.id,
                    accounts: [storedOAuthAccount]
                ),
            ]
        )
    }

    func XCTAssertThrowsErrorAsync<T>(
        _ expression: @autoclosure () async throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected async error", file: file, line: line)
        } catch {}
    }
}
