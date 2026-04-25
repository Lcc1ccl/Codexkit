import Foundation
import XCTest
@testable import CodexkitApp

@MainActor
final class TokenStoreGatewayLifecycleTests: CodexBarTestCase {
    func testOpenRouterInitializationKeepsGatewayStoppedWhenInactive() {
        let openRouterGateway = OpenRouterGatewayControllerSpy()

        _ = TokenStore(
            openRouterGatewayService: openRouterGateway,
            codexRunningProcessIDs: { [] }
        )

        XCTAssertEqual(openRouterGateway.startCount, 0)
        XCTAssertEqual(openRouterGateway.stopCount, 1)
    }

    func testOpenRouterInitializationStartsGatewayWhenActiveProviderIsOpenRouter() throws {
        let account = self.makeOpenRouterAccount(id: "acct-openrouter")
        let provider = self.makeOpenRouterProvider(account: account)
        try self.writeConfig(
            CodexBarConfig(
                active: CodexBarActiveSelection(providerId: provider.id, accountId: account.id),
                providers: [provider]
            )
        )

        let openRouterGateway = OpenRouterGatewayControllerSpy()

        _ = TokenStore(
            openRouterGatewayService: openRouterGateway,
            codexRunningProcessIDs: { [] }
        )

        XCTAssertEqual(openRouterGateway.startCount, 1)
        XCTAssertEqual(openRouterGateway.stopCount, 0)
    }

    func testOpenRouterLeaseRestoreStartsGatewayWhenInactiveProviderStillHasServiceableState() throws {
        let openRouterAccount = self.makeOpenRouterAccount(id: "acct-openrouter-restore")
        let openRouterProvider = self.makeOpenRouterProvider(account: openRouterAccount)
        let custom = self.makeCustomProvider()
        let leaseStore = OpenRouterGatewayLeaseStoreSpy(
            initialLease: OpenRouterGatewayLeaseSnapshot(
                processIDs: [404],
                leasedAt: Date(timeIntervalSince1970: 1_710_000_000),
                sourceProviderId: openRouterProvider.id
            )
        )
        let openRouterGateway = OpenRouterGatewayControllerSpy()
        try self.writeConfig(
            CodexBarConfig(
                active: CodexBarActiveSelection(providerId: custom.provider.id, accountId: custom.account.id),
                providers: [openRouterProvider, custom.provider]
            )
        )

        _ = TokenStore(
            syncService: RecordingSyncService(),
            openRouterGatewayService: openRouterGateway,
            openRouterGatewayLeaseStore: leaseStore,
            codexRunningProcessIDs: { [404] }
        )

        XCTAssertEqual(openRouterGateway.startCount, 1)
        XCTAssertEqual(openRouterGateway.stopCount, 0)
        XCTAssertFalse(leaseStore.cleared)
        XCTAssertNil(leaseStore.lastSavedLease)
        XCTAssertEqual(openRouterGateway.lastProvider?.id, openRouterProvider.id)
        XCTAssertFalse(openRouterGateway.lastIsActiveProvider)
    }

    func testOpenRouterLeaseAcquireKeepsGatewayRunningAfterSwitchingAwayFromActiveProvider() throws {
        let openRouterAccount = self.makeOpenRouterAccount(id: "acct-openrouter-acquire")
        let openRouterProvider = self.makeOpenRouterProvider(account: openRouterAccount)
        let custom = self.makeCustomProvider()
        let runningPIDs: Set<pid_t> = [101, 202]
        let leaseStore = OpenRouterGatewayLeaseStoreSpy()
        let openRouterGateway = OpenRouterGatewayControllerSpy()
        try self.writeConfig(
            CodexBarConfig(
                active: CodexBarActiveSelection(providerId: openRouterProvider.id, accountId: openRouterAccount.id),
                providers: [openRouterProvider, custom.provider]
            )
        )

        let store = TokenStore(
            syncService: RecordingSyncService(),
            openRouterGatewayService: openRouterGateway,
            openRouterGatewayLeaseStore: leaseStore,
            codexRunningProcessIDs: { runningPIDs }
        )

        try store.activateCustomProvider(providerID: custom.provider.id, accountID: custom.account.id)

        XCTAssertEqual(openRouterGateway.stopCount, 0)
        XCTAssertEqual(leaseStore.lastSavedLease?.processIDs, runningPIDs)
        XCTAssertEqual(leaseStore.lastSavedLease?.sourceProviderId, "openrouter")
        XCTAssertEqual(openRouterGateway.lastProvider?.id, openRouterProvider.id)
        XCTAssertFalse(openRouterGateway.lastIsActiveProvider)
    }

