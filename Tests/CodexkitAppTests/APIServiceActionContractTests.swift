import Foundation
import XCTest
@testable import CodexkitApp

@MainActor
final class APIServiceActionContractTests: CodexBarTestCase {
    func testSettingsRoutingActionUsesDraftSettingsIncludingClientAPIKey() async throws {
        let oauthAccount = try self.makeOAuthAccount(
            accountID: "acct-settings-routing",
            email: "settings-routing@example.com"
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
                        repositoryRootPath: nil,
                        managementSecretKey: "persisted-management-secret",
                        clientAPIKey: "persisted-client-key",
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

        let runtimeController = RuntimeControllerSpy()
        let store = TokenStore(
            syncService: CodexSyncService(),
            openRouterGatewayService: OpenRouterGatewayControllerSpy(),
            apiServiceRuntimeController: { runtimeController },
            apiServiceRoutingProbeAction: { _ in },
            codexRunningProcessIDs: { [] }
        )

        let message = try await store.setAPIServiceRoutingEnabled(
            true,
            using: CLIProxyAPISettingsUpdate(
                enabled: true,
                host: "0.0.0.0",
                port: 9321,
                repositoryRootPath: nil,
                managementSecretKey: "draft-management-secret",
                clientAPIKey: "draft-client-key",
                memberAccountIDs: [storedOAuthAccount.id],
                restrictFreeAccounts: true,
                routingStrategy: .fillFirst,
                switchProjectOnQuotaExceeded: false,
                switchPreviewModelOnQuotaExceeded: false,
                requestRetry: 9,
                maxRetryInterval: 45,
                disableCooling: true
            )
        )

        let authObject = try self.readAuthJSON()
        let runtimeSettings = try XCTUnwrap(runtimeController.appliedSettings.last)

        XCTAssertEqual(message, L.menuAPIServiceRoutingProbeSuccess)
        XCTAssertEqual(store.config.desktop.cliProxyAPI.host, "0.0.0.0")
        XCTAssertEqual(store.config.desktop.cliProxyAPI.port, 9321)
        XCTAssertEqual(store.config.desktop.cliProxyAPI.managementSecretKey, "draft-management-secret")
        XCTAssertEqual(store.config.desktop.cliProxyAPI.routingStrategy, .fillFirst)
        XCTAssertEqual(store.config.desktop.cliProxyAPI.requestRetry, 9)
        XCTAssertEqual(store.config.desktop.cliProxyAPI.maxRetryInterval, 45)
        XCTAssertTrue(store.config.desktop.cliProxyAPI.disableCooling)
        XCTAssertTrue(store.config.desktop.cliProxyAPI.enabled)
        XCTAssertEqual(authObject["auth_mode"] as? String, "apikey")
        XCTAssertEqual(authObject["OPENAI_API_KEY"] as? String, "draft-client-key")
        XCTAssertEqual(store.config.desktop.cliProxyAPI.clientAPIKey, "draft-client-key")
        XCTAssertEqual(runtimeSettings.clientAPIKey, "draft-client-key")
        XCTAssertEqual(runtimeSettings.host, "0.0.0.0")
        XCTAssertEqual(runtimeSettings.port, 9321)
        XCTAssertEqual(runtimeSettings.managementSecretKey, "draft-management-secret")
        XCTAssertEqual(runtimeSettings.routingStrategy, .fillFirst)
        XCTAssertEqual(runtimeSettings.requestRetry, 9)
        XCTAssertEqual(runtimeSettings.maxRetryInterval, 45)
        XCTAssertTrue(runtimeSettings.disableCooling)
    }

    func testRuntimeActionRollsBackPersistedConfigWhenApplyFails() async throws {
        let oauthAccount = try self.makeOAuthAccount(
            accountID: "acct-runtime-rollback",
            email: "runtime-rollback@example.com"
        )
        let storedOAuthAccount = CodexBarProviderAccount.fromTokenAccount(
            oauthAccount,
            existingID: oauthAccount.accountId
        )
        let baselineConfig = CodexBarConfig(
            active: CodexBarActiveSelection(
                providerId: "openai-oauth",
                accountId: storedOAuthAccount.id
            ),
            desktop: CodexBarDesktopSettings(
                cliProxyAPI: .init(
                    enabled: false,
                    host: "127.0.0.1",
                    port: 8317,
                    repositoryRootPath: nil,
                    managementSecretKey: "baseline-management-secret",
                    clientAPIKey: "baseline-client-key",
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
        try self.writeConfig(baselineConfig)
        try self.writeAuthJSON(
            accessToken: oauthAccount.accessToken,
            refreshToken: oauthAccount.refreshToken,
            idToken: oauthAccount.idToken,
            remoteAccountID: oauthAccount.openAIAccountId
        )
        let baselineAuthObject = try self.readAuthJSON()

        let runtimeController = RuntimeControllerSpy()
        runtimeController.nextApplyResult = false
        let store = TokenStore(
            syncService: CodexSyncService(),
            openRouterGatewayService: OpenRouterGatewayControllerSpy(),
            apiServiceRuntimeController: { runtimeController },
            codexRunningProcessIDs: { [] }
        )

        await self.assertThrowsError {
            try await store.setAPIServiceRuntimeRunning(
                true,
                using: CLIProxyAPISettingsUpdate(
                    enabled: false,
                    host: "0.0.0.0",
                    port: 9321,
                    repositoryRootPath: nil,
                    managementSecretKey: "draft-management-secret",
                    clientAPIKey: nil,
                    memberAccountIDs: [storedOAuthAccount.id],
                    restrictFreeAccounts: true,
                    routingStrategy: .fillFirst,
                    switchProjectOnQuotaExceeded: false,
                    switchPreviewModelOnQuotaExceeded: false,
                    requestRetry: 8,
                    maxRetryInterval: 44,
                    disableCooling: true
                )
            )
        }

        let reloadedConfig = try CodexBarConfigStore().loadOrMigrate()

        XCTAssertEqual(store.config.desktop.cliProxyAPI.host, baselineConfig.desktop.cliProxyAPI.host)
        XCTAssertEqual(store.config.desktop.cliProxyAPI.port, baselineConfig.desktop.cliProxyAPI.port)
        XCTAssertEqual(store.config.desktop.cliProxyAPI.managementSecretKey, baselineConfig.desktop.cliProxyAPI.managementSecretKey)
        XCTAssertEqual(store.config.desktop.cliProxyAPI.routingStrategy, baselineConfig.desktop.cliProxyAPI.routingStrategy)
        XCTAssertEqual(reloadedConfig.desktop.cliProxyAPI.host, baselineConfig.desktop.cliProxyAPI.host)
        XCTAssertEqual(reloadedConfig.desktop.cliProxyAPI.port, baselineConfig.desktop.cliProxyAPI.port)
        let restoredAuthObject = try self.readAuthJSON()
        XCTAssertEqual(restoredAuthObject["auth_mode"] as? String, baselineAuthObject["auth_mode"] as? String)
        let baselineTokens = try XCTUnwrap(baselineAuthObject["tokens"] as? [String: Any])
        let restoredTokens = try XCTUnwrap(restoredAuthObject["tokens"] as? [String: Any])
        XCTAssertEqual(restoredTokens["account_id"] as? String, baselineTokens["account_id"] as? String)
        XCTAssertNil(restoredAuthObject["OPENAI_API_KEY"] as? String)
        XCTAssertEqual(runtimeController.appliedSettings.count, 1)
        XCTAssertEqual(runtimeController.stopCallCount, 1)
    }

    func testSaveSettingsRollsBackWhenRuntimeReconfigureFails() throws {
        let oauthAccount = try self.makeOAuthAccount(
            accountID: "acct-save-runtime-rollback",
            email: "save-runtime-rollback@example.com"
        )
        let storedOAuthAccount = CodexBarProviderAccount.fromTokenAccount(
            oauthAccount,
            existingID: oauthAccount.accountId
        )
        let baselineConfig = CodexBarConfig(
            active: CodexBarActiveSelection(
                providerId: "openai-oauth",
                accountId: storedOAuthAccount.id
            ),
            desktop: CodexBarDesktopSettings(
                cliProxyAPI: .init(
                    enabled: false,
                    host: "127.0.0.1",
                    port: 8317,
                    repositoryRootPath: nil,
                    managementSecretKey: "baseline-management-secret",
                    clientAPIKey: "baseline-client-key",
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
        try self.writeConfig(baselineConfig)
        try self.writeAuthJSON(
            accessToken: oauthAccount.accessToken,
            refreshToken: oauthAccount.refreshToken,
            idToken: oauthAccount.idToken,
            remoteAccountID: oauthAccount.openAIAccountId
        )
        let baselineAuthObject = try self.readAuthJSON()

        let runtimeController = RuntimeControllerSpy()
        runtimeController.nextApplyResult = false
        let store = TokenStore(
            syncService: CodexSyncService(),
            openRouterGatewayService: OpenRouterGatewayControllerSpy(),
            apiServiceRuntimeController: { runtimeController },
            codexRunningProcessIDs: { [] }
        )
        store.updateCLIProxyAPIState(
            CLIProxyAPIServiceState(
                config: store.cliProxyAPIState.config,
                status: .running,
                pid: 4242
            )
        )

        XCTAssertThrowsError(
            try store.saveSettings(
                SettingsSaveRequests(
                    cliProxyAPI: CLIProxyAPISettingsUpdate(
                        enabled: false,
                        host: "0.0.0.0",
                        port: 9321,
                        repositoryRootPath: nil,
                        managementSecretKey: "draft-management-secret",
                        clientAPIKey: nil,
                        memberAccountIDs: [storedOAuthAccount.id],
                        restrictFreeAccounts: true,
                        routingStrategy: .fillFirst,
                        switchProjectOnQuotaExceeded: false,
                        switchPreviewModelOnQuotaExceeded: false,
                        requestRetry: 8,
                        maxRetryInterval: 44,
                        disableCooling: true
                    )
                )
            )
        )

        let reloadedConfig = try CodexBarConfigStore().loadOrMigrate()
        let restoredAuthObject = try self.readAuthJSON()

        XCTAssertEqual(reloadedConfig.desktop.cliProxyAPI.host, baselineConfig.desktop.cliProxyAPI.host)
        XCTAssertEqual(reloadedConfig.desktop.cliProxyAPI.port, baselineConfig.desktop.cliProxyAPI.port)
        XCTAssertEqual(store.config.desktop.cliProxyAPI.host, baselineConfig.desktop.cliProxyAPI.host)
        XCTAssertEqual(store.config.desktop.cliProxyAPI.port, baselineConfig.desktop.cliProxyAPI.port)
        XCTAssertEqual(restoredAuthObject["auth_mode"] as? String, baselineAuthObject["auth_mode"] as? String)
        XCTAssertEqual(runtimeController.appliedSettings.count, 2)
        XCTAssertEqual(runtimeController.stopCallCount, 0)
    }
}

@MainActor
private final class RuntimeControllerSpy: CLIProxyAPIRuntimeControlling {
    var nextApplyResult = true
    var appliedSettings: [CodexBarDesktopSettings.CLIProxyAPISettings] = []
    var stopCallCount = 0
    var reconfigureRequests: [CodexBarDesktopSettings.CLIProxyAPISettings] = []

    @discardableResult
    func applyConfiguration(_ settings: CodexBarDesktopSettings.CLIProxyAPISettings) -> Bool {
        self.appliedSettings.append(settings)
        return self.nextApplyResult
    }

    func stop() {
        self.stopCallCount += 1
    }

    func reconfigureIfRunning(_ settings: CodexBarDesktopSettings.CLIProxyAPISettings) {
        self.reconfigureRequests.append(settings)
    }
}

private final class OpenRouterGatewayControllerSpy: OpenRouterGatewayControlling {
    func startIfNeeded() {}
    func stop() {}
    func updateState(provider _: CodexBarProvider?, isActiveProvider _: Bool) {}
}

private extension APIServiceActionContractTests {
    func assertThrowsError(
        _ expression: @escaping () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await expression()
            XCTFail("Expected async error", file: file, line: line)
        } catch {}
    }
}
