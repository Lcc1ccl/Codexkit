import AppKit
import SwiftUI
import XCTest
@testable import CodexkitApp

final class MenuBarPopoverSizingTests: XCTestCase {
    private func renderedWidth(
        _ text: String,
        font: NSFont
    ) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return ceil((text as NSString).size(withAttributes: attributes).width)
    }

    private func measuredAccountRowWidth(
        account: TokenAccount,
        rowState: OpenAIAccountRowState
    ) -> CGFloat {
        let hostingView = NSHostingView(
            rootView: AccountRowView(
                account: account,
                rowState: rowState,
                isRefreshing: false,
                usageDisplayMode: .used,
                defaultManualActivationBehavior: .updateConfigOnly,
                showsStandaloneCard: true,
                onActivate: { _ in },
                onRefresh: {},
                onReauth: {},
                onDelete: {}
            )
        )
        return ceil(hostingView.fittingSize.width)
    }

    func testInitialSizeUsesStableWidthAndDefaultHeight() {
        let size = MenuBarPopoverSizing.initialSize(availableHeight: 1200)

        XCTAssertEqual(size.width, MenuBarStatusItemIdentity.popoverContentWidth)
        XCTAssertEqual(size.height, MenuBarPopoverSizing.defaultHeight)
    }

    func testClampedHeightCapsToAvailableHeight() {
        XCTAssertEqual(
            MenuBarPopoverSizing.clampedHeight(desiredHeight: 2000, availableHeight: 1400),
            1400
        )
    }

    func testClampedHeightFallsBackToConfiguredMaximumWhenAvailableHeightIsUnknown() {
        XCTAssertEqual(
            MenuBarPopoverSizing.clampedHeight(desiredHeight: 2000, availableHeight: nil),
            MenuBarPopoverSizing.maximumHeight
        )
    }

    func testClampedHeightRespectsAvailableHeight() {
        XCTAssertEqual(
            MenuBarPopoverSizing.clampedHeight(desiredHeight: 600, availableHeight: 500),
            500
        )
    }

    func testClampedHeightFollowsShortContentHeight() {
        XCTAssertEqual(
            MenuBarPopoverSizing.clampedHeight(desiredHeight: 100, availableHeight: 200),
            100
        )
    }

    func testOpenAIAccountRowWidthBudgetFitsPopoverContentWidth() {
        XCTAssertLessThanOrEqual(
            OpenAIAccountRowLayout.totalRowWidth(windowCount: 2),
            OpenAIAccountRowLayout.popoverRowWidthBudget
        )
    }

    func testOpenAIAccountRowFramesCoverRenderedQuotaStrings() {
        let percentFont = NSFont.systemFont(ofSize: 9, weight: .semibold)
        let countdownFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)

        XCTAssertGreaterThanOrEqual(
            OpenAIAccountRowLayout.primaryPercentWidth,
            self.renderedWidth("100%", font: percentFont)
        )
        XCTAssertGreaterThanOrEqual(
            OpenAIAccountRowLayout.secondaryPercentWidth,
            self.renderedWidth("100%", font: percentFont)
        )
        XCTAssertGreaterThanOrEqual(
            OpenAIAccountRowLayout.primaryCountdownWidth,
            self.renderedWidth("7d23h", font: countdownFont)
        )
        XCTAssertGreaterThanOrEqual(
            OpenAIAccountRowLayout.secondaryCountdownWidth,
            self.renderedWidth("7d23h", font: countdownFont)
        )
    }

    func testOpenAIAccountRowMeasuredWidthFitsPopoverBudget() {
        let now = Date()
        let account = TokenAccount(
            email: "team@example.com",
            accountId: "account-1",
            openAIAccountId: "remote-1",
            accessToken: "access",
            refreshToken: "refresh",
            idToken: "id",
            planType: "team",
            primaryUsedPercent: 100,
            secondaryUsedPercent: 88,
            primaryResetAt: now.addingTimeInterval(5 * 3_600),
            secondaryResetAt: now.addingTimeInterval((7 * 86_400) + (23 * 3_600)),
            primaryLimitWindowSeconds: 5 * 3_600,
            secondaryLimitWindowSeconds: 7 * 86_400,
            lastChecked: now,
            isActive: true,
            isSuspended: false,
            tokenExpired: false
        )
        let rowState = OpenAIAccountRowState(
            isNextUseTarget: true,
            runningThreadCount: 12,
            forceUseAction: false
        )

        let measuredWidth = self.measuredAccountRowWidth(account: account, rowState: rowState)

        XCTAssertLessThanOrEqual(
            measuredWidth,
            OpenAIAccountRowLayout.popoverRowWidthBudget
        )
    }

    func testMenuBarScrollViewDisablesHorizontalElasticity() {
        let scrollView = NSScrollView()

        MenuBarScrollViewConfiguration.apply(to: scrollView, idleScrollerAlpha: 0)

        XCTAssertFalse(scrollView.hasHorizontalScroller)
        XCTAssertEqual(scrollView.horizontalScrollElasticity, .none)
    }
}
