import XCTest
@testable import CodexkitApp

final class OpenAIAccountPresentationTests: XCTestCase {
    private var originalLanguageOverride: Bool?

    override func setUp() {
        super.setUp()
        self.originalLanguageOverride = L.languageOverride
        L.languageOverride = false
    }

    override func tearDown() {
        L.languageOverride = self.originalLanguageOverride
        super.tearDown()
    }

    func testRowStateShowsUseActionWhenAccountIsNotNextUseTarget() {
        let account = self.makeAccount(accountId: "acct_idle", isActive: false)

        let state = OpenAIAccountPresentation.rowState(
            for: account,
            summary: OpenAIRunningThreadAttribution.Summary.empty
        )

        XCTAssertTrue(state.showsUseAction)
        XCTAssertEqual(
            OpenAIAccountPresentation.manualActivationButtonTitle(defaultBehavior: .updateConfigOnly),
            "Use"
        )
        XCTAssertEqual(
            OpenAIAccountPresentation.manualActivationButtonTitle(defaultBehavior: .launchNewInstance),
            "Use"
        )
        XCTAssertNil(state.runningThreadBadgeTitle)
    }

    func testRowStateShowsSelectedNextUseStateWithUseAction() {
        let account = self.makeAccount(accountId: "acct_next", isActive: true)

        let state = OpenAIAccountPresentation.rowState(
            for: account,
            summary: OpenAIRunningThreadAttribution.Summary.empty
        )

        XCTAssertTrue(state.isNextUseTarget)
        XCTAssertFalse(state.showsUseAction)
    }

    func testRowStateShowsRunningThreadBadgeWhenThreadsAreAttributed() {
        let account = self.makeAccount(accountId: "acct_busy", isActive: false)
        let summary = OpenAIRunningThreadAttribution.Summary(
            availability: .available,
            runningThreadCounts: ["acct_busy": 2],
            unknownThreadCount: 0
        )

        let state = OpenAIAccountPresentation.rowState(
            for: account,
            summary: summary
        )

        XCTAssertEqual(state.runningThreadCount, 2)
        XCTAssertEqual(state.runningThreadBadgeTitle, "Running 2")
    }

    func testNextUseAndRunningThreadsCanCoexistOnSameAccount() {
        let account = self.makeAccount(accountId: "acct_dual", isActive: true)
        let summary = OpenAIRunningThreadAttribution.Summary(
            availability: .available,
            runningThreadCounts: ["acct_dual": 2],
            unknownThreadCount: 0
        )

        let state = OpenAIAccountPresentation.rowState(
            for: account,
            summary: summary
        )

        XCTAssertTrue(state.isNextUseTarget)
        XCTAssertEqual(state.runningThreadCount, 2)
        XCTAssertFalse(state.showsUseAction)
        XCTAssertEqual(state.runningThreadBadgeTitle, "Running 2")
    }

    func testRowStateShowsCompactChineseRunningThreadBadge() {
        L.languageOverride = true
        let account = self.makeAccount(accountId: "acct_busy", isActive: false)
        let summary = OpenAIRunningThreadAttribution.Summary(
            availability: .available,
            runningThreadCounts: ["acct_busy": 2],
            unknownThreadCount: 0
        )

        let state = OpenAIAccountPresentation.rowState(
            for: account,
            summary: summary
        )

        XCTAssertEqual(state.runningThreadBadgeTitle, "运行 2")
    }

    func testUnavailableSummaryHidesBadgeAndShowsUnavailableText() {
        let account = self.makeAccount(accountId: "acct_busy", isActive: false)

        let state = OpenAIAccountPresentation.rowState(
            for: account,
            summary: .unavailable
        )
        let summaryText = OpenAIAccountPresentation.runningThreadSummaryText(summary: .unavailable)

        XCTAssertEqual(state.runningThreadCount, 0)
        XCTAssertNil(state.runningThreadBadgeTitle)
        XCTAssertEqual(summaryText, "Running status unavailable")
    }

