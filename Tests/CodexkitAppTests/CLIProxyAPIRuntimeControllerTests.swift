import Foundation
import XCTest
@testable import CodexkitApp

@MainActor
final class CLIProxyAPIRuntimeControllerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.handler = nil
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testShouldRestartProcessWhenMemberSelectionChanges() {
        let applied = CodexBarDesktopSettings.CLIProxyAPISettings(
            enabled: true,
            host: "127.0.0.1",
            port: 8317,
            repositoryRootPath: "/tmp/CLIProxyAPI",
            managementSecretKey: "secret",
            memberAccountIDs: ["acct-a"]
        )
        let next = CodexBarDesktopSettings.CLIProxyAPISettings(
            enabled: true,
            host: "127.0.0.1",
            port: 8317,
            repositoryRootPath: "/tmp/CLIProxyAPI",
            managementSecretKey: "secret",
            memberAccountIDs: ["acct-b"]
        )

        XCTAssertTrue(
            CLIProxyAPIRuntimeController.shouldRestartProcess(
                isRunning: true,
                appliedSettings: applied,
                nextSettings: next
            )
        )
    }

    func testShouldNotRestartProcessWhenRepositoryRootChanges() {
        let applied = CodexBarDesktopSettings.CLIProxyAPISettings(
            enabled: true,
            host: "127.0.0.1",
            port: 8317,
            repositoryRootPath: "/tmp/CLIProxyAPI-a",
            managementSecretKey: "secret",
            memberAccountIDs: ["acct-a"]
        )
        let next = CodexBarDesktopSettings.CLIProxyAPISettings(
            enabled: true,
            host: "127.0.0.1",
            port: 8317,
            repositoryRootPath: "/tmp/CLIProxyAPI-b",
            managementSecretKey: "secret",
            memberAccountIDs: ["acct-a"]
        )

        XCTAssertFalse(
            CLIProxyAPIRuntimeController.shouldRestartProcess(
                isRunning: true,
                appliedSettings: applied,
                nextSettings: next
            )
        )
    }

    func testShouldNotRestartProcessWhenSettingsAreUnchanged() {
        let applied = CodexBarDesktopSettings.CLIProxyAPISettings(
            enabled: true,
            host: "127.0.0.1",
            port: 8317,
            repositoryRootPath: "/tmp/CLIProxyAPI",
            managementSecretKey: "secret",
            clientAPIKey: "client-secret",
            memberAccountIDs: ["acct-a", "acct-b"]
        )

        XCTAssertFalse(
            CLIProxyAPIRuntimeController.shouldRestartProcess(
                isRunning: true,
                appliedSettings: applied,
                nextSettings: applied
            )
        )
    }

    func testShouldRestartProcessWhenClientAPIKeyChanges() {
        let applied = CodexBarDesktopSettings.CLIProxyAPISettings(
            enabled: true,
            host: "127.0.0.1",
            port: 8317,
            repositoryRootPath: "/tmp/CLIProxyAPI",
            managementSecretKey: "secret",
            clientAPIKey: "client-secret-a",
            memberAccountIDs: ["acct-a"]
        )
        let next = CodexBarDesktopSettings.CLIProxyAPISettings(
            enabled: true,
            host: "127.0.0.1",
            port: 8317,
            repositoryRootPath: "/tmp/CLIProxyAPI",
            managementSecretKey: "secret",
            clientAPIKey: "client-secret-b",
            memberAccountIDs: ["acct-a"]
        )

        XCTAssertTrue(
            CLIProxyAPIRuntimeController.shouldRestartProcess(
                isRunning: true,
                appliedSettings: applied,
                nextSettings: next
            )
        )
    }

    func testShouldRestartProcessWhenRestrictFreeAccountsChanges() {
        let applied = CodexBarDesktopSettings.CLIProxyAPISettings(
            enabled: true,
            host: "127.0.0.1",
            port: 8317,
            repositoryRootPath: "/tmp/CLIProxyAPI",
            managementSecretKey: "secret",
            memberAccountIDs: ["acct-plus"],
            restrictFreeAccounts: true
        )
        var next = applied
        next.restrictFreeAccounts = false

        XCTAssertTrue(
            CLIProxyAPIRuntimeController.shouldRestartProcess(
                isRunning: true,
                appliedSettings: applied,
                nextSettings: next
            )
        )
    }

    func testResolvedMemberAccountsExcludeFreeMembersWhenRestrictionEnabled() {
        let plus = TokenAccount(
            email: "plus@example.com",
            accountId: "acct-plus",
            accessToken: "access-plus",
            refreshToken: "refresh-plus",
            idToken: "id-plus",
            planType: "plus"
        )
        let free = TokenAccount(
            email: "free@example.com",
            accountId: "acct-free",
            accessToken: "access-free",
            refreshToken: "refresh-free",
            idToken: "id-free",
            planType: "free"
        )
        let settings = CodexBarDesktopSettings.CLIProxyAPISettings(
            enabled: true,
            host: "127.0.0.1",
            port: 8317,
            repositoryRootPath: nil,
            managementSecretKey: "secret",
            memberAccountIDs: ["acct-plus", "acct-free"],
            restrictFreeAccounts: true
        )

        let resolved = CLIProxyAPIRuntimeController.resolvedMemberAccounts(
            from: [plus, free],
            settings: settings
        )

        XCTAssertEqual(resolved.map(\.accountId), ["acct-plus"])
    }

    func testWaitForHealthyStartupRetriesTransientFailuresUntilHealthy() async {
        let attempts = LockedAttempts()

        let healthy = await CLIProxyAPIRuntimeController.waitForHealthyStartup(
            maxAttempts: 4,
            retryDelayNanoseconds: 1,
            isProcessRunning: { true },
            healthCheck: {
                let current = attempts.increment()
                return current >= 3
            },
            sleep: { _ in }
        )

        XCTAssertTrue(healthy)
        XCTAssertEqual(attempts.value, 3)
    }

    func testWaitForHealthyStartupStopsRetryingWhenProcessExits() async {
        let attempts = LockedAttempts()

        let healthy = await CLIProxyAPIRuntimeController.waitForHealthyStartup(
            maxAttempts: 5,
            retryDelayNanoseconds: 1,
            isProcessRunning: { attempts.value == 0 },
            healthCheck: {
                _ = attempts.increment()
                return false
            },
            sleep: { _ in }
        )

        XCTAssertFalse(healthy)
        XCTAssertEqual(attempts.value, 1)
    }

    func testAdoptRunningServiceIfReusableRequiresHealthAndManagementAuth() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let controller = CLIProxyAPIRuntimeController(
            service: CLIProxyAPIService(session: session),
            managementService: CLIProxyAPIManagementService(session: session)
        )
        let settings = CodexBarDesktopSettings.CLIProxyAPISettings(
            enabled: true,
            host: "127.0.0.1",
            port: 8411,
            repositoryRootPath: nil,
            managementSecretKey: "secret",
            memberAccountIDs: ["acct-a"]
        )
        var requestedPaths: [String] = []

        MockURLProtocol.handler = { request in
            requestedPaths.append(request.url?.path ?? "")
            switch request.url?.path {
            case "/healthz":
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(#"{"status":"ok"}"#.utf8))
            case "/v0/management/config":
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(#"{"host":"127.0.0.1","port":8411}"#.utf8))
            default:
                XCTFail("Unexpected request: \(request.url?.absoluteString ?? "nil")")
                throw URLError(.badURL)
            }
        }

        let reused = await controller.adoptRunningServiceIfReusable(settings)

        XCTAssertTrue(reused)
        XCTAssertEqual(requestedPaths, ["/healthz", "/v0/management/config"])
    }

    func testAdoptRunningServiceIfReusableFailsWhenManagementAuthFails() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let controller = CLIProxyAPIRuntimeController(
            service: CLIProxyAPIService(session: session),
            managementService: CLIProxyAPIManagementService(session: session)
        )
        let settings = CodexBarDesktopSettings.CLIProxyAPISettings(
            enabled: true,
            host: "127.0.0.1",
            port: 8412,
            repositoryRootPath: nil,
            managementSecretKey: "secret",
            memberAccountIDs: ["acct-a"]
        )
        var requestedPaths: [String] = []

        MockURLProtocol.handler = { request in
            requestedPaths.append(request.url?.path ?? "")
            switch request.url?.path {
            case "/healthz":
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(#"{"status":"ok"}"#.utf8))
            case "/v0/management/config":
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
                let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
                return (response, Data(#"{"message":"unauthorized"}"#.utf8))
            default:
                XCTFail("Unexpected request: \(request.url?.absoluteString ?? "nil")")
                throw URLError(.badURL)
            }
        }

        let reused = await controller.adoptRunningServiceIfReusable(settings)

        XCTAssertFalse(reused)
        XCTAssertEqual(requestedPaths, ["/healthz", "/v0/management/config"])
    }

    func testRuntimeStateDisablesStartWhileProcessIsAlreadyLive() {
        let state = CLIProxyAPIServiceState(
            config: CLIProxyAPIServiceConfig(
                authDirectory: CLIProxyAPIService.authDirectoryURL,
                managementSecretKey: "secret"
            ),
            status: .failed,
            pid: 4242
        )

        XCTAssertFalse(state.canStartRuntimeFromSettings(hasSelectedMembers: true))
        XCTAssertTrue(state.canStopRuntimeFromSettings)
    }
}

private final class LockedAttempts: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    func increment() -> Int {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.storage += 1
        return self.storage
    }

    var value: Int {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.storage
    }
}
