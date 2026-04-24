import XCTest
@testable import CodexkitApp

@MainActor
final class SettingsWindowCoordinatorTests: XCTestCase {
    func testInitializerSupportsStartingOnAPIServicePage() {
        let accounts = [
            self.makeAccount(email: "alpha@example.com", accountId: "acct_alpha"),
            self.makeAccount(email: "beta@example.com", accountId: "acct_beta"),
        ]
        let coordinator = SettingsWindowCoordinator(
            config: self.makeConfig(),
            accounts: accounts,
            selectedPage: .apiService
        )

        XCTAssertEqual(coordinator.selectedPage, .apiService)
        XCTAssertFalse(coordinator.hasCurrentPageChanges)

        coordinator.update(\.cliProxyAPIEnabled, to: true, field: .cliProxyAPIEnabled)

        XCTAssertTrue(coordinator.hasCurrentPageChanges)

        coordinator.requestPageSelection(.accounts)

        XCTAssertEqual(coordinator.selectedPage, .apiService)
        XCTAssertEqual(coordinator.pendingAction, .selectPage(.accounts))
    }

    func testInitializerSupportsStartingOnGeneralPage() {
        let accounts = [
            self.makeAccount(email: "alpha@example.com", accountId: "acct_alpha"),
            self.makeAccount(email: "beta@example.com", accountId: "acct_beta"),
        ]
        let coordinator = SettingsWindowCoordinator(
            config: self.makeConfig(),
            accounts: accounts,
            selectedPage: .general
        )

        XCTAssertEqual(coordinator.selectedPage, .general)
        XCTAssertFalse(coordinator.hasCurrentPageChanges)
    }

    func testInitializerSupportsStartingOnOperationalPages() {
        let accounts = [
            self.makeAccount(email: "alpha@example.com", accountId: "acct_alpha"),
            self.makeAccount(email: "beta@example.com", accountId: "acct_beta"),
        ]

        for page in [SettingsPage.provider, .apiServiceDashboard, .apiServiceLogs] {
            let coordinator = SettingsWindowCoordinator(
                config: self.makeConfig(),
                accounts: accounts,
                selectedPage: page
            )

            XCTAssertEqual(coordinator.selectedPage, page)
            XCTAssertFalse(coordinator.hasCurrentPageChanges)
            XCTAssertFalse(coordinator.hasChanges(on: page))
        }
    }

    func testSwitchingPagesKeepsDraftAcrossEdits() {
        let accounts = [
            self.makeAccount(email: "alpha@example.com", accountId: "acct_alpha"),
            self.makeAccount(email: "beta@example.com", accountId: "acct_beta"),
        ]
        let coordinator = SettingsWindowCoordinator(
            config: self.makeConfig(),
            accounts: accounts
        )

        coordinator.update(\.accountOrderingMode, to: .manual, field: .accountOrderingMode)
        coordinator.update(\.manualActivationBehavior, to: .launchNewInstance, field: .manualActivationBehavior)
        coordinator.selectedPage = .general
        coordinator.update(\.menuBarQuotaVisibility, to: .secondaryOnly, field: .menuBarQuotaVisibility)
        coordinator.update(\.menuBarAPIServiceStatusVisibility, to: .hidden, field: .menuBarAPIServiceStatusVisibility)
        coordinator.selectedPage = .usage
        coordinator.update(\.usageDisplayMode, to: .remaining, field: .usageDisplayMode)
        coordinator.update(\.plusRelativeWeight, to: 12, field: .plusRelativeWeight)
        coordinator.update(\.proRelativeToPlusMultiplier, to: 14, field: .proRelativeToPlusMultiplier)
        coordinator.selectedPage = .accounts
        coordinator.update(\.preferredCodexAppPath, to: "/Applications/Codex.app", field: .preferredCodexAppPath)
        coordinator.selectedPage = .apiService
        coordinator.update(\.cliProxyAPIEnabled, to: true, field: .cliProxyAPIEnabled)
        coordinator.update(\.cliProxyAPIHost, to: "0.0.0.0", field: .cliProxyAPIHost)
        coordinator.update(\.cliProxyAPIPort, to: 9317, field: .cliProxyAPIPort)
        coordinator.update(\.cliProxyAPIManagementSecretKey, to: "manual-secret", field: .cliProxyAPIManagementSecretKey)
        coordinator.update(\.cliProxyAPIMemberAccountIDs, to: ["acct_alpha"], field: .cliProxyAPIMemberAccountIDs)
        coordinator.selectedPage = .updates

        XCTAssertEqual(coordinator.draft.accountOrderingMode, .manual)
        XCTAssertEqual(coordinator.draft.manualActivationBehavior, .launchNewInstance)
        coordinator.selectedPage = .general
        XCTAssertEqual(coordinator.draft.menuBarQuotaVisibility, .secondaryOnly)
        XCTAssertEqual(coordinator.draft.menuBarAPIServiceStatusVisibility, .hidden)
        coordinator.selectedPage = .usage
        XCTAssertEqual(coordinator.draft.usageDisplayMode, .remaining)
        XCTAssertEqual(coordinator.draft.plusRelativeWeight, 12)
        XCTAssertEqual(coordinator.draft.proRelativeToPlusMultiplier, 14)
        coordinator.selectedPage = .accounts
        XCTAssertEqual(coordinator.draft.preferredCodexAppPath, "/Applications/Codex.app")
        coordinator.selectedPage = .apiService
        XCTAssertTrue(coordinator.draft.cliProxyAPIEnabled)
        XCTAssertEqual(coordinator.draft.cliProxyAPIHost, "0.0.0.0")
        XCTAssertEqual(coordinator.draft.cliProxyAPIPort, 9317)
        XCTAssertEqual(coordinator.draft.cliProxyAPIManagementSecretKey, "manual-secret")
        XCTAssertEqual(coordinator.draft.cliProxyAPIMemberAccountIDs, ["acct_alpha"])
    }