    func testUnavailableAttributionShowsRuntimeLogInitializationHint() {
        let logsDatabaseName = CodexPaths.logsSQLiteURL.lastPathComponent
        let attribution = OpenAIRunningThreadAttribution(
            threads: [],
            summary: .unavailable,
            recentActivityWindow: 5,
            diagnosticMessage: "runtime database missing table: \(logsDatabaseName).logs",
            unavailableReason: .missingTable(database: logsDatabaseName, table: "logs")
        )

        let summaryText = OpenAIAccountPresentation.runningThreadSummaryText(
            attribution: attribution
        )

        XCTAssertEqual(
            summaryText,
            "Running status unavailable (runtime logs not initialized)"
        )
    }

    func testSummaryTextIncludesUnattributedRunningThreads() {
        let summary = OpenAIRunningThreadAttribution.Summary(
            availability: .available,
            runningThreadCounts: ["acct_busy": 2],
            unknownThreadCount: 1
        )

        let text = OpenAIAccountPresentation.runningThreadSummaryText(summary: summary)

        XCTAssertEqual(text, "Running · 3 threads / 1 account · 1 unattributed thread")
    }

    func testManualActivationContextActionsExposeTwoOverridesAndMarkUpdateConfigDefault() {
        let actions = OpenAIAccountPresentation.manualActivationContextActions(
            defaultBehavior: .updateConfigOnly
        )

        XCTAssertEqual(OpenAIAccountPresentation.primaryManualActivationTrigger, .primaryTap)
        XCTAssertEqual(actions.map(\.behavior), [.updateConfigOnly, .launchNewInstance])
        XCTAssertEqual(
            actions.map(\.trigger),
            [.contextOverride(.updateConfigOnly), .contextOverride(.launchNewInstance)]
        )
        XCTAssertEqual(
            actions.map(\.title),
            ["Default Target Only (This Time)", "Launch New Instance (This Time)"]
        )
        XCTAssertEqual(actions.filter(\.isDefault).map(\.behavior), [.updateConfigOnly])
    }

    func testManualActivationContextActionsMarkLaunchDefault() {
        let actions = OpenAIAccountPresentation.manualActivationContextActions(
            defaultBehavior: .launchNewInstance
        )

        XCTAssertEqual(actions.filter(\.isDefault).map(\.behavior), [.launchNewInstance])
    }

    func testActiveAccountRemainsNextUseTarget() {
        let account = self.makeAccount(accountId: "acct_pool", isActive: true)

        let state = OpenAIAccountPresentation.rowState(
            for: account,
            summary: .empty
        )

        XCTAssertTrue(state.isNextUseTarget)
        XCTAssertFalse(state.showsUseAction)
    }

    func testForceUseActionOverridesAggregateModeForAPIGatingUI() {
        let account = self.makeAccount(accountId: "acct_pool", isActive: true)

        let state = OpenAIAccountPresentation.rowState(
            for: account,
            summary: .empty,
            forceUseAction: true
        )

        XCTAssertFalse(state.isNextUseTarget)
        XCTAssertTrue(state.showsUseAction)
        XCTAssertEqual(state.useActionTitle, "Use")
    }

    func testAPIServiceStopFirstMessageUsesEnglishAndChineseLocalization() {
        XCTAssertEqual(L.menuAPIServiceStopFirstMessage, "Stop the API service first")

        L.languageOverride = true

        XCTAssertEqual(L.menuAPIServiceStopFirstMessage, "请先停止API服务")
    }

    func testAPIServiceSettingsKeyLabelsUseExplicitClientAPIWording() {
        XCTAssertEqual(L.settingsAPIServiceClientAPIKey, "Client API Key")
        XCTAssertEqual(
            L.settingsAPIServiceClientAPIKeyPlaceholder,
            "Enter or generate a client API key"
        )
        XCTAssertEqual(L.menuAPIServiceKeyLabel, "Management Key")

        L.languageOverride = true

        XCTAssertEqual(L.settingsAPIServiceClientAPIKey, "客户端 API Key")
        XCTAssertEqual(L.settingsAPIServiceClientAPIKeyPlaceholder, "输入或生成客户端 API Key")
        XCTAssertEqual(L.menuAPIServiceKeyLabel, "管理密钥")
    }

