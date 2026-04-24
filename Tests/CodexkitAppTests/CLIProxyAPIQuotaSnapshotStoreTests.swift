import Foundation
import XCTest
@testable import CodexkitApp

final class CLIProxyAPIQuotaSnapshotStoreTests: CodexBarTestCase {
    func testSaveAndLoadRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let store = CLIProxyAPIQuotaSnapshotStore(url: url)
        let snapshot = CLIProxyAPIQuotaSnapshot(
            snapshotGeneratedAt: Date(timeIntervalSince1970: 1_700_000_000),
            refreshStatus: .ok,
            stale: false,
            refreshIntervalSeconds: 60,
            staleThresholdSeconds: 120,
            accounts: [
                CLIProxyAPIQuotaAccountItem(
                    id: "acct-alpha",
                    authIndex: "auth-alpha",
                    name: "Alpha",
                    provider: "codex",
                    email: "alpha@example.com",
                    priority: 1,
                    chatGPTAccountID: "acct-alpha",
                    localAccountID: "local-alpha",
                    planType: "team",
                    fiveHourRemainingPercent: 88,
                    weeklyRemainingPercent: 64,
                    primaryResetAt: Date(timeIntervalSince1970: 1_700_000_600),
                    secondaryResetAt: Date(timeIntervalSince1970: 1_700_086_400),
                    primaryLimitWindowSeconds: 18_000,
                    secondaryLimitWindowSeconds: 604_800,
                    lastQuotaRefreshedAt: Date(timeIntervalSince1970: 1_700_000_060),
                    refreshStatus: .ok,
                    refreshError: nil,
                    source: "service"
                )
            ]
        )

        store.save(snapshot)

        XCTAssertEqual(store.load(), snapshot)
    }
}