    func testManualAccountOrderSectionVisibilityFollowsOrderingMode() {
        let accounts = [
            self.makeAccount(email: "alpha@example.com", accountId: "acct_alpha"),
            self.makeAccount(email: "beta@example.com", accountId: "acct_beta"),
        ]
        let coordinator = SettingsWindowCoordinator(
            config: self.makeConfig(accountOrderingMode: .quotaSort),
            accounts: accounts
        )

        XCTAssertFalse(coordinator.showsManualAccountOrderSection)

        coordinator.update(\.accountOrderingMode, to: .manual, field: .accountOrderingMode)
        XCTAssertTrue(coordinator.showsManualAccountOrderSection)

        coordinator.update(\.accountOrderingMode, to: .quotaSort, field: .accountOrderingMode)
        XCTAssertFalse(coordinator.showsManualAccountOrderSection)
    }

    func testCodexAppPathSectionVisibilityFollowsManualActivationBehavior() {
        let accounts = [
            self.makeAccount(email: "alpha@example.com", accountId: "acct_alpha"),
            self.makeAccount(email: "beta@example.com", accountId: "acct_beta"),
        ]
        let coordinator = SettingsWindowCoordinator(
            config: self.makeConfig(),
            accounts: accounts
        )

        XCTAssertFalse(coordinator.showsCodexAppPathSection)

        coordinator.update(\.manualActivationBehavior, to: .launchNewInstance, field: .manualActivationBehavior)
        XCTAssertTrue(coordinator.showsCodexAppPathSection)

        coordinator.update(\.manualActivationBehavior, to: .updateConfigOnly, field: .manualActivationBehavior)
        XCTAssertFalse(coordinator.showsCodexAppPathSection)
    }

    func testAccountActivationPathsSectionVisibilityFollowsScopeMode() {
        let accounts = [
            self.makeAccount(email: "alpha@example.com", accountId: "acct_alpha"),
            self.makeAccount(email: "beta@example.com", accountId: "acct_beta"),
        ]
        let coordinator = SettingsWindowCoordinator(
            config: self.makeConfig(),
            accounts: accounts
        )

        XCTAssertFalse(coordinator.showsAccountActivationPathsSection)

        coordinator.update(\.accountActivationScopeMode, to: .specificPaths, field: .accountActivationScopeMode)
        XCTAssertTrue(coordinator.showsAccountActivationPathsSection)

        coordinator.update(\.accountActivationScopeMode, to: .globalAndSpecificPaths, field: .accountActivationScopeMode)
        XCTAssertTrue(coordinator.showsAccountActivationPathsSection)

        coordinator.update(\.accountActivationScopeMode, to: .global, field: .accountActivationScopeMode)
        XCTAssertFalse(coordinator.showsAccountActivationPathsSection)
    }

    func testAccountsPageSavePersistsServiceTier() throws {
        let accounts = [
            self.makeAccount(email: "alpha@example.com", accountId: "acct_alpha"),
        ]
        let sink = TestSettingsSaveSink(config: self.makeConfig())
        let coordinator = SettingsWindowCoordinator(
            config: sink.config,
            accounts: accounts,
            selectedPage: .accounts
        )

        coordinator.update(\.serviceTier, to: .fast, field: .serviceTier)

        let requests = try coordinator.save(page: .accounts, using: sink)

        XCTAssertEqual(requests.openAIAccount?.serviceTier, .fast)
        XCTAssertEqual(sink.config.global.serviceTier, .fast)

        let reopened = SettingsWindowCoordinator(
            config: sink.config,
            accounts: accounts,
            selectedPage: .accounts
        )
        XCTAssertEqual(reopened.draft.serviceTier, .fast)
    }

    func testManualActivationBehaviorSectionRemainsVisibleWithoutUsageModeSetting() {
        let accounts = [
            self.makeAccount(email: "alpha@example.com", accountId: "acct_alpha"),
            self.makeAccount(email: "beta@example.com", accountId: "acct_beta"),
        ]
        let coordinator = SettingsWindowCoordinator(
            config: self.makeConfig(),
            accounts: accounts
        )

        XCTAssertTrue(coordinator.showsManualActivationBehaviorSection)
    }

