import XCTest
@testable import CodexkitApp

final class CodexBarProviderPresentationTests: XCTestCase {
    func testBaseURLBadgeLabelKeepsMeaningfulPathSegments() {
        let provider = CodexBarProvider(
            id: "compatible",
            kind: .openAICompatible,
            label: "Compatible",
            enabled: true,
            baseURL: "https://relay.example.com/proxy/openai/v1",
            activeAccountId: nil,
            accounts: []
        )

        XCTAssertEqual(provider.baseURLBadgeLabel, "relay.example.com/proxy/openai/v1")
    }

    func testBaseURLBadgeLabelOmitsDefaultV1PathNoise() {
        let provider = CodexBarProvider(
            id: "compatible",
            kind: .openAICompatible,
            label: "Compatible",
            enabled: true,
            baseURL: "https://relay.example.com/v1",
            activeAccountId: nil,
            accounts: []
        )

        XCTAssertEqual(provider.baseURLBadgeLabel, "relay.example.com")
    }
}