    func testMenuAPIServiceEnableOnlyStartsRuntimeWithoutChangingSelection() throws {
        let store = TokenStore(
            openRouterGatewayService: OpenRouterGatewayControllerSpy(),
            codexRunningProcessIDs: { [] }
        )
        let account = try self.makeOAuthAccount(
            accountID: "acct-menu-enable",
            email: "menu-enable@example.com"
        )

        store.addOrUpdate(account)
        try store.activate(account)
        let initialProviderID = store.config.active.providerId
        let initialAccountID = store.config.active.accountId

        try store.setAPIServiceEnabledFromMenu(true)

        XCTAssertTrue(store.config.desktop.cliProxyAPI.enabled)
        XCTAssertEqual(store.config.active.providerId, initialProviderID)
        XCTAssertEqual(store.config.active.accountId, initialAccountID)
    }

    func testMenuAPIServiceDisableOnlyStopsRuntimeWithoutReroutingSelection() throws {
        let store = TokenStore(
            openRouterGatewayService: OpenRouterGatewayControllerSpy(),
            codexRunningProcessIDs: { [] }
        )
        var lowerPriority = try self.makeOAuthAccount(
            accountID: "acct-lower-priority",
            email: "lower@example.com"
        )
        lowerPriority.primaryUsedPercent = 82
        lowerPriority.secondaryUsedPercent = 20
        var higherPriority = try self.makeOAuthAccount(
            accountID: "acct-higher-priority",
            email: "higher@example.com"
        )
        higherPriority.primaryUsedPercent = 10
        higherPriority.secondaryUsedPercent = 10

        store.addOrUpdate(lowerPriority)
        store.addOrUpdate(higherPriority)
        try store.activate(lowerPriority)
        let initialProviderID = store.config.active.providerId
        let initialAccountID = store.config.active.accountId
        try store.setAPIServiceEnabledFromMenu(true)

        try store.setAPIServiceEnabledFromMenu(false)

        XCTAssertFalse(store.config.desktop.cliProxyAPI.enabled)
        XCTAssertEqual(store.config.active.providerId, initialProviderID)
        XCTAssertEqual(store.config.active.accountId, initialAccountID)
    }