    func testSaveEmitsChangedDomainRequestsAndReopenReflectsSavedValues() throws {
        let accounts = [
            self.makeAccount(email: "alpha@example.com", accountId: "acct_alpha"),
            self.makeAccount(email: "beta@example.com", accountId: "acct_beta"),
        ]
        let sink = TestSettingsSaveSink(config: self.makeConfig())
        let coordinator = SettingsWindowCoordinator(
            config: sink.config,
            accounts: accounts
        )

        coordinator.update(\.accountOrderingMode, to: .manual, field: .accountOrderingMode)
        coordinator.setAccountOrder(["acct_beta", "acct_alpha"])
        coordinator.update(\.manualActivationBehavior, to: .launchNewInstance, field: .manualActivationBehavior)
        coordinator.selectedPage = .general
        coordinator.update(\.menuBarQuotaVisibility, to: .secondaryOnly, field: .menuBarQuotaVisibility)
        coordinator.update(\.menuBarAPIServiceStatusVisibility, to: .hidden, field: .menuBarAPIServiceStatusVisibility)
        coordinator.selectedPage = .usage
        coordinator.update(\.usageDisplayMode, to: .remaining, field: .usageDisplayMode)
        coordinator.update(\.plusRelativeWeight, to: 12, field: .plusRelativeWeight)
        coordinator.update(\.proRelativeToPlusMultiplier, to: 14, field: .proRelativeToPlusMultiplier)
        coordinator.update(\.teamRelativeToPlusMultiplier, to: 2.2, field: .teamRelativeToPlusMultiplier)
        coordinator.selectedPage = .accounts
        coordinator.update(\.preferredCodexAppPath, to: "/Applications/Codex.app", field: .preferredCodexAppPath)
        coordinator.update(\.accountActivationScopeMode, to: .specificPaths, field: .accountActivationScopeMode)
        coordinator.update(
            \.accountActivationRootPaths,
            to: ["/tmp/project-b", "/tmp/project-a", "/tmp/project-b"],
            field: .accountActivationRootPaths
        )
        coordinator.selectedPage = .apiService
        coordinator.update(\.cliProxyAPIEnabled, to: true, field: .cliProxyAPIEnabled)
        coordinator.update(\.cliProxyAPIHost, to: "0.0.0.0", field: .cliProxyAPIHost)
        coordinator.update(\.cliProxyAPIPort, to: 9317, field: .cliProxyAPIPort)
        coordinator.update(\.cliProxyAPIManagementSecretKey, to: "manual-secret", field: .cliProxyAPIManagementSecretKey)
        coordinator.update(\.cliProxyAPIMemberAccountIDs, to: ["acct_alpha"], field: .cliProxyAPIMemberAccountIDs)

        let requests = try coordinator.save(using: sink)

        XCTAssertEqual(sink.appliedRequests.count, 1)
        XCTAssertEqual(
            requests.openAIAccount,
            OpenAIAccountSettingsUpdate(
                accountOrder: ["acct_beta", "acct_alpha"],
                accountOrderingMode: .manual,
                manualActivationBehavior: .launchNewInstance
            )
        )
        XCTAssertEqual(
            requests.openAIGeneral,
            OpenAIGeneralSettingsUpdate(
                menuBarQuotaVisibility: .secondaryOnly,
                menuBarAPIServiceStatusVisibility: .hidden
            )
        )
        XCTAssertEqual(
            requests.openAIUsage,
            OpenAIUsageSettingsUpdate(
                usageDisplayMode: .remaining,
                plusRelativeWeight: 12,
                proRelativeToPlusMultiplier: 14,
                teamRelativeToPlusMultiplier: 2.2
            )
        )
        XCTAssertEqual(
            requests.desktop,
            DesktopSettingsUpdate(
                preferredCodexAppPath: "/Applications/Codex.app",
                accountActivationScopeMode: .specificPaths,
                accountActivationRootPaths: ["/tmp/project-b", "/tmp/project-a"]
            )
        )
        let apiRequest = try XCTUnwrap(requests.cliProxyAPI)
        XCTAssertTrue(apiRequest.enabled)
        XCTAssertEqual(apiRequest.host, "0.0.0.0")
        XCTAssertEqual(apiRequest.port, 9317)
        XCTAssertNil(apiRequest.repositoryRootPath)
        XCTAssertEqual(apiRequest.managementSecretKey, "manual-secret")
        XCTAssertEqual(apiRequest.memberAccountIDs, ["acct_alpha"])
        XCTAssertEqual(apiRequest.routingStrategy, .fillFirst)
        XCTAssertFalse(apiRequest.switchPreviewModelOnQuotaExceeded)
        XCTAssertEqual(apiRequest.requestRetry, 2)
        XCTAssertEqual(apiRequest.maxRetryInterval, 20)

        let reopened = SettingsWindowCoordinator(
            config: sink.config,
            accounts: accounts
        )
        XCTAssertEqual(reopened.draft.accountOrder, ["acct_beta", "acct_alpha"])
        XCTAssertEqual(reopened.draft.accountOrderingMode, .manual)
        XCTAssertEqual(reopened.draft.manualActivationBehavior, .launchNewInstance)
        XCTAssertEqual(reopened.draft.menuBarQuotaVisibility, .secondaryOnly)
        XCTAssertEqual(reopened.draft.menuBarAPIServiceStatusVisibility, .hidden)
        XCTAssertEqual(reopened.draft.usageDisplayMode, .remaining)
        XCTAssertEqual(reopened.draft.plusRelativeWeight, 12)
        XCTAssertEqual(reopened.draft.proRelativeToPlusMultiplier, 14)
        XCTAssertEqual(reopened.draft.teamRelativeToPlusMultiplier, 2.2)
        XCTAssertEqual(reopened.draft.preferredCodexAppPath, "/Applications/Codex.app")
        XCTAssertEqual(reopened.draft.accountActivationScopeMode, .specificPaths)
        XCTAssertEqual(reopened.draft.accountActivationRootPaths, ["/tmp/project-b", "/tmp/project-a"])
        XCTAssertTrue(reopened.draft.cliProxyAPIEnabled)
        XCTAssertEqual(reopened.draft.cliProxyAPIPort, 9317)
        XCTAssertEqual(reopened.draft.cliProxyAPIMemberAccountIDs, ["acct_alpha"])
        XCTAssertFalse(reopened.draft.cliProxyAPIHost.isEmpty)
        XCTAssertFalse(reopened.draft.cliProxyAPIManagementSecretKey.isEmpty)
    }