    func testHeaderAvailabilityBadgeTitleShowsWheneverOpenAIAccountsExist() {
        XCTAssertEqual(
            OpenAIAccountPresentation.headerAvailabilityBadgeTitle(
                availableCount: 2,
                totalCount: 46
            ),
            "2/46"
        )
        XCTAssertNil(
            OpenAIAccountPresentation.headerAvailabilityBadgeTitle(
                availableCount: 0,
                totalCount: 0
            )
        )
    }

    func testManualSwitchBannerExplainsFutureTargetOnlyAndOffersLaunchAction() {
        let result = OpenAIManualSwitchResult(
            action: .updateConfigOnly,
            targetAccountID: "acct-alpha",
            launchedNewInstance: false
        )
        let banner = OpenAIAccountPresentation.manualSwitchBanner(
            result: result,
            targetAccount: self.makeAccount(
                accountId: "acct-alpha",
                email: "alpha@example.com",
                isActive: false
            )
        )

        XCTAssertEqual(banner.title, "Default target updated")
        XCTAssertEqual(
            banner.message,
            "New requests now default to alpha@example.com; running threads are not guaranteed to switch. Launch a new instance if you need it to take effect immediately."
        )
        XCTAssertEqual(banner.actionTitle, "Launch Instance")
        XCTAssertEqual(banner.tone, OpenAIStatusBannerPresentation.Tone.info)
    }

    func testManualSwitchBannerForLaunchDoesNotOfferSecondAction() {
        let result = OpenAIManualSwitchResult(
            action: .launchNewInstance,
            targetAccountID: "acct-alpha",
            launchedNewInstance: true
        )
        let banner = OpenAIAccountPresentation.manualSwitchBanner(
            result: result,
            targetAccount: self.makeAccount(
                accountId: "acct-alpha",
                email: "alpha@example.com",
                isActive: false
            )
        )

        XCTAssertEqual(banner.title, "Default target updated and new instance launched")
        XCTAssertEqual(
            banner.message,
            "The new Codex instance will use alpha@example.com; existing instances stay open, and running threads keep their current target."
        )
        XCTAssertNil(banner.actionTitle)
    }

    func testAPIServiceFallbackBannerWarnsWhenRuntimeIsDegraded() {
        let banner = OpenAIAccountPresentation.apiServiceFallbackBanner(
            serviceability: .apiServiceDegraded,
            hasServiceableFallbackCandidate: true
        )

        XCTAssertEqual(
            banner,
            OpenAIStatusBannerPresentation(
                title: "API Service is degraded",
                message: "CLIProxyAPI is not currently healthy; do not treat it as the source of truth for OAuth pool routing until it recovers.",
                actionTitle: "Open Settings",
                tone: .warning
            )
        )
    }

    func testAPIServiceFallbackBannerOffersDisableActionWhenPoolIsUnserviceableButFallbackExists() {
        let banner = OpenAIAccountPresentation.apiServiceFallbackBanner(
            serviceability: .observedPoolUnserviceable,
            hasServiceableFallbackCandidate: true
        )

        XCTAssertEqual(
            banner,
            OpenAIStatusBannerPresentation(
                title: "API Service pool is unserviceable",
                message: "All selected CPA auth files are disabled or cooling down. You can now disable API Service and fall back to direct OAuth / provider routing.",
                actionTitle: "Disable API Service",
                tone: .warning
            )
        )
    }

    func testAPIServiceFallbackBannerOffersNativeRestoreWhenNoFallbackCandidateExists() {
        let banner = OpenAIAccountPresentation.apiServiceFallbackBanner(
            serviceability: .observedPoolUnserviceable,
            hasServiceableFallbackCandidate: false
        )

        XCTAssertEqual(
            banner,
            OpenAIStatusBannerPresentation(
                title: "API Service pool is unserviceable",
                message: "All selected CPA auth files are disabled or cooling down, and there is no direct OAuth / provider candidate to fall back to automatically. Open settings to perform an explicit recovery.",
                actionTitle: "Restore Native Access",
                tone: .warning
            )
        )
    }

