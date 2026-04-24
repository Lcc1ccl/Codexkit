import XCTest
@testable import CodexkitApp

final class CodexPathsCLIProxyAPIRuntimePolicyTests: XCTestCase {
    func testCLIProxyAPIRuntimePolicyUsesLegacyWritableRuntimeRoot() {
        let policy = CodexPaths.cliProxyAPIRuntimeRootPolicy

        XCTAssertEqual(policy.authority, .legacyCodexkitHome)
        XCTAssertEqual(policy.liveRootURL, CodexPaths.codexBarRoot.appendingPathComponent("cliproxyapi", isDirectory: true))
        XCTAssertEqual(policy.stagedRootURL, CodexPaths.codexBarRoot.appendingPathComponent("cliproxyapi-staged", isDirectory: true))
        XCTAssertEqual(policy.liveConfigURL, policy.liveRootURL.appendingPathComponent("config.yaml"))
        XCTAssertEqual(policy.stagedConfigURL, policy.stagedRootURL.appendingPathComponent("config.yaml"))
        XCTAssertEqual(policy.liveAuthDirectoryURL, policy.liveRootURL.appendingPathComponent("auth", isDirectory: true))
        XCTAssertEqual(policy.stagedAuthDirectoryURL, policy.stagedRootURL.appendingPathComponent("auth", isDirectory: true))
    }

    func testCLIProxyAPIRuntimePolicyLeavesBundleImmutableByDefault() {
        let policy = CodexPaths.cliProxyAPIRuntimeRootPolicy

        XCTAssertEqual(policy.bundledRuntimeRole, .launchSource)
        XCTAssertFalse(policy.bundledMutableStateAllowed)
    }

    func testCLIProxyAPIRuntimePolicyAliasesStayInSync() {
        let policy = CodexPaths.cliProxyAPIRuntimeRootPolicy

        XCTAssertEqual(CodexPaths.cliProxyAPIRuntimeRootURL, policy.liveRootURL)
        XCTAssertEqual(CodexPaths.cliProxyAPIStagedRuntimeRootURL, policy.stagedRootURL)
        XCTAssertEqual(CodexPaths.cliProxyAPIConfigURL, policy.liveConfigURL)
        XCTAssertEqual(CodexPaths.cliProxyAPIStagedConfigURL, policy.stagedConfigURL)
        XCTAssertEqual(CodexPaths.cliProxyAPIAuthDirectoryURL, policy.liveAuthDirectoryURL)
        XCTAssertEqual(CodexPaths.cliProxyAPIStagedAuthDirectoryURL, policy.stagedAuthDirectoryURL)
    }
}