    func testPageScopedSaveOnlyAppliesCurrentPageRequests() throws {
        let accounts = [
            self.makeAccount(email: "alpha@example.com", accountId: "acct_alpha"),
            self.makeAccount(email: "beta@example.com", accountId: "acct_beta"),
        ]
        let sink = TestSettingsSaveSink(config: self.makeConfig())
        let coordinator = SettingsWindowCoordinator(
            config: sink.config,
            accounts: accounts
        )

        coordinator.update(\.accountOrderingMode, to: .manual, field: .accountOrderingMode)
        coordinator.selectedPage = .usage
        coordinator.update(\.usageDisplayMode, to: .remaining, field: .usageDisplayMode)
        coordinator.update(\.plusRelativeWeight, to: 12, field: .plusRelativeWeight)
        coordinator.selectedPage = .apiService
        coordinator.update(\.cliProxyAPIEnabled, to: true, field: .cliProxyAPIEnabled)
        coordinator.update(\.cliProxyAPIHost, to: "0.0.0.0", field: .cliProxyAPIHost)
        coordinator.update(\.cliProxyAPIPort, to: 9317, field: .cliProxyAPIPort)

        let requests = try coordinator.save(page: .apiService, using: sink)

        XCTAssertEqual(sink.appliedRequests.count, 1)
        XCTAssertNil(requests.openAIAccount)
        XCTAssertNil(requests.openAIUsage)
        XCTAssertNil(requests.desktop)
        let apiRequest = try XCTUnwrap(requests.cliProxyAPI)
        XCTAssertTrue(apiRequest.enabled)
        XCTAssertEqual(apiRequest.host, "0.0.0.0")
        XCTAssertEqual(apiRequest.port, 9317)
        XCTAssertNil(apiRequest.repositoryRootPath)
        XCTAssertEqual(apiRequest.routingStrategy, .fillFirst)
        XCTAssertEqual(apiRequest.requestRetry, coordinator.draft.cliProxyAPIRequestRetry)
        XCTAssertEqual(apiRequest.maxRetryInterval, coordinator.draft.cliProxyAPIMaxRetryInterval)
        XCTAssertEqual(apiRequest.disableCooling, coordinator.draft.cliProxyAPIDisableCooling)
        XCTAssertTrue(coordinator.hasChanges(on: .accounts))
        XCTAssertTrue(coordinator.hasChanges(on: .usage))
        XCTAssertFalse(coordinator.hasChanges(on: .apiService))
    }

    func testGeneralPageSaveOnlyAppliesGeneralRequests() throws {
        let accounts = [
            self.makeAccount(email: "alpha@example.com", accountId: "acct_alpha"),
            self.makeAccount(email: "beta@example.com", accountId: "acct_beta"),
        ]
        let sink = TestSettingsSaveSink(config: self.makeConfig())
        let coordinator = SettingsWindowCoordinator(
            config: sink.config,
            accounts: accounts
        )

        coordinator.selectedPage = .general
        coordinator.update(\.menuBarQuotaVisibility, to: .primaryOnly, field: .menuBarQuotaVisibility)
        coordinator.update(\.menuBarAPIServiceStatusVisibility, to: .hidden, field: .menuBarAPIServiceStatusVisibility)
        coordinator.selectedPage = .usage
        coordinator.update(\.plusRelativeWeight, to: 12, field: .plusRelativeWeight)

        let requests = try coordinator.save(page: .general, using: sink)

        XCTAssertNil(requests.openAIAccount)
        XCTAssertNil(requests.openAIUsage)
        XCTAssertNil(requests.desktop)
        XCTAssertNil(requests.cliProxyAPI)
        XCTAssertEqual(
            requests.openAIGeneral,
            OpenAIGeneralSettingsUpdate(
                menuBarQuotaVisibility: .primaryOnly,
                menuBarAPIServiceStatusVisibility: .hidden
            )
        )
        XCTAssertFalse(coordinator.hasChanges(on: .general))
        XCTAssertTrue(coordinator.hasChanges(on: .usage))
    }

    func testOperationalPagesNeverEmitSaveRequests() throws {
        let accounts = [
            self.makeAccount(email: "alpha@example.com", accountId: "acct_alpha"),
            self.makeAccount(email: "beta@example.com", accountId: "acct_beta"),
        ]
        let sink = TestSettingsSaveSink(config: self.makeConfig())
        let coordinator = SettingsWindowCoordinator(
            config: sink.config,
            accounts: accounts
        )

        coordinator.update(\.usageDisplayMode, to: .remaining, field: .usageDisplayMode)

        for page in [SettingsPage.provider, .apiServiceDashboard, .apiServiceLogs] {
            let requests = try coordinator.save(page: page, using: sink)
            XCTAssertTrue(requests.isEmpty, "Expected \(page) save to stay empty")
            XCTAssertFalse(coordinator.hasChanges(on: page))
        }

        XCTAssertTrue(coordinator.hasChanges(on: .usage))
    }

    func testAPIServiceSaveFiltersSelectedFreeMembersWhenRestrictionEnabled() throws {
        let accounts = [
            self.makeAccount(email: "plus@example.com", accountId: "acct_alpha", planType: "plus"),
            self.makeAccount(email: "free@example.com", accountId: "acct_beta", planType: "free"),
        ]
        let sink = TestSettingsSaveSink(config: self.makeConfig(accountOrder: ["acct_alpha", "acct_beta"]))
        let coordinator = SettingsWindowCoordinator(
            config: sink.config,
            accounts: accounts
        )

        coordinator.selectedPage = .apiService
        coordinator.update(\.cliProxyAPIMemberAccountIDs, to: ["acct_alpha", "acct_beta"], field: .cliProxyAPIMemberAccountIDs)

        let requests = try coordinator.save(page: .apiService, using: sink)

        let apiRequest = try XCTUnwrap(requests.cliProxyAPI)
        XCTAssertTrue(apiRequest.restrictFreeAccounts)
        XCTAssertEqual(apiRequest.memberAccountIDs, ["acct_alpha"])
        XCTAssertEqual(sink.config.desktop.cliProxyAPI.memberAccountIDs, ["acct_alpha"])
        XCTAssertTrue(sink.config.desktop.cliProxyAPI.restrictFreeAccounts)
    }

