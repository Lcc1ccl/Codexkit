import Foundation
import XCTest
@testable import CodexkitApp

@MainActor
final class CLIProxyAPIRuntimeControllerTests: CodexBarTestCase {
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

    func testRefreshHealthPropagatesUsageTimeBuckets() async {
        let originalState = TokenStore.shared.cliProxyAPIState
        defer {
            TokenStore.shared.updateCLIProxyAPIState(originalState)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let controller = CLIProxyAPIRuntimeController(
            service: CLIProxyAPIService(session: session),
            managementService: CLIProxyAPIManagementService(session: session)
        )
        let config = CLIProxyAPIServiceConfig(
            host: "127.0.0.1",
            port: 8413,
            authDirectory: URL(fileURLWithPath: "/tmp/auth"),
            managementSecretKey: "secret",
            enabled: true
        )
        TokenStore.shared.updateCLIProxyAPIState(
            CLIProxyAPIServiceState(
                config: config,
                status: .degraded,
                totalRequests: 1,
                failedRequests: 0,
                totalTokens: 2,
                requestsByDay: ["previous-day": 1],
                requestsByHour: ["previous-hour": 1],
                tokensByDay: ["previous-day": 2],
                tokensByHour: ["previous-hour": 2]
            )
        )

        MockURLProtocol.handler = { request in
            switch request.url?.path {
            case "/healthz":
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(#"{"status":"ok"}"#.utf8))
            case "/v0/management/config":
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(#"{"host":"127.0.0.1","port":8413}"#.utf8))
            case "/v0/management/auth-files":
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(#"{"files":[]}"#.utf8))
            case "/v0/management/usage":
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
                let body = """
                {"usage":{"total_requests":12,"failure_count":3,"total_tokens":144,"requests_by_day":{"2026-05-02":12},"requests_by_hour":{"2026-05-02T19":7},"tokens_by_day":{"2026-05-02":144},"tokens_by_hour":{"2026-05-02T19":90},"apis":{}},"failed_requests":3}
                """.data(using: .utf8)!
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, body)
            case "/v0/management/quota":
                let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
                return (response, Data(#"{"error":"quota unavailable"}"#.utf8))
            default:
                XCTFail("Unexpected request: \(request.url?.absoluteString ?? "nil")")
                throw URLError(.badURL)
            }
        }

        await controller.refreshHealth()

        let state = TokenStore.shared.cliProxyAPIState
        XCTAssertEqual(state.status, .running)
        XCTAssertEqual(state.totalRequests, 12)
        XCTAssertEqual(state.failedRequests, 3)
        XCTAssertEqual(state.totalTokens, 144)
        XCTAssertEqual(state.requestsByDay, ["2026-05-02": 12])
        XCTAssertEqual(state.requestsByHour, ["2026-05-02T19": 7])
        XCTAssertEqual(state.tokensByDay, ["2026-05-02": 144])
        XCTAssertEqual(state.tokensByHour, ["2026-05-02T19": 90])
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