    func testPlanBadgeTitleKeepsTeamLabelForHoveredTeamAccount() {
        let account = self.makeAccount(
            accountId: "acct_team_hover",
            isActive: false,
            planType: "team",
            organizationName: "Acme Team"
        )

        XCTAssertEqual(
            OpenAIAccountPresentation.planBadgeTitle(for: account, isHovered: true),
            "TEAM"
        )
    }

    func testPlanBadgeTitleShowsTeamForNonHoveredTeamAccount() {
        let account = self.makeAccount(
            accountId: "acct_team_idle",
            isActive: false,
            planType: "team",
            organizationName: "Acme Team"
        )

        XCTAssertEqual(
            OpenAIAccountPresentation.planBadgeTitle(for: account, isHovered: false),
            "TEAM"
        )
    }

    func testPlanBadgeTitleIgnoresOrganizationNameForHoveredTeamAccount() {
        let account = self.makeAccount(
            accountId: "acct_team_trimmed",
            isActive: false,
            planType: "team",
            organizationName: "  Acme Team  "
        )

        XCTAssertEqual(
            OpenAIAccountPresentation.planBadgeTitle(for: account, isHovered: true),
            "TEAM"
        )
    }

    func testPlanBadgeTitleFallsBackToTeamForHoveredTeamAccountWithoutOrganizationName() {
        let nilNameAccount = self.makeAccount(
            accountId: "acct_team_nil",
            isActive: false,
            planType: "team",
            organizationName: nil
        )
        let blankNameAccount = self.makeAccount(
            accountId: "acct_team_blank",
            isActive: false,
            planType: "team",
            organizationName: "   "
        )

        XCTAssertEqual(
            OpenAIAccountPresentation.planBadgeTitle(for: nilNameAccount, isHovered: true),
            "TEAM"
        )
        XCTAssertEqual(
            OpenAIAccountPresentation.planBadgeTitle(for: blankNameAccount, isHovered: true),
            "TEAM"
        )
    }

    func testPlanBadgeTitleKeepsOriginalPlanLabelForHoveredNonTeamAccount() {
        let account = self.makeAccount(
            accountId: "acct_plus_hover",
            isActive: false,
            planType: "plus",
            organizationName: "Acme Team"
        )

        XCTAssertEqual(
            OpenAIAccountPresentation.planBadgeTitle(for: account, isHovered: true),
            "PLUS"
        )
    }

    func testExpandedTeamBadgeHoverLayoutStaysDisabledForHoveredTeamWithOrganizationName() {
        let account = self.makeAccount(
            accountId: "acct_team_layout",
            isActive: false,
            planType: "team",
            organizationName: "Acme Team"
        )

        XCTAssertFalse(
            OpenAIAccountPresentation.usesExpandedTeamBadgeHoverLayout(
                for: account,
                isHovered: true
            )
        )
        XCTAssertFalse(
            OpenAIAccountPresentation.usesExpandedTeamBadgeHoverLayout(
                for: account,
                isHovered: false
            )
        )
    }

    func testExpandedTeamBadgeHoverLayoutStaysDisabledWithoutOrganizationName() {
        let account = self.makeAccount(
            accountId: "acct_team_no_name",
            isActive: false,
            planType: "team",
            organizationName: "   "
        )

        XCTAssertFalse(
            OpenAIAccountPresentation.usesExpandedTeamBadgeHoverLayout(
                for: account,
                isHovered: true
            )
        )
    }

    func testExpandedTeamBadgeHoverLayoutStaysDisabledForNonTeamAccount() {
        let account = self.makeAccount(
            accountId: "acct_plus_layout",
            isActive: false,
            planType: "plus",
            organizationName: "Acme Team"
        )

        XCTAssertFalse(
            OpenAIAccountPresentation.usesExpandedTeamBadgeHoverLayout(
                for: account,
                isHovered: true
            )
        )
    }