    func testAPIServiceSaveKeepsFreeMembersWhenRestrictionDisabled() throws {
        let accounts = [
            self.makeAccount(email: "plus@example.com", accountId: "acct_alpha", planType: "plus"),
            self.makeAccount(email: "free@example.com", accountId: "acct_beta", planType: "free"),
        ]
        let sink = TestSettingsSaveSink(config: self.makeConfig(accountOrder: ["acct_alpha", "acct_beta"]))
        let coordinator = SettingsWindowCoordinator(
            config: sink.config,
            accounts: accounts
        )

        coordinator.selectedPage = .apiService
        coordinator.update(\.cliProxyAPIMemberAccountIDs, to: ["acct_alpha", "acct_beta"], field: .cliProxyAPIMemberAccountIDs)
        coordinator.update(\.cliProxyAPIRestrictFreeAccounts, to: false, field: .cliProxyAPIRestrictFreeAccounts)

        let requests = try coordinator.save(page: .apiService, using: sink)

        let apiRequest = try XCTUnwrap(requests.cliProxyAPI)
        XCTAssertFalse(apiRequest.restrictFreeAccounts)
        XCTAssertEqual(apiRequest.memberAccountIDs, ["acct_alpha", "acct_beta"])
        XCTAssertFalse(sink.config.desktop.cliProxyAPI.restrictFreeAccounts)
    }

    func testEditingGeneralSettingsDoesNotMutateUsageDisplayModeOrQuotaSortValues() throws {
        let accounts = [
            self.makeAccount(email: "alpha@example.com", accountId: "acct_alpha"),
            self.makeAccount(email: "beta@example.com", accountId: "acct_beta"),
        ]
        let sink = TestSettingsSaveSink(config: self.makeConfig())
        let coordinator = SettingsWindowCoordinator(
            config: sink.config,
            accounts: accounts
        )

        let baselineUsageDisplayMode = coordinator.draft.usageDisplayMode
        let baselinePlusWeight = coordinator.draft.plusRelativeWeight
        let baselineProRatio = coordinator.draft.proRelativeToPlusMultiplier
        let baselineTeamRatio = coordinator.draft.teamRelativeToPlusMultiplier

        coordinator.selectedPage = .general
        coordinator.update(\.menuBarQuotaVisibility, to: .secondaryOnly, field: .menuBarQuotaVisibility)
        coordinator.update(\.menuBarAPIServiceStatusVisibility, to: .hidden, field: .menuBarAPIServiceStatusVisibility)

        let requests = try coordinator.save(page: .general, using: sink)

        XCTAssertEqual(coordinator.draft.usageDisplayMode, baselineUsageDisplayMode)
        XCTAssertEqual(coordinator.draft.plusRelativeWeight, baselinePlusWeight)
        XCTAssertEqual(coordinator.draft.proRelativeToPlusMultiplier, baselineProRatio)
        XCTAssertEqual(coordinator.draft.teamRelativeToPlusMultiplier, baselineTeamRatio)
        XCTAssertEqual(sink.config.openAI.usageDisplayMode, baselineUsageDisplayMode)
        XCTAssertEqual(sink.config.openAI.quotaSort.plusRelativeWeight, baselinePlusWeight)
        XCTAssertEqual(sink.config.openAI.quotaSort.proRelativeToPlusMultiplier, baselineProRatio)
        XCTAssertEqual(sink.config.openAI.quotaSort.teamRelativeToPlusMultiplier, baselineTeamRatio)
        XCTAssertNil(requests.openAIUsage)
    }

    func testUpdatesPageSavePersistsManagedUpdateSettingsAndReopens() throws {
        let accounts = [
            self.makeAccount(email: "alpha@example.com", accountId: "acct_alpha"),
            self.makeAccount(email: "beta@example.com", accountId: "acct_beta"),
        ]
        let sink = TestSettingsSaveSink(config: self.makeConfig())
        let coordinator = SettingsWindowCoordinator(
            config: sink.config,
            accounts: accounts,
            selectedPage: .updates
        )

        coordinator.update(\.codexkitAutomaticallyChecksForUpdates, to: false, field: .codexkitAutomaticallyChecksForUpdates)
        coordinator.update(\.codexkitAutomaticallyInstallsUpdates, to: true, field: .codexkitAutomaticallyInstallsUpdates)
        coordinator.update(\.codexkitUpdateCheckSchedule, to: .weekly, field: .codexkitUpdateCheckSchedule)
        coordinator.update(\.cliProxyAPIAutomaticallyChecksForUpdates, to: true, field: .cliProxyAPIAutomaticallyChecksForUpdates)
        coordinator.update(\.cliProxyAPIAutomaticallyInstallsUpdates, to: true, field: .cliProxyAPIAutomaticallyInstallsUpdates)
        coordinator.update(\.cliProxyAPIUpdateCheckSchedule, to: .monthly, field: .cliProxyAPIUpdateCheckSchedule)

        let requests = try coordinator.save(page: .updates, using: sink)

        XCTAssertEqual(
            requests.desktop,
            DesktopSettingsUpdate(
                preferredCodexAppPath: nil,
                accountActivationScopeMode: nil,
                accountActivationRootPaths: nil,
                codexkitUpdate: .init(
                    automaticallyChecksForUpdates: false,
                    automaticallyInstallsUpdates: true,
                    checkSchedule: .weekly
                ),
                cliProxyAPIUpdate: .init(
                    automaticallyChecksForUpdates: true,
                    automaticallyInstallsUpdates: true,
                    checkSchedule: .monthly
                )
            )
        )
        XCTAssertNil(requests.openAIAccount)
        XCTAssertNil(requests.openAIUsage)
        XCTAssertNil(requests.cliProxyAPI)

        let reopened = SettingsWindowCoordinator(
            config: sink.config,
            accounts: accounts,
            selectedPage: .updates
        )
        XCTAssertFalse(reopened.draft.codexkitAutomaticallyChecksForUpdates)
        XCTAssertTrue(reopened.draft.codexkitAutomaticallyInstallsUpdates)
        XCTAssertEqual(reopened.draft.codexkitUpdateCheckSchedule, .weekly)
        XCTAssertTrue(reopened.draft.cliProxyAPIAutomaticallyChecksForUpdates)
        XCTAssertTrue(reopened.draft.cliProxyAPIAutomaticallyInstallsUpdates)
        XCTAssertEqual(reopened.draft.cliProxyAPIUpdateCheckSchedule, .monthly)
    }

