import XCTest
@testable import CodexkitApp

final class MenuBarStatusItemPresentationTests: XCTestCase {
    func testActiveAccountUsesUsageSummary() {
        let account = TokenAccount(
            email: "active@example.com",
            accountId: "acct_active",
            primaryUsedPercent: 67,
            secondaryUsedPercent: 48,
            isActive: true
        )

        let presentation = MenuBarStatusItemPresentation.make(
            accounts: [account],
            activeProvider: nil,
            usageDisplayMode: .used,
            menuBarDisplay: .init(),
            updateAvailable: false
        )

        XCTAssertEqual(presentation.iconName, "terminal.fill")
        XCTAssertEqual(presentation.title, "67%·48%")
        XCTAssertEqual(presentation.emphasis, .primary)
    }

    func testFallbackProviderDoesNotLeakProviderLabelIntoStatusItem() {
        let provider = CodexBarProvider(id: "compatible", kind: .openAICompatible, label: "ProviderLong")

        let presentation = MenuBarStatusItemPresentation.make(
            accounts: [],
            activeProvider: provider,
            usageDisplayMode: .used,
            menuBarDisplay: .init(),
            updateAvailable: false
        )

        XCTAssertEqual(presentation.iconName, "network")
        XCTAssertEqual(presentation.title, "")
        XCTAssertEqual(presentation.emphasis, .primary)
    }

    func testAPIServiceEnabledHidesUsageSummaryInStatusItem() {
        let account = TokenAccount(
            email: "active@example.com",
            accountId: "acct_active",
            primaryUsedPercent: 32,
            secondaryUsedPercent: 11,
            isActive: true
        )

        let presentation = MenuBarStatusItemPresentation.make(
            accounts: [account],
            activeProvider: nil,
            usageDisplayMode: .used,
            menuBarDisplay: .init(
                quotaVisibility: .both,
                apiServiceStatusVisibility: .hidden
            ),
            updateAvailable: false,
            apiServiceEnabled: true
        )

        XCTAssertEqual(presentation.iconName, "terminal.fill")
        XCTAssertEqual(presentation.title, "")
    }

    func testQuotaVisibilityCanHideWeeklyWindow() {
        let account = TokenAccount(
            email: "active@example.com",
            accountId: "acct_active",
            primaryUsedPercent: 67,
            secondaryUsedPercent: 48,
            isActive: true
        )

        let presentation = MenuBarStatusItemPresentation.make(
            accounts: [account],
            activeProvider: nil,
            usageDisplayMode: .used,
            menuBarDisplay: .init(quotaVisibility: .primaryOnly),
            updateAvailable: false
        )

        XCTAssertEqual(presentation.title, "67%")
    }

    func testAllHiddenKeepsExistingIconSeverityLogicUnchanged() {
        let account = TokenAccount(
            email: "active@example.com",
            accountId: "acct_active",
            primaryUsedPercent: 100,
            secondaryUsedPercent: 10,
            isActive: true
        )

        let presentation = MenuBarStatusItemPresentation.make(
            accounts: [account],
            activeProvider: nil,
            usageDisplayMode: .used,
            menuBarDisplay: .init(quotaVisibility: .hidden),
            updateAvailable: false
        )

        XCTAssertEqual(presentation.iconName, "bolt.circle.fill")
        XCTAssertEqual(presentation.title, "")
        XCTAssertEqual(presentation.emphasis, .warning)
    }

    func testAPIServiceVisibleShowsAvailableOverTotalUsingObservedFilesFirst() {
        let accounts = [
            TokenAccount(email: "a@example.com", accountId: "acct_a"),
            TokenAccount(email: "b@example.com", accountId: "acct_b"),
            TokenAccount(email: "c@example.com", accountId: "acct_c"),
        ]
        let now = Date()
        let observed = [
            CLIProxyAPIObservedAuthFile(
                id: "acct_a",
                fileName: "a.json",
                localAccountID: "acct_a",
                remoteAccountID: nil,
                email: nil,
                planType: nil,
                authIndex: nil,
                priority: nil,
                status: nil,
                statusMessage: nil,
                disabled: false,
                unavailable: false,
                nextRetryAfter: nil
            ),
            CLIProxyAPIObservedAuthFile(
                id: "acct_b",
                fileName: "b.json",
                localAccountID: "acct_b",
                remoteAccountID: nil,
                email: nil,
                planType: nil,
                authIndex: nil,
                priority: nil,
                status: "disabled",
                statusMessage: nil,
                disabled: false,
                unavailable: false,
                nextRetryAfter: nil
            ),
        ]

        let presentation = MenuBarStatusItemPresentation.make(
            accounts: accounts,
            activeProvider: nil,
            usageDisplayMode: .used,
            menuBarDisplay: .init(),
            updateAvailable: false,
            apiServiceEnabled: true,
            apiServiceMemberAccountIDs: ["acct_a", "acct_b", "acct_c"],
            observedAuthFiles: observed,
            now: now
        )

        XCTAssertEqual(presentation.title, L.available(2, 3))
    }

    func testAPIServiceVisibleFallsBackToLocalAvailabilityWhenObservationMissing() {
        let accounts = [
            TokenAccount(email: "a@example.com", accountId: "acct_a"),
            TokenAccount(email: "b@example.com", accountId: "acct_b", primaryUsedPercent: 100),
        ]

        let presentation = MenuBarStatusItemPresentation.make(
            accounts: accounts,
            activeProvider: nil,
            usageDisplayMode: .used,
            menuBarDisplay: .init(),
            updateAvailable: false,
            apiServiceEnabled: true,
            apiServiceMemberAccountIDs: ["acct_a", "acct_b"],
            observedAuthFiles: []
        )

        XCTAssertEqual(presentation.title, L.available(1, 2))
    }
}