    func testDisablingAPIServiceRestoresStoredCompatibleProviderSelection() async throws {
        let syncService = RecordingSyncService()
        let oauthAccount = try self.makeOAuthAccount(
            accountID: "acct-restore-compatible-oauth",
            email: "restore-compatible-oauth@example.com"
        )
        let storedOAuthAccount = CodexBarProviderAccount.fromTokenAccount(
            oauthAccount,
            existingID: oauthAccount.accountId
        )
        let compatible = self.makeCustomProvider()
        try self.writeConfig(
            CodexBarConfig(
                active: CodexBarActiveSelection(providerId: "openai-oauth", accountId: storedOAuthAccount.id),
                desktop: CodexBarDesktopSettings(
                    cliProxyAPI: .init(
                        enabled: true,
                        host: "127.0.0.1",
                        port: 8317,
                        repositoryRootPath: nil,
                        managementSecretKey: "management-secret",
                        clientAPIKey: "client-key",
                        preAPIServiceActiveProviderID: compatible.provider.id,
                        preAPIServiceActiveAccountID: compatible.account.id,
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
            syncService: syncService,
            openRouterGatewayService: OpenRouterGatewayControllerSpy(),
            codexRunningProcessIDs: { [] }
        )

        try await store.setAPIServiceRoutingEnabledFromMenu(false)

        XCTAssertFalse(store.config.desktop.cliProxyAPI.enabled)
        XCTAssertEqual(store.config.active.providerId, compatible.provider.id)
        XCTAssertEqual(store.config.active.accountId, compatible.account.id)
        XCTAssertEqual(store.config.provider(id: compatible.provider.id)?.activeAccountId, compatible.account.id)
        XCTAssertEqual(syncService.lastIntent, .disableAPIServiceRestoreDirect)
        XCTAssertEqual(syncService.lastConfig?.active.providerId, compatible.provider.id)
        XCTAssertEqual(syncService.lastConfig?.active.accountId, compatible.account.id)
    }

    func testDisablingAPIServiceRestoresStoredOpenRouterSelection() async throws {
        let syncService = RecordingSyncService()
        let oauthAccount = try self.makeOAuthAccount(
            accountID: "acct-restore-openrouter-oauth",
            email: "restore-openrouter-oauth@example.com"
        )
        let storedOAuthAccount = CodexBarProviderAccount.fromTokenAccount(
            oauthAccount,
            existingID: oauthAccount.accountId
        )
        let openRouterAccount = self.makeOpenRouterAccount(id: "acct-restore-openrouter")
        let openRouterProvider = self.makeOpenRouterProvider(account: openRouterAccount)
        try self.writeConfig(
            CodexBarConfig(
                active: CodexBarActiveSelection(providerId: "openai-oauth", accountId: storedOAuthAccount.id),
                desktop: CodexBarDesktopSettings(
                    cliProxyAPI: .init(
                        enabled: true,
                        host: "127.0.0.1",
                        port: 8317,
                        repositoryRootPath: nil,
                        managementSecretKey: "management-secret",
                        clientAPIKey: "client-key",
                        preAPIServiceActiveProviderID: openRouterProvider.id,
                        preAPIServiceActiveAccountID: openRouterAccount.id,
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
                    openRouterProvider,
                ]
            )
        )

        let store = TokenStore(
            syncService: syncService,
            openRouterGatewayService: OpenRouterGatewayControllerSpy(),
            codexRunningProcessIDs: { [] }
        )

        try await store.setAPIServiceRoutingEnabledFromMenu(false)

        XCTAssertFalse(store.config.desktop.cliProxyAPI.enabled)
        XCTAssertEqual(store.config.active.providerId, openRouterProvider.id)
        XCTAssertEqual(store.config.active.accountId, openRouterAccount.id)
        XCTAssertEqual(store.config.provider(id: openRouterProvider.id)?.activeAccountId, openRouterAccount.id)
        XCTAssertEqual(syncService.lastIntent, .disableAPIServiceRestoreDirect)
        XCTAssertEqual(syncService.lastConfig?.active.providerId, openRouterProvider.id)
        XCTAssertEqual(syncService.lastConfig?.active.accountId, openRouterAccount.id)
    }

    func testSaveSettingsDisablingAPIServiceKeepsCurrentOAuthSelectionWhenNoOAuthIsRoutable() throws {
        var exhaustedOAuth = try self.makeOAuthAccount(
            accountID: "acct-oauth-exhausted",
            email: "oauth-exhausted@example.com"
        )
        exhaustedOAuth.primaryUsedPercent = 100
        let storedOAuth = CodexBarProviderAccount.fromTokenAccount(
            exhaustedOAuth,
            existingID: exhaustedOAuth.accountId
        )
        let oauthProvider = CodexBarProvider(
            id: "openai-oauth",
            kind: .openAIOAuth,
            label: "OpenAI",
            activeAccountId: storedOAuth.id,
            accounts: [storedOAuth]
        )
        let compatible = self.makeCustomProvider()
        try self.writeConfig(
            CodexBarConfig(
                active: CodexBarActiveSelection(providerId: oauthProvider.id, accountId: storedOAuth.id),
                desktop: CodexBarDesktopSettings(
                    cliProxyAPI: .init(
                        enabled: true,
                        host: "127.0.0.1",
                        port: 8317,
                        repositoryRootPath: "/tmp/CLIProxyAPI",
                        managementSecretKey: "secret",
                        memberAccountIDs: [storedOAuth.id]
                    )
                ),
                providers: [oauthProvider, compatible.provider]
            )
        )

        let store = TokenStore(
            openRouterGatewayService: OpenRouterGatewayControllerSpy(),
            codexRunningProcessIDs: { [] }
        )

        try store.saveSettings(
            SettingsSaveRequests(
                cliProxyAPI: CLIProxyAPISettingsUpdate(
                    enabled: false,
                    host: store.config.desktop.cliProxyAPI.host,
                    port: store.config.desktop.cliProxyAPI.port,
                    repositoryRootPath: store.config.desktop.cliProxyAPI.repositoryRootPath,
                    managementSecretKey: store.config.desktop.cliProxyAPI.managementSecretKey,
                    memberAccountIDs: store.config.desktop.cliProxyAPI.memberAccountIDs
                )
            )
        )

        XCTAssertFalse(store.config.desktop.cliProxyAPI.enabled)
        XCTAssertEqual(store.config.active.providerId, oauthProvider.id)
        XCTAssertEqual(store.config.active.accountId, storedOAuth.id)
    }

    func testSavingSettingsDisablingAPIServicePrefersAvailableOAuthAccountOverStoredProviderSelection() throws {
        let oauthAccount = try self.makeOAuthAccount(
            accountID: "acct-oauth-preferred",
            email: "oauth-preferred@example.com"
        )
        let storedOAuthAccount = CodexBarProviderAccount.fromTokenAccount(
            oauthAccount,
            existingID: oauthAccount.accountId
        )
        let compatible = self.makeCustomProvider()
        var config = CodexBarConfig(
            active: CodexBarActiveSelection(
                providerId: "openai-oauth",
                accountId: storedOAuthAccount.id
            ),
            desktop: CodexBarDesktopSettings(
                cliProxyAPI: .init(
                    enabled: true,
                    host: "127.0.0.1",
                    port: 8317,
                    repositoryRootPath: "/tmp/default-CLIProxyAPI",
                    managementSecretKey: "default-secret",
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
        config.setOpenAIAccountOrder([storedOAuthAccount.id])
        try self.writeConfig(config)

        let store = TokenStore(
            openRouterGatewayService: OpenRouterGatewayControllerSpy(),
            codexRunningProcessIDs: { [] }
        )

        try store.saveSettings(
            SettingsSaveRequests(
                cliProxyAPI: CLIProxyAPISettingsUpdate(
                    enabled: false,
                    host: store.config.desktop.cliProxyAPI.host,
                    port: store.config.desktop.cliProxyAPI.port,
                    repositoryRootPath: store.config.desktop.cliProxyAPI.repositoryRootPath,
                    managementSecretKey: store.config.desktop.cliProxyAPI.managementSecretKey,
                    memberAccountIDs: store.config.desktop.cliProxyAPI.memberAccountIDs
                )
            )
        )

        XCTAssertFalse(store.config.desktop.cliProxyAPI.enabled)
        XCTAssertEqual(store.config.active.providerId, "openai-oauth")
        XCTAssertEqual(store.config.active.accountId, storedOAuthAccount.id)
    }

    func testSavingSettingsDisablingAPIServiceKeepsCurrentOAuthSelectionWhenNoOAuthAccountIsAvailable() throws {
        var oauthAccount = try self.makeOAuthAccount(
            accountID: "acct-oauth-unavailable",
            email: "oauth-unavailable@example.com"
        )
        oauthAccount.tokenExpired = true
        let storedOAuthAccount = CodexBarProviderAccount.fromTokenAccount(
            oauthAccount,
            existingID: oauthAccount.accountId
        )
        let compatible = self.makeCustomProvider()
        let config = CodexBarConfig(
            active: CodexBarActiveSelection(
                providerId: "openai-oauth",
                accountId: storedOAuthAccount.id
            ),
            desktop: CodexBarDesktopSettings(
                cliProxyAPI: .init(
                    enabled: true,
                    host: "127.0.0.1",
                    port: 8317,
                    repositoryRootPath: "/tmp/default-CLIProxyAPI",
                    managementSecretKey: "default-secret",
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
        try self.writeConfig(config)

        let store = TokenStore(
            openRouterGatewayService: OpenRouterGatewayControllerSpy(),
            codexRunningProcessIDs: { [] }
        )

        try store.saveSettings(
            SettingsSaveRequests(
                cliProxyAPI: CLIProxyAPISettingsUpdate(
                    enabled: false,
                    host: store.config.desktop.cliProxyAPI.host,
                    port: store.config.desktop.cliProxyAPI.port,
                    repositoryRootPath: store.config.desktop.cliProxyAPI.repositoryRootPath,
                    managementSecretKey: store.config.desktop.cliProxyAPI.managementSecretKey,
                    memberAccountIDs: store.config.desktop.cliProxyAPI.memberAccountIDs
                )
            )
        )

        XCTAssertFalse(store.config.desktop.cliProxyAPI.enabled)
        XCTAssertEqual(store.config.active.providerId, "openai-oauth")
        XCTAssertEqual(store.config.active.accountId, storedOAuthAccount.id)
    }

    func testActivateWhileAPIServiceEnabledAutoDisablesAndSwitchesSelectedAccount() throws {
        let syncService = RecordingSyncService()
        let first = try self.makeOAuthAccount(accountID: "acct-first", email: "first@example.com", isActive: true)
        let second = try self.makeOAuthAccount(accountID: "acct-second", email: "second@example.com")
        let provider = CodexBarProvider(
            id: "openai-oauth",
            kind: .openAIOAuth,
            label: "OpenAI",
            activeAccountId: first.accountId,
            accounts: [
                CodexBarProviderAccount.fromTokenAccount(first, existingID: first.accountId),
                CodexBarProviderAccount.fromTokenAccount(second, existingID: second.accountId),
            ]
        )
        try self.writeConfig(
            CodexBarConfig(
                active: .init(providerId: provider.id, accountId: first.accountId),
                desktop: .init(
                    cliProxyAPI: .init(
                        enabled: true,
                        host: "127.0.0.1",
                        port: 8317,
                        repositoryRootPath: nil,
                        managementSecretKey: "management-secret",
                        clientAPIKey: "client-key",
                        memberAccountIDs: [first.accountId, second.accountId]
                    )
                ),
                providers: [provider]
            )
        )

        let store = TokenStore(
            syncService: syncService,
            openRouterGatewayService: OpenRouterGatewayControllerSpy(),
            codexRunningProcessIDs: { [] }
        )

        try store.activate(second)

        XCTAssertFalse(store.config.desktop.cliProxyAPI.enabled)
        XCTAssertEqual(store.config.active.providerId, "openai-oauth")
        XCTAssertEqual(store.config.active.accountId, second.accountId)
        XCTAssertEqual(syncService.lastIntent, .disableAPIServiceAndSwitch)
    }

    func testSaveSettingsDisablingAPIServiceUsesRestoreDirectIntent() throws {
        let syncService = RecordingSyncService()
        let account = try self.makeOAuthAccount(accountID: "acct-restore-intent", email: "restore-intent@example.com", isActive: true)
        let stored = CodexBarProviderAccount.fromTokenAccount(account, existingID: account.accountId)
        try self.writeConfig(
            CodexBarConfig(
                active: .init(providerId: "openai-oauth", accountId: stored.id),
                desktop: .init(
                    cliProxyAPI: .init(
                        enabled: true,
                        host: "127.0.0.1",
                        port: 8317,
                        repositoryRootPath: nil,
                        managementSecretKey: "management-secret",
                        clientAPIKey: "client-key",
                        memberAccountIDs: [stored.id]
                    )
                ),
                providers: [
                    CodexBarProvider(
                        id: "openai-oauth",
                        kind: .openAIOAuth,
                        label: "OpenAI",
                        activeAccountId: stored.id,
                        accounts: [stored]
                    ),
                ]
            )
        )

        let store = TokenStore(
            syncService: syncService,
            openRouterGatewayService: OpenRouterGatewayControllerSpy(),
            codexRunningProcessIDs: { [] }
        )

        try store.saveSettings(
            SettingsSaveRequests(
                cliProxyAPI: CLIProxyAPISettingsUpdate(
                    enabled: false,
                    host: store.config.desktop.cliProxyAPI.host,
                    port: store.config.desktop.cliProxyAPI.port,
                    repositoryRootPath: store.config.desktop.cliProxyAPI.repositoryRootPath,
                    managementSecretKey: store.config.desktop.cliProxyAPI.managementSecretKey,
                    memberAccountIDs: store.config.desktop.cliProxyAPI.memberAccountIDs
                )
            )
        )

        XCTAssertFalse(store.config.desktop.cliProxyAPI.enabled)
        XCTAssertEqual(syncService.lastIntent, .disableAPIServiceRestoreDirect)
    }

    func testAPIServicePoolServiceabilityReturnsRunningWhenAtLeastOneSelectedAuthIsServiceable() throws {
        let store = TokenStore(
            openRouterGatewayService: OpenRouterGatewayControllerSpy(),
            codexRunningProcessIDs: { [] }
        )
        let account = try self.makeOAuthAccount(
            accountID: "acct-running",
            email: "running@example.com"
        )
        store.addOrUpdate(account)
        try store.saveSettings(
            SettingsSaveRequests(
                cliProxyAPI: CLIProxyAPISettingsUpdate(
                    enabled: true,
                    host: "127.0.0.1",
                    port: 9317,
                    repositoryRootPath: "/tmp/CLIProxyAPI",
                    managementSecretKey: "secret",
                    memberAccountIDs: [account.accountId]
                )
            )
        )
        store.updateCLIProxyAPIState(
            CLIProxyAPIServiceState(
                config: store.cliProxyAPIState.config,
                status: .running,
                observedAuthFiles: [
                    CLIProxyAPIObservedAuthFile(
                        id: "auth-1",
                        fileName: "codex-alpha.json",
                        localAccountID: account.accountId,
                        remoteAccountID: account.remoteAccountId,
                        email: account.email,
                        planType: account.planType,
                        authIndex: "auth-1",
                        priority: 5,
                        status: "active",
                        statusMessage: "ready",
                        disabled: false,
                        unavailable: true,
                        nextRetryAfter: nil
                    )
                ]
            )
        )

        XCTAssertEqual(store.apiServicePoolServiceability(now: Date()), .apiServiceRunning)
    }

    func testAPIServicePoolServiceabilityReturnsObservedPoolUnserviceableWhenAllSelectedAuthsBlocked() throws {
        let store = TokenStore(
            openRouterGatewayService: OpenRouterGatewayControllerSpy(),
            codexRunningProcessIDs: { [] }
        )
        let account = try self.makeOAuthAccount(
            accountID: "acct-blocked",
            email: "blocked@example.com"
        )
        store.addOrUpdate(account)
        try store.saveSettings(
            SettingsSaveRequests(
                cliProxyAPI: CLIProxyAPISettingsUpdate(
                    enabled: true,
                    host: "127.0.0.1",
                    port: 9317,
                    repositoryRootPath: "/tmp/CLIProxyAPI",
                    managementSecretKey: "secret",
                    memberAccountIDs: [account.accountId]
                )
            )
        )
        store.updateCLIProxyAPIState(
            CLIProxyAPIServiceState(
                config: store.cliProxyAPIState.config,
                status: .running,
                observedAuthFiles: [
                    CLIProxyAPIObservedAuthFile(
                        id: "auth-1",
                        fileName: "codex-alpha.json",
                        localAccountID: account.accountId,
                        remoteAccountID: account.remoteAccountId,
                        email: account.email,
                        planType: account.planType,
                        authIndex: "auth-1",
                        priority: 5,
                        status: "cooldown",
                        statusMessage: "retry later",
                        disabled: false,
                        unavailable: true,
                        nextRetryAfter: Date(timeIntervalSinceNow: 300)
                    )
                ]
            )
        )

        XCTAssertEqual(store.apiServicePoolServiceability(now: Date()), .observedPoolUnserviceable)
    }

    func testAPIServicePoolServiceabilityReturnsDegradedWhenRuntimeIsNotRunning() throws {
        let store = TokenStore(
            openRouterGatewayService: OpenRouterGatewayControllerSpy(),
            codexRunningProcessIDs: { [] }
        )
        let account = try self.makeOAuthAccount(
            accountID: "acct-degraded",
            email: "degraded@example.com"
        )
        store.addOrUpdate(account)
        try store.saveSettings(
            SettingsSaveRequests(
                cliProxyAPI: CLIProxyAPISettingsUpdate(
                    enabled: true,
                    host: "127.0.0.1",
                    port: 9317,
                    repositoryRootPath: "/tmp/CLIProxyAPI",
                    managementSecretKey: "secret",
                    memberAccountIDs: [account.accountId]
                )
            )
        )
        store.updateCLIProxyAPIState(
            CLIProxyAPIServiceState(
                config: store.cliProxyAPIState.config,
                status: .failed
            )
        )

        XCTAssertEqual(store.apiServicePoolServiceability(now: Date()), .apiServiceDegraded)
    }

    func testInitializationAbsorbsNewerAuthJSONSnapshot() throws {
        let olderRefreshAt = Date(timeIntervalSince1970: 1_760_000_000)
        let newerRefreshAt = Date(timeIntervalSince1970: 1_760_000_600)
        let localAccount = try self.makeOAuthAccount(
            accountID: "acct_load_reconcile",
            email: "load-reconcile@example.com",
            accessTokenExpiresAt: Date(timeIntervalSince1970: 1_760_003_600),
            oauthClientID: "app_local_load",
            tokenLastRefreshAt: olderRefreshAt
        )
        let authAccount = try self.makeOAuthAccount(
            accountID: "acct_load_reconcile",
            email: "load-reconcile@example.com",
            accessTokenExpiresAt: Date(timeIntervalSince1970: 1_760_007_200),
            oauthClientID: "app_auth_load",
            tokenLastRefreshAt: newerRefreshAt
        )
        let stored = CodexBarProviderAccount.fromTokenAccount(localAccount, existingID: localAccount.accountId)
        let provider = CodexBarProvider(
            id: "openai-oauth",
            kind: .openAIOAuth,
            label: "OpenAI",
            activeAccountId: stored.id,
            accounts: [stored]
        )
        try self.writeConfig(
            CodexBarConfig(
                active: CodexBarActiveSelection(providerId: provider.id, accountId: stored.id),
                providers: [provider]
            )
        )
        try self.writeAuthJSON(
            accessToken: authAccount.accessToken,
            refreshToken: authAccount.refreshToken,
            idToken: authAccount.idToken,
            remoteAccountID: authAccount.remoteAccountId,
            clientID: "app_auth_load",
            lastRefresh: newerRefreshAt
        )

        let store = TokenStore(codexRunningProcessIDs: { [] })

        let resolved = try XCTUnwrap(store.oauthAccount(accountID: localAccount.accountId))
        XCTAssertEqual(resolved.accessToken, authAccount.accessToken)
        XCTAssertEqual(resolved.oauthClientID, "app_auth_load")
        XCTAssertEqual(resolved.tokenLastRefreshAt, newerRefreshAt)
    }

    func testActivateAbsorbsNewerAuthJSONBeforeSynchronizing() throws {
        let syncService = RecordingSyncService()

        let activeOtherAccount = try self.makeOAuthAccount(
            accountID: "acct_active_other",
            email: "active-other@example.com"
        )
        let localAccount = try self.makeOAuthAccount(
            accountID: "acct_activate_reconcile",
            email: "activate-reconcile@example.com",
            accessTokenExpiresAt: Date(timeIntervalSince1970: 1_770_003_600),
            oauthClientID: "app_activate_local",
            tokenLastRefreshAt: Date(timeIntervalSince1970: 1_770_000_000)
        )
        let authAccount = try self.makeOAuthAccount(
            accountID: "acct_activate_reconcile",
            email: "activate-reconcile@example.com",
            accessTokenExpiresAt: Date(timeIntervalSince1970: 1_770_007_200),
            oauthClientID: "app_activate_auth",
            tokenLastRefreshAt: Date(timeIntervalSince1970: 1_770_000_600)
        )
        let provider = CodexBarProvider(
            id: "openai-oauth",
            kind: .openAIOAuth,
            label: "OpenAI",
            activeAccountId: activeOtherAccount.accountId,
            accounts: [
                CodexBarProviderAccount.fromTokenAccount(activeOtherAccount, existingID: activeOtherAccount.accountId),
                CodexBarProviderAccount.fromTokenAccount(localAccount, existingID: localAccount.accountId),
            ]
        )
        try self.writeConfig(
            CodexBarConfig(
                active: CodexBarActiveSelection(providerId: provider.id, accountId: activeOtherAccount.accountId),
                providers: [provider]
            )
        )
        try self.writeAuthJSON(
            accessToken: authAccount.accessToken,
            refreshToken: authAccount.refreshToken,
            idToken: authAccount.idToken,
            remoteAccountID: authAccount.remoteAccountId,
            clientID: "app_activate_auth",
            lastRefresh: Date(timeIntervalSince1970: 1_770_000_600)
        )

        let store = TokenStore(
            syncService: syncService,
            openRouterGatewayService: OpenRouterGatewayControllerSpy(),
            codexRunningProcessIDs: { [] }
        )

        try store.activate(localAccount)

        let synchronizedAccount = try XCTUnwrap(syncService.lastConfig?.activeAccount())
        XCTAssertEqual(synchronizedAccount.accessToken, authAccount.accessToken)
        XCTAssertEqual(synchronizedAccount.oauthClientID, "app_activate_auth")
        XCTAssertEqual(store.activeAccount()?.accessToken, authAccount.accessToken)
    }
}

private final class OpenRouterGatewayControllerSpy: OpenRouterGatewayControlling {
    var startCount = 0
    var stopCount = 0
    private(set) var lastProvider: CodexBarProvider?
    private(set) var lastIsActiveProvider = false

    func startIfNeeded() {
        self.startCount += 1
    }

    func stop() {
        self.stopCount += 1
    }

    func updateState(provider: CodexBarProvider?, isActiveProvider: Bool) {
        self.lastProvider = provider
        self.lastIsActiveProvider = isActiveProvider
    }
}

private final class OpenRouterGatewayLeaseStoreSpy: OpenRouterGatewayLeaseStoring {
    private var currentLease: OpenRouterGatewayLeaseSnapshot?
    private(set) var lastSavedLease: OpenRouterGatewayLeaseSnapshot?
    private(set) var cleared = false

    init(initialLease: OpenRouterGatewayLeaseSnapshot? = nil) {
        self.currentLease = initialLease
    }

    func loadLease() -> OpenRouterGatewayLeaseSnapshot? {
        self.currentLease
    }

    func saveLease(_ lease: OpenRouterGatewayLeaseSnapshot) {
        self.currentLease = lease
        self.lastSavedLease = lease
        self.cleared = false
    }

    func clear() {
        self.currentLease = nil
        self.lastSavedLease = nil
        self.cleared = true
    }
}

private final class RecordingSyncService: CodexSynchronizing {
    private(set) var callCount = 0
    private(set) var lastConfig: CodexBarConfig?
    private(set) var lastIntent: CodexSyncIntent?
    private(set) var restoreCallCount = 0

    func synchronize(config: CodexBarConfig) throws {
        self.callCount += 1
        self.lastConfig = config
        self.lastIntent = nil
    }

    func synchronize(config: CodexBarConfig, intent: CodexSyncIntent) throws {
        self.callCount += 1
        self.lastConfig = config
        self.lastIntent = intent
    }

    func restoreNativeConfiguration(
        desktopSettings _: CodexBarDesktopSettings
    ) throws -> CodexNativeRestoreResult {
        self.restoreCallCount += 1
        return .init(auth: .unchanged, config: .unchanged)
    }
}

private extension TokenStoreGatewayLifecycleTests {
    func makeOpenRouterAccount(id: String) -> CodexBarProviderAccount {
        CodexBarProviderAccount(
            id: id,
            kind: .apiKey,
            label: "Primary",
            apiKey: "sk-or-v1-\(id)"
        )
    }

    func makeOpenRouterProvider(account: CodexBarProviderAccount) -> CodexBarProvider {
        CodexBarProvider(
            id: "openrouter",
            kind: .openRouter,
            label: "OpenRouter",
            enabled: true,
            selectedModelID: "openai/gpt-4.1",
            activeAccountId: account.id,
            accounts: [account]
        )
    }

    func makeCustomProvider() -> (provider: CodexBarProvider, account: CodexBarProviderAccount) {
        let account = CodexBarProviderAccount(
            id: "acct-compatible",
            kind: .apiKey,
            label: "Compatible",
            apiKey: "sk-compatible"
        )
        let provider = CodexBarProvider(
            id: "compatible-provider",
            kind: .openAICompatible,
            label: "Compatible",
            enabled: true,
            baseURL: "https://example.invalid/v1",
            activeAccountId: account.id,
            accounts: [account]
        )
        return (provider, account)
    }
}