    func testMakeSaveRequestsMergesAccountsAndUpdatesDesktopChanges() {
        let accounts = [
            self.makeAccount(email: "alpha@example.com", accountId: "acct_alpha"),
            self.makeAccount(email: "beta@example.com", accountId: "acct_beta"),
        ]
        let coordinator = SettingsWindowCoordinator(
            config: self.makeConfig(),
            accounts: accounts
        )

        coordinator.update(\.preferredCodexAppPath, to: "/Applications/Codex.app", field: .preferredCodexAppPath)
        coordinator.selectedPage = .updates
        coordinator.update(\.cliProxyAPIAutomaticallyChecksForUpdates, to: true, field: .cliProxyAPIAutomaticallyChecksForUpdates)

        let requests = coordinator.makeSaveRequests()

        XCTAssertEqual(
            requests.desktop,
            DesktopSettingsUpdate(
                preferredCodexAppPath: "/Applications/Codex.app",
                accountActivationScopeMode: .global,
                accountActivationRootPaths: [],
                codexkitUpdate: .init(
                    automaticallyChecksForUpdates: true,
                    automaticallyInstallsUpdates: false,
                    checkSchedule: .daily
                ),
                cliProxyAPIUpdate: .init(
                    automaticallyChecksForUpdates: true,
                    automaticallyInstallsUpdates: false,
                    checkSchedule: .daily
                )
            )
        )
    }

    func testAccountsPageSaveCanPersistActivationScopeWithoutTouchingOtherPages() throws {
        let accounts = [
            self.makeAccount(email: "alpha@example.com", accountId: "acct_alpha"),
            self.makeAccount(email: "beta@example.com", accountId: "acct_beta"),
        ]
        let sink = TestSettingsSaveSink(config: self.makeConfig())
        let coordinator = SettingsWindowCoordinator(
            config: sink.config,
            accounts: accounts
        )

        coordinator.update(\.accountActivationScopeMode, to: .globalAndSpecificPaths, field: .accountActivationScopeMode)
        coordinator.update(
            \.accountActivationRootPaths,
            to: ["/tmp/project-z", "/tmp/project-y"],
            field: .accountActivationRootPaths
        )

        let requests = try coordinator.save(page: .accounts, using: sink)

        XCTAssertNil(requests.openAIUsage)
        XCTAssertNil(requests.cliProxyAPI)
        XCTAssertEqual(
            requests.desktop,
            DesktopSettingsUpdate(
                preferredCodexAppPath: nil,
                accountActivationScopeMode: .globalAndSpecificPaths,
                accountActivationRootPaths: ["/tmp/project-z", "/tmp/project-y"]
            )
        )
        XCTAssertFalse(coordinator.hasChanges(on: .accounts))
    }

    func testCancelRollsBackAcrossPagesAndDoesNotTriggerRequests() {
        let accounts = [
            self.makeAccount(email: "alpha@example.com", accountId: "acct_alpha"),
            self.makeAccount(email: "beta@example.com", accountId: "acct_beta"),
        ]
        let baseConfig = self.makeConfig()
        let sink = TestSettingsSaveSink(config: baseConfig)
        let coordinator = SettingsWindowCoordinator(
            config: baseConfig,
            accounts: accounts
        )

        coordinator.update(\.manualActivationBehavior, to: .launchNewInstance, field: .manualActivationBehavior)
        coordinator.selectedPage = .usage
        coordinator.update(\.usageDisplayMode, to: .remaining, field: .usageDisplayMode)
        coordinator.update(\.plusRelativeWeight, to: 14, field: .plusRelativeWeight)
        coordinator.update(\.proRelativeToPlusMultiplier, to: 15, field: .proRelativeToPlusMultiplier)
        coordinator.selectedPage = .accounts
        coordinator.update(\.preferredCodexAppPath, to: "/Applications/Codex.app", field: .preferredCodexAppPath)

        coordinator.cancel()

        XCTAssertTrue(sink.appliedRequests.isEmpty)
        XCTAssertEqual(coordinator.draft, SettingsWindowDraft(config: baseConfig, accounts: accounts))

        let reopened = SettingsWindowCoordinator(
            config: sink.config,
            accounts: accounts
        )
        XCTAssertEqual(reopened.draft, SettingsWindowDraft(config: baseConfig, accounts: accounts))
    }

    func testSaveAndCloseClosesWindowAfterSuccessfulSave() {
        let accounts = [
            self.makeAccount(email: "alpha@example.com", accountId: "acct_alpha"),
            self.makeAccount(email: "beta@example.com", accountId: "acct_beta"),
        ]
        let sink = TestSettingsSaveSink(config: self.makeConfig())
        let coordinator = SettingsWindowCoordinator(
            config: sink.config,
            accounts: accounts
        )
        var closeCount = 0

        coordinator.selectedPage = .usage
        coordinator.update(\.usageDisplayMode, to: .remaining, field: .usageDisplayMode)
        coordinator.saveAndClose(using: sink) {
            closeCount += 1
        }

        XCTAssertEqual(closeCount, 1)
        XCTAssertEqual(sink.appliedRequests.count, 1)
    }

    func testRequestPageSelectionDefersNavigationUntilCurrentPageDecision() throws {
        let accounts = [
            self.makeAccount(email: "alpha@example.com", accountId: "acct_alpha"),
            self.makeAccount(email: "beta@example.com", accountId: "acct_beta"),
        ]
        let sink = TestSettingsSaveSink(config: self.makeConfig())
        let coordinator = SettingsWindowCoordinator(
            config: sink.config,
            accounts: accounts
        )

        coordinator.update(\.manualActivationBehavior, to: .launchNewInstance, field: .manualActivationBehavior)
        coordinator.requestPageSelection(.usage)

        XCTAssertEqual(coordinator.selectedPage, .accounts)
        XCTAssertEqual(coordinator.pendingAction, .selectPage(.usage))

        coordinator.confirmPendingActionSave(using: sink) {}

        XCTAssertEqual(coordinator.selectedPage, .usage)
        XCTAssertNil(coordinator.pendingAction)
        XCTAssertEqual(sink.appliedRequests.count, 1)
        XCTAssertEqual(
            sink.appliedRequests[0].openAIAccount,
            OpenAIAccountSettingsUpdate(
                accountOrder: ["acct_alpha", "acct_beta"],
                accountOrderingMode: .quotaSort,
                manualActivationBehavior: .launchNewInstance
            )
        )
    }

