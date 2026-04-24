import Foundation
import XCTest
@testable import CodexkitApp

@MainActor
final class MenuBarAccountSwitchFlowTests: CodexBarTestCase {
    func testUseFlowDispatchesAutoDisableAndSwitchIntentAtStoreSeam() throws {
        let syncService = IntentRecordingSyncService()
        let first = try self.makeOAuthAccount(accountID: "acct-menu-first", email: "menu-first@example.com", isActive: true)
        let second = try self.makeOAuthAccount(accountID: "acct-menu-second", email: "menu-second@example.com")
        try self.writeConfig(self.makeOAuthRoutingConfig(first: first, second: second))

        let store = TokenStore(
            syncService: syncService,
            openRouterGatewayService: OpenRouterGatewayControllerSpy(),
            codexRunningProcessIDs: { [] }
        )

        try store.activate(second)

        XCTAssertEqual(syncService.lastIntent, .disableAPIServiceAndSwitch)
        XCTAssertFalse(store.config.desktop.cliProxyAPI.enabled)
        XCTAssertEqual(store.config.active.accountId, second.accountId)
    }

    func testExplicitRestoreDispatchesDisableRestoreIntentAtStoreSeam() throws {
        let syncService = IntentRecordingSyncService()
        let first = try self.makeOAuthAccount(accountID: "acct-restore-first", email: "restore-first@example.com", isActive: true)
        let second = try self.makeOAuthAccount(accountID: "acct-restore-second", email: "restore-second@example.com")
        try self.writeConfig(self.makeOAuthRoutingConfig(first: first, second: second))

        let store = TokenStore(
            syncService: syncService,
            openRouterGatewayService: OpenRouterGatewayControllerSpy(),
            codexRunningProcessIDs: { [] }
        )

        try store.disableAPIServiceRoutingAndRestoreDirect()

        XCTAssertEqual(syncService.lastIntent, .disableAPIServiceRestoreDirect)
        XCTAssertFalse(store.config.desktop.cliProxyAPI.enabled)
    }

    func testAutoDisableSwitchFailureDoesNotClaimSuccessOrMutateSelection() throws {
        let first = try self.makeOAuthAccount(accountID: "acct-failure-first", email: "failure-first@example.com", isActive: true)
        let second = try self.makeOAuthAccount(accountID: "acct-failure-second", email: "failure-second@example.com")
        try self.writeConfig(self.makeOAuthRoutingConfig(first: first, second: second))

        let store = TokenStore(
            syncService: FailingIntentSyncService(),
            openRouterGatewayService: OpenRouterGatewayControllerSpy(),
            codexRunningProcessIDs: { [] }
        )

        XCTAssertThrowsError(try store.activate(second))
        XCTAssertTrue(store.config.desktop.cliProxyAPI.enabled)
        XCTAssertEqual(store.config.active.accountId, first.accountId)
    }
}

private final class IntentRecordingSyncService: CodexSynchronizing {
    private(set) var lastIntent: CodexSyncIntent?

    func synchronize(config _: CodexBarConfig) throws {
        self.lastIntent = nil
    }

    func synchronize(config _: CodexBarConfig, intent: CodexSyncIntent) throws {
        self.lastIntent = intent
    }
}

private struct FailingIntentSyncService: CodexSynchronizing {
    func synchronize(config _: CodexBarConfig) throws {
        throw TestError.syncFailed
    }

    func synchronize(config _: CodexBarConfig, intent _: CodexSyncIntent) throws {
        throw TestError.syncFailed
    }

    private enum TestError: Error {
        case syncFailed
    }
}

private final class OpenRouterGatewayControllerSpy: OpenRouterGatewayControlling {
    func startIfNeeded() {}
    func stop() {}
    func updateState(provider _: CodexBarProvider?, isActiveProvider _: Bool) {}
}

private extension MenuBarAccountSwitchFlowTests {
    func makeOAuthRoutingConfig(first: TokenAccount, second: TokenAccount) -> CodexBarConfig {
        let storedFirst = CodexBarProviderAccount.fromTokenAccount(first, existingID: first.accountId)
        let storedSecond = CodexBarProviderAccount.fromTokenAccount(second, existingID: second.accountId)
        return CodexBarConfig(
            active: .init(providerId: "openai-oauth", accountId: storedFirst.id),
            desktop: .init(
                cliProxyAPI: .init(
                    enabled: true,
                    host: "127.0.0.1",
                    port: 8317,
                    repositoryRootPath: nil,
                    managementSecretKey: "management-secret",
                    clientAPIKey: "client-key",
                    memberAccountIDs: [storedFirst.id, storedSecond.id]
                )
            ),
            providers: [
                CodexBarProvider(
                    id: "openai-oauth",
                    kind: .openAIOAuth,
                    label: "OpenAI",
                    activeAccountId: storedFirst.id,
                    accounts: [storedFirst, storedSecond]
                ),
            ]
        )
    }
}