    func testCopyableAccountGroupEmailReturnsOriginalEmail() {
        XCTAssertEqual(
            OpenAIAccountPresentation.copyableAccountGroupEmail("alpha@example.com"),
            "alpha@example.com"
        )
    }

    func testCopyableAccountGroupEmailTrimsWhitespace() {
        XCTAssertEqual(
            OpenAIAccountPresentation.copyableAccountGroupEmail("  alpha@example.com  "),
            "alpha@example.com"
        )
    }

    func testCopyableAccountGroupEmailRejectsBlankValue() {
        XCTAssertNil(
            OpenAIAccountPresentation.copyableAccountGroupEmail("   ")
        )
    }

    func testCopyActionWritesNormalizedEmailToPasteboard() {
        let pasteboard = PasteboardSpy()

        let copiedEmail = OpenAIAccountGroupEmailCopyAction.perform(
            email: "  alpha@example.com  ",
            pasteboard: pasteboard
        )

        XCTAssertEqual(copiedEmail, "alpha@example.com")
        XCTAssertEqual(pasteboard.clearContentsCallCount, 1)
        XCTAssertEqual(pasteboard.lastString, "alpha@example.com")
        XCTAssertEqual(pasteboard.lastType, .string)
    }

    func testCopyActionSkipsBlankEmail() {
        let pasteboard = PasteboardSpy()

        let copiedEmail = OpenAIAccountGroupEmailCopyAction.perform(
            email: "   ",
            pasteboard: pasteboard
        )

        XCTAssertNil(copiedEmail)
        XCTAssertEqual(pasteboard.clearContentsCallCount, 0)
        XCTAssertNil(pasteboard.lastString)
        XCTAssertNil(pasteboard.lastType)
    }

    func testAccountGroupCopyConfirmationTextShowsCopiedWhenEmailsMatch() {
        XCTAssertEqual(
            OpenAIAccountPresentation.accountGroupCopyConfirmationText(
                groupEmail: "  alpha@example.com ",
                copiedEmail: "alpha@example.com"
            ),
            "Copied"
        )
    }

    func testAccountGroupCopyConfirmationTextUsesChineseCopy() {
        L.languageOverride = true

        XCTAssertEqual(
            OpenAIAccountPresentation.accountGroupCopyConfirmationText(
                groupEmail: "alpha@example.com",
                copiedEmail: "alpha@example.com"
            ),
            "已复制"
        )
    }

    func testAccountGroupCopyConfirmationTextHidesWhenEmailsDoNotMatch() {
        XCTAssertNil(
            OpenAIAccountPresentation.accountGroupCopyConfirmationText(
                groupEmail: "alpha@example.com",
                copiedEmail: "beta@example.com"
            )
        )
    }

    private func makeAccount(
        accountId: String,
        email: String? = nil,
        isActive: Bool,
        planType: String = "free",
        organizationName: String? = nil,
        primaryUsedPercent: Double = 0,
        secondaryUsedPercent: Double = 0
    ) -> TokenAccount {
        TokenAccount(
            email: email ?? "\(accountId)@example.com",
            accountId: accountId,
            accessToken: "access-\(accountId)",
            refreshToken: "refresh-\(accountId)",
            idToken: "id-\(accountId)",
            planType: planType,
            primaryUsedPercent: primaryUsedPercent,
            secondaryUsedPercent: secondaryUsedPercent,
            isActive: isActive,
            organizationName: organizationName
        )
    }
}

private final class PasteboardSpy: StringPasteboardWriting {
    private(set) var clearContentsCallCount = 0
    private(set) var lastString: String?
    private(set) var lastType: NSPasteboard.PasteboardType?

    func clearContents() -> Int {
        self.clearContentsCallCount += 1
        return self.clearContentsCallCount
    }

    func setString(_ string: String, forType dataType: NSPasteboard.PasteboardType) -> Bool {
        self.lastString = string
        self.lastType = dataType
        return true
    }
}