    func testRequestCloseDefersClosingUntilDiscardDecision() {
        let accounts = [
            self.makeAccount(email: "alpha@example.com", accountId: "acct_alpha"),
            self.makeAccount(email: "beta@example.com", accountId: "acct_beta"),
        ]
        let coordinator = SettingsWindowCoordinator(
            config: self.makeConfig(),
            accounts: accounts
        )
        var closeCount = 0

        coordinator.selectedPage = .usage
        coordinator.update(\.usageDisplayMode, to: .remaining, field: .usageDisplayMode)

        XCTAssertFalse(coordinator.requestClose())
        XCTAssertEqual(coordinator.pendingAction, .close)

        coordinator.confirmPendingActionDiscard {
            closeCount += 1
        }

        XCTAssertEqual(closeCount, 1)
        XCTAssertNil(coordinator.pendingAction)
        XCTAssertEqual(coordinator.draft.usageDisplayMode, .used)
        XCTAssertFalse(coordinator.hasChanges(on: .usage))
    }

    func testCancelAndCloseDoesNotSaveButClosesWindow() {
        let accounts = [
            self.makeAccount(email: "alpha@example.com", accountId: "acct_alpha"),
            self.makeAccount(email: "beta@example.com", accountId: "acct_beta"),
        ]
        let sink = TestSettingsSaveSink(config: self.makeConfig())
        let coordinator = SettingsWindowCoordinator(
            config: sink.config,
            accounts: accounts
        )
        var closeCount = 0

        coordinator.update(\.usageDisplayMode, to: .remaining, field: .usageDisplayMode)
        coordinator.cancelAndClose {
            closeCount += 1
        }

        XCTAssertEqual(closeCount, 1)
        XCTAssertTrue(sink.appliedRequests.isEmpty)
        XCTAssertEqual(coordinator.draft.usageDisplayMode, .used)
    }

    func testSaveAndCloseKeepsWindowOpenWhenSaveFails() {
        let accounts = [
            self.makeAccount(email: "alpha@example.com", accountId: "acct_alpha"),
            self.makeAccount(email: "beta@example.com", accountId: "acct_beta"),
        ]
        let coordinator = SettingsWindowCoordinator(
            config: self.makeConfig(),
            accounts: accounts
        )
        let sink = FailingSettingsSaveSink()
        var closeCount = 0

        coordinator.selectedPage = .usage
        coordinator.update(\.usageDisplayMode, to: .remaining, field: .usageDisplayMode)
        coordinator.saveAndClose(using: sink) {
            closeCount += 1
        }

        XCTAssertEqual(closeCount, 0)
        XCTAssertEqual(coordinator.validationMessage, "save failed")
    }

    func testReconcileExternalStateRefreshesUntouchedFieldsAndPreservesEditedFields() {
        let initialAccounts = [
            self.makeAccount(email: "alpha@example.com", accountId: "acct_alpha"),
            self.makeAccount(email: "beta@example.com", accountId: "acct_beta"),
        ]
        let coordinator = SettingsWindowCoordinator(
            config: self.makeConfig(),
            accounts: initialAccounts
        )

        coordinator.update(\.manualActivationBehavior, to: .launchNewInstance, field: .manualActivationBehavior)

        var externalConfig = self.makeConfig()
        externalConfig.openAI.accountOrderingMode = .manual
        externalConfig.openAI.usageDisplayMode = .remaining
        externalConfig.openAI.manualActivationBehavior = .updateConfigOnly

        coordinator.reconcileExternalState(
            config: externalConfig,
            accounts: initialAccounts
        )

        XCTAssertEqual(coordinator.draft.accountOrderingMode, .manual)
        XCTAssertEqual(coordinator.draft.manualActivationBehavior, .launchNewInstance)
        XCTAssertEqual(coordinator.draft.usageDisplayMode, .remaining)
    }

    func testReconcileExternalStateKeepsExplicitlyEditedFieldEvenIfValueMatchesOriginalBaseline() {
        let initialAccounts = [
            self.makeAccount(email: "alpha@example.com", accountId: "acct_alpha"),
            self.makeAccount(email: "beta@example.com", accountId: "acct_beta"),
        ]
        let coordinator = SettingsWindowCoordinator(
            config: self.makeConfig(),
            accounts: initialAccounts
        )

        coordinator.update(\.manualActivationBehavior, to: .launchNewInstance, field: .manualActivationBehavior)
        coordinator.update(\.manualActivationBehavior, to: .updateConfigOnly, field: .manualActivationBehavior)

        var externalConfig = self.makeConfig()
        externalConfig.openAI.manualActivationBehavior = .launchNewInstance

        coordinator.reconcileExternalState(
            config: externalConfig,
            accounts: initialAccounts
        )

        XCTAssertEqual(coordinator.draft.manualActivationBehavior, .updateConfigOnly)
        XCTAssertEqual(
            coordinator.makeSaveRequests().openAIAccount,
            OpenAIAccountSettingsUpdate(
                accountOrder: ["acct_alpha", "acct_beta"],
                accountOrderingMode: .quotaSort,
                manualActivationBehavior: .updateConfigOnly
            )
        )
    }

    func testReconcileExternalStateMergesNewAccountsIntoEditedOrder() {
        let initialAccounts = [
            self.makeAccount(email: "alpha@example.com", accountId: "acct_alpha"),
            self.makeAccount(email: "beta@example.com", accountId: "acct_beta"),
        ]
        let coordinator = SettingsWindowCoordinator(
            config: self.makeConfig(),
            accounts: initialAccounts
        )
        coordinator.setAccountOrder(["acct_beta", "acct_alpha"])

        var externalConfig = self.makeConfig()
        externalConfig.setOpenAIAccountOrder(["acct_alpha", "acct_beta", "acct_gamma"])
        let updatedAccounts = initialAccounts + [
            self.makeAccount(email: "gamma@example.com", accountId: "acct_gamma"),
        ]

        coordinator.reconcileExternalState(
            config: externalConfig,
            accounts: updatedAccounts
        )

        XCTAssertEqual(coordinator.draft.accountOrder, ["acct_beta", "acct_alpha", "acct_gamma"])
        XCTAssertEqual(coordinator.orderedAccounts.map(\.id), ["acct_beta", "acct_alpha", "acct_gamma"])
    }

    func testReconcileExternalStateDropsRemovedAccountsFromEditedOrder() {
        let initialAccounts = [
            self.makeAccount(email: "alpha@example.com", accountId: "acct_alpha"),
            self.makeAccount(email: "beta@example.com", accountId: "acct_beta"),
            self.makeAccount(email: "gamma@example.com", accountId: "acct_gamma"),
        ]
        let coordinator = SettingsWindowCoordinator(
            config: self.makeConfig(accountOrder: ["acct_alpha", "acct_beta", "acct_gamma"]),
            accounts: initialAccounts
        )
        coordinator.setAccountOrder(["acct_gamma", "acct_beta", "acct_alpha"])

        let updatedAccounts = [
            self.makeAccount(email: "alpha@example.com", accountId: "acct_alpha"),
            self.makeAccount(email: "gamma@example.com", accountId: "acct_gamma"),
        ]
        let externalConfig = self.makeConfig(accountOrder: ["acct_alpha", "acct_gamma"])

        coordinator.reconcileExternalState(
            config: externalConfig,
            accounts: updatedAccounts
        )

        XCTAssertEqual(coordinator.draft.accountOrder, ["acct_gamma", "acct_alpha"])
        XCTAssertEqual(coordinator.orderedAccounts.map(\.id), ["acct_gamma", "acct_alpha"])
    }

    private func makeConfig(
        accountOrder: [String] = ["acct_alpha", "acct_beta"],
        accountOrderingMode: CodexBarOpenAIAccountOrderingMode = .quotaSort
    ) -> CodexBarConfig {
        let alpha = CodexBarProviderAccount(
            id: "acct_alpha",
            kind: .oauthTokens,
            label: "alpha@example.com",
            email: "alpha@example.com",
            openAIAccountId: "acct_alpha",
            accessToken: "access-alpha",
            refreshToken: "refresh-alpha",
            idToken: "id-alpha"
        )
        let beta = CodexBarProviderAccount(
            id: "acct_beta",
            kind: .oauthTokens,
            label: "beta@example.com",
            email: "beta@example.com",
            openAIAccountId: "acct_beta",
            accessToken: "access-beta",
            refreshToken: "refresh-beta",
            idToken: "id-beta"
        )
        let gamma = CodexBarProviderAccount(
            id: "acct_gamma",
            kind: .oauthTokens,
            label: "gamma@example.com",
            email: "gamma@example.com",
            openAIAccountId: "acct_gamma",
            accessToken: "access-gamma",
            refreshToken: "refresh-gamma",
            idToken: "id-gamma"
        )

        return CodexBarConfig(
            active: CodexBarActiveSelection(
                providerId: "openai-oauth",
                accountId: "acct_alpha"
            ),
            desktop: CodexBarDesktopSettings(
                accountActivationScope: .init(
                    mode: .global,
                    rootPaths: []
                ),
                cliProxyAPI: .init(
                    enabled: false,
                    host: "127.0.0.1",
                    port: 8317,
                    repositoryRootPath: "/tmp/default-CLIProxyAPI",
                    managementSecretKey: "default-secret",
                    memberAccountIDs: []
                )
            ),
            openAI: CodexBarOpenAISettings(
                accountOrder: accountOrder,
                accountOrderingMode: accountOrderingMode,
                manualActivationBehavior: .updateConfigOnly
            ),
            providers: [
                CodexBarProvider(
                    id: "openai-oauth",
                    kind: .openAIOAuth,
                    label: "OpenAI",
                    activeAccountId: "acct_alpha",
                    accounts: [alpha, beta, gamma]
                )
            ]
        )
    }

    private func makeAccount(email: String, accountId: String, planType: String = "plus") -> TokenAccount {
        TokenAccount(
            email: email,
            accountId: accountId,
            accessToken: "access-\(accountId)",
            refreshToken: "refresh-\(accountId)",
            idToken: "id-\(accountId)",
            planType: planType
        )
    }
}

@MainActor
private final class TestSettingsSaveSink: SettingsSaveRequestApplying {
    private(set) var config: CodexBarConfig
    private(set) var appliedRequests: [SettingsSaveRequests] = []

    init(config: CodexBarConfig) {
        self.config = config
    }

    @MainActor
    func applySettingsSaveRequests(_ requests: SettingsSaveRequests) throws {
        self.appliedRequests.append(requests)
        try SettingsSaveRequestApplier.apply(requests, to: &self.config)
    }
}

private struct FailingSettingsSaveSink: SettingsSaveRequestApplying {
    @MainActor
    func applySettingsSaveRequests(_ requests: SettingsSaveRequests) throws {
        throw TestSaveError.failed
    }

    private enum TestSaveError: LocalizedError {
        case failed

        var errorDescription: String? { "save failed" }
    }
}
