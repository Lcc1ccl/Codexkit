import Foundation
import XCTest
@testable import CodexkitApp

final class CLIProxyAPIManagementServiceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.handler = nil
    }

    func testListAuthFilesUsesBearerSecretAndDecodesEntries() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let service = CLIProxyAPIManagementService(session: session)
        let config = CLIProxyAPIServiceConfig(
            host: "127.0.0.1",
            port: 8411,
            authDirectory: URL(fileURLWithPath: "/tmp/auth"),
            managementSecretKey: "secret",
            allowRemoteManagement: false,
            enabled: true
        )

        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
            XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:8411/v0/management/auth-files")
            let body = """
            {"files":[{"name":"codex-alpha.json","type":"codex","email":"alpha@example.com","auth_index":"acct-alpha","status":"active","status_message":"ready","disabled":false,"unavailable":true,"priority":7,"codexkit_local_account_id":"local-alpha","next_retry_after":"2026-04-21T04:20:00Z","id_token":{"plan_type":"team","chatgpt_account_id":"acct_openai_alpha"}}]}
            """.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }

        let files = try await service.listAuthFiles(config: config)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].name, "codex-alpha.json")
        XCTAssertEqual(files[0].type, "codex")
        XCTAssertEqual(files[0].email, "alpha@example.com")
        XCTAssertEqual(files[0].authIndex, "acct-alpha")
        XCTAssertEqual(files[0].idToken?.planType, "team")
        XCTAssertEqual(files[0].idToken?.chatGPTAccountID, "acct_openai_alpha")
        XCTAssertEqual(files[0].status, "active")
        XCTAssertEqual(files[0].statusMessage, "ready")
        XCTAssertEqual(files[0].disabled, false)
        XCTAssertEqual(files[0].unavailable, true)
        XCTAssertEqual(files[0].priority, 7)
        XCTAssertEqual(files[0].localAccountID, "local-alpha")
        XCTAssertEqual(files[0].nextRetryAfter, ISO8601DateFormatter().date(from: "2026-04-21T04:20:00Z"))
    }

    func testListModelsUsesBearerSecretAndDecodesEntries() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let service = CLIProxyAPIManagementService(session: session)
        let config = CLIProxyAPIServiceConfig(
            host: "127.0.0.1",
            port: 8411,
            authDirectory: URL(fileURLWithPath: "/tmp/auth"),
            managementSecretKey: "secret",
            allowRemoteManagement: false,
            enabled: true
        )

        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
            XCTAssertTrue(request.url?.absoluteString.contains("/v0/management/auth-files/models?name=codex-alpha.json") == true)
            let body = """
            {"models":[{"id":"gpt-5.4","display_name":"GPT-5.4","type":"chat"}]}
            """.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }

        let models = try await service.listModels(config: config, authFileName: "codex-alpha.json")
        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(models[0].id, "gpt-5.4")
        XCTAssertEqual(models[0].display_name, "GPT-5.4")
    }

    func testGetUsageStatisticsUsesBearerSecretAndDecodesCounts() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let service = CLIProxyAPIManagementService(session: session)
        let config = CLIProxyAPIServiceConfig(
            host: "127.0.0.1",
            port: 8411,
            authDirectory: URL(fileURLWithPath: "/tmp/auth"),
            managementSecretKey: "secret",
            allowRemoteManagement: false,
            enabled: true
        )

        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
            XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:8411/v0/management/usage")
            let body = """
            {"usage":{"total_requests":12,"failure_count":3,"total_tokens":144,"requests_by_day":{"2026-05-02":12},"requests_by_hour":{"2026-05-02T19":7},"tokens_by_day":{"2026-05-02":144},"tokens_by_hour":{"2026-05-02T19":90},"apis":{"openai":{"total_requests":12,"total_tokens":144,"models":{"gpt-5.4":{"total_requests":12,"total_tokens":144,"details":[{"timestamp":"2026-05-02T19:01:02Z","latency_ms":234,"source":"responses","auth_index":"acct-alpha","failed":false,"tokens":{"input_tokens":80,"output_tokens":30,"reasoning_tokens":10,"cached_tokens":4,"total_tokens":120}},{"timestamp":"2026-05-02T19:03:04Z","latency_ms":345,"source":"chat_completions","auth_index":"acct-alpha","failed":true,"tokens":{"input_tokens":20,"output_tokens":3,"reasoning_tokens":1,"cached_tokens":0,"total_tokens":24}}]}}}}},"failed_requests":3}
            """.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }

        let usage = try await service.getUsageStatistics(config: config)
        XCTAssertEqual(usage.usage.total_requests, 12)
        XCTAssertEqual(usage.failed_requests, 3)
        XCTAssertEqual(usage.usage.total_tokens, 144)
        XCTAssertEqual(usage.usage.apis?["openai"]?.models?["gpt-5.4"]?.details?.count, 2)
        XCTAssertEqual(usage.usage.apis?["openai"]?.models?["gpt-5.4"]?.details?.last?.authIndex, "acct-alpha")
        XCTAssertEqual(usage.usage.requests_by_day, ["2026-05-02": 12])
        XCTAssertEqual(usage.usage.requests_by_hour, ["2026-05-02T19": 7])
        XCTAssertEqual(usage.usage.tokens_by_day, ["2026-05-02": 144])
        XCTAssertEqual(usage.usage.tokens_by_hour, ["2026-05-02T19": 90])
        let firstDetail = try XCTUnwrap(usage.usage.apis?["openai"]?.models?["gpt-5.4"]?.details?.first)
        XCTAssertEqual(firstDetail.timestamp, ISO8601DateFormatter().date(from: "2026-05-02T19:01:02Z"))
        XCTAssertEqual(firstDetail.latencyMs, 234)
        XCTAssertEqual(firstDetail.source, "responses")
        XCTAssertEqual(firstDetail.tokens?.inputTokens, 80)
        XCTAssertEqual(firstDetail.tokens?.outputTokens, 30)
        XCTAssertEqual(firstDetail.tokens?.reasoningTokens, 10)
        XCTAssertEqual(firstDetail.tokens?.cachedTokens, 4)
    }

    func testGetLogsUsesBearerSecretAndDecodesLines() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let service = CLIProxyAPIManagementService(session: session)
        let config = CLIProxyAPIServiceConfig(
            host: "127.0.0.1",
            port: 8411,
            authDirectory: URL(fileURLWithPath: "/tmp/auth"),
            managementSecretKey: "secret",
            allowRemoteManagement: false,
            enabled: true
        )

        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
            let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
            XCTAssertEqual(components.path, "/v0/management/logs")
            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            XCTAssertEqual(query["limit"], "120")
            XCTAssertEqual(query["after"], "1710000000")
            let body = """
            {"lines":["first line","second line"],"line-count":2,"latest-timestamp":1710000123}
            """.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }

        let logs = try await service.getLogs(config: config, afterTimestamp: 1_710_000_000, limit: 120)
        XCTAssertEqual(logs.lines, ["first line", "second line"])
        XCTAssertEqual(logs.lineCount, 2)
        XCTAssertEqual(logs.latestTimestamp, 1_710_000_123)
    }

    func testGetLogsSurfacesServerMessage() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let service = CLIProxyAPIManagementService(session: session)
        let config = CLIProxyAPIServiceConfig(
            host: "127.0.0.1",
            port: 8411,
            authDirectory: URL(fileURLWithPath: "/tmp/auth"),
            managementSecretKey: "secret",
            allowRemoteManagement: false,
            enabled: true
        )

        MockURLProtocol.handler = { request in
            let body = #"{"error":"logging to file disabled"}"#.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }

        do {
            _ = try await service.getLogs(config: config, afterTimestamp: nil, limit: 50)
            XCTFail("Expected getLogs to throw")
        } catch {
            XCTAssertEqual(error.localizedDescription, "logging to file disabled")
        }
    }

    func testGetLogsRetriesRetryAfterResponses() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let service = CLIProxyAPIManagementService(session: session, sleep: { _ in })
        let config = CLIProxyAPIServiceConfig(
            host: "127.0.0.1",
            port: 8411,
            authDirectory: URL(fileURLWithPath: "/tmp/auth"),
            managementSecretKey: "secret",
            allowRemoteManagement: false,
            enabled: true
        )
        var attempts = 0

        MockURLProtocol.handler = { request in
            attempts += 1
            if attempts == 1 {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 429,
                    httpVersion: nil,
                    headerFields: ["Retry-After": "0"]
                )!
                return (response, Data(#"{"error":"retry later"}"#.utf8))
            }

            let body = Data(#"{"lines":["after retry"],"line-count":1,"latest-timestamp":1710000123}"#.utf8)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }

        let logs = try await service.getLogs(config: config, afterTimestamp: nil, limit: 10)
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(logs.lines, ["after retry"])
    }

    func testGetQuotaSnapshotRetriesTimeoutTransportError() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let service = CLIProxyAPIManagementService(session: session, sleep: { _ in })
        let config = CLIProxyAPIServiceConfig(
            host: "127.0.0.1",
            port: 8411,
            authDirectory: URL(fileURLWithPath: "/tmp/auth"),
            managementSecretKey: "secret",
            allowRemoteManagement: false,
            enabled: true
        )
        var attempts = 0

        MockURLProtocol.handler = { request in
            attempts += 1
            if attempts == 1 {
                throw URLError(.timedOut)
            }

            let body = """
            {"snapshot_generated_at":"2026-04-21T04:20:00Z","refresh_status":"ok","stale":false,"refresh_interval_seconds":60,"stale_threshold_seconds":120,"accounts":[]}
            """.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }

        let snapshot = try await service.getQuotaSnapshot(config: config)
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(snapshot.refreshStatus, .ok)
        XCTAssertTrue(snapshot.accounts.isEmpty)
    }

    func testGetQuotaSnapshotUsesBearerSecretAndDecodesFreshness() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let service = CLIProxyAPIManagementService(session: session)
        let config = CLIProxyAPIServiceConfig(
            host: "127.0.0.1",
            port: 8411,
            authDirectory: URL(fileURLWithPath: "/tmp/auth"),
            managementSecretKey: "secret",
            allowRemoteManagement: false,
            enabled: true
        )

        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
            XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:8411/v0/management/quota")
            let body = """
            {"snapshot_generated_at":"2026-04-21T04:20:00Z","refresh_status":"ok","stale":false,"refresh_interval_seconds":60,"stale_threshold_seconds":120,"accounts":[{"id":"codex-alpha.json","auth_index":"acct-alpha","name":"codex-alpha.json","provider":"codex","email":"alpha@example.com","priority":7,"chatgpt_account_id":"acct_openai_alpha","codexkit_local_account_id":"local-alpha","plan_type":"team","five_hour_remaining_percent":78,"weekly_remaining_percent":64,"primary_reset_at":"2026-04-21T05:00:00Z","secondary_reset_at":"2026-04-22T00:00:00Z","primary_limit_window_seconds":18000,"secondary_limit_window_seconds":604800,"last_quota_refreshed_at":"2026-04-21T04:20:00Z","quota_refresh_status":"ok","quota_refresh_error":null,"quota_source":"service"}]}
            """.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }

        let snapshot = try await service.getQuotaSnapshot(config: config)
        XCTAssertEqual(snapshot.refreshStatus, .ok)
        XCTAssertFalse(snapshot.stale)
        XCTAssertEqual(snapshot.refreshIntervalSeconds, 60)
        XCTAssertEqual(snapshot.staleThresholdSeconds, 120)
        XCTAssertEqual(snapshot.accounts.count, 1)
        XCTAssertEqual(snapshot.accounts[0].localAccountID, "local-alpha")
        XCTAssertEqual(snapshot.accounts[0].fiveHourRemainingPercent, 78)
    }

    func testGetConfigDecodesCoreRoutingRetryAndQuotaFields() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let service = CLIProxyAPIManagementService(session: session)
        let config = CLIProxyAPIServiceConfig(
            host: "127.0.0.1",
            port: 8411,
            authDirectory: URL(fileURLWithPath: "/tmp/auth"),
            managementSecretKey: "secret",
            allowRemoteManagement: false,
            enabled: true
        )

        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
            XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:8411/v0/management/config")
            let body = """
            {"host":"127.0.0.1","port":8411,"auth-dir":"/tmp/auth","disable-cooling":true,"request-retry":5,"max-retry-interval":45,"remote-management":{"allow-remote":false,"secret-key":"secret"},"quota-exceeded":{"switch-project":false,"switch-preview-model":true},"routing":{"strategy":"fill-first"}}
            """.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }

        let response = try await service.getConfig(config: config)
        let runtimeConfig = service.makeRuntimeConfiguration(response: response, fallback: config)

        XCTAssertEqual(runtimeConfig.host, "127.0.0.1")
        XCTAssertEqual(runtimeConfig.port, 8411)
        XCTAssertEqual(runtimeConfig.authDirectory.path, "/tmp/auth")
        XCTAssertEqual(runtimeConfig.routingStrategy, .fillFirst)
        XCTAssertFalse(runtimeConfig.switchProjectOnQuotaExceeded)
        XCTAssertTrue(runtimeConfig.switchPreviewModelOnQuotaExceeded)
        XCTAssertEqual(runtimeConfig.requestRetry, 5)
        XCTAssertEqual(runtimeConfig.maxRetryInterval, 45)
        XCTAssertTrue(runtimeConfig.disableCooling)
    }

    func testPutRoutingStrategySendsBearerSecretAndValueBody() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let service = CLIProxyAPIManagementService(session: session)
        let config = CLIProxyAPIServiceConfig(
            host: "127.0.0.1",
            port: 8411,
            authDirectory: URL(fileURLWithPath: "/tmp/auth"),
            managementSecretKey: "secret",
            allowRemoteManagement: false,
            enabled: true
        )

        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:8411/v0/management/routing/strategy")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"ok":true}"#.utf8))
        }

        try await service.putRoutingStrategy(config: config, strategy: .fillFirst)
    }

    func testMakeAccountUsageItemsAggregatesPerAuthIndex() {
        let files = [
            CLIProxyAPIManagementListResponse.FileEntry(
                name: "codex-alpha.json",
                type: "codex",
                email: "alpha@example.com",
                authIndex: "acct-alpha",
                account: nil,
                accountType: nil,
                idToken: .init(planType: "team", chatGPTAccountID: "acct_openai_alpha")
            )
        ]
        let usage = CLIProxyAPIManagementUsageResponse(
            usage: .init(
                total_requests: 2,
                success_count: 1,
                failure_count: 1,
                total_tokens: 144,
                apis: [
                    "openai": .init(
                        total_requests: 2,
                        total_tokens: 144,
                        models: [
                            "gpt-5.4": .init(
                                total_requests: 2,
                                total_tokens: 144,
                                details: [
                                    .init(
                                        authIndex: "acct-alpha",
                                        failed: false,
                                        tokens: .init(
                                            inputTokens: 80,
                                            outputTokens: 30,
                                            reasoningTokens: 10,
                                            cachedTokens: 4,
                                            totalTokens: 120
                                        )
                                    ),
                                    .init(
                                        authIndex: "acct-alpha",
                                        failed: true,
                                        tokens: .init(
                                            inputTokens: 20,
                                            outputTokens: 3,
                                            reasoningTokens: 1,
                                            cachedTokens: 0,
                                            totalTokens: 24
                                        )
                                    )
                                ]
                            )
                        ]
                    )
                ]
            ),
            failed_requests: 1
        )
        let localAccounts = [
            TokenAccount(
                email: "alpha@example.com",
                accountId: "acct-alpha",
                openAIAccountId: "acct_openai_alpha",
                accessToken: "access",
                refreshToken: "refresh",
                idToken: "id",
                planType: "team",
                primaryUsedPercent: 0,
                secondaryUsedPercent: 91,
                organizationName: "TEAM"
            )
        ]

        let items = CLIProxyAPIManagementService.makeAccountUsageItems(
            files: files,
            usage: usage,
            localAccounts: localAccounts
        )

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].email, "alpha@example.com")
        XCTAssertEqual(items[0].planType, "team")
        XCTAssertEqual(items[0].successRequests, 1)
        XCTAssertEqual(items[0].failedRequests, 1)
        XCTAssertEqual(items[0].inputTokens, 100)
        XCTAssertEqual(items[0].outputTokens, 33)
        XCTAssertEqual(items[0].reasoningTokens, 11)
        XCTAssertEqual(items[0].cachedTokens, 4)
        XCTAssertEqual(items[0].totalTokens, 144)
        XCTAssertEqual(items[0].fiveHourRemainingPercent, 100)
        XCTAssertEqual(items[0].weeklyRemainingPercent, 9)
    }

    func testMakeAccountUsageItemsPrefersSamePlanWhenMatchingOnlyByEmail() {
        let files = [
            CLIProxyAPIManagementListResponse.FileEntry(
                name: "codex-alpha-team.json",
                type: "codex",
                email: "alpha@example.com",
                authIndex: "acct-alpha-team",
                account: nil,
                accountType: nil,
                idToken: .init(planType: "team", chatGPTAccountID: nil)
            )
        ]
        let localAccounts = [
            TokenAccount(
                email: "alpha@example.com",
                accountId: "acct-plus",
                openAIAccountId: "acct-plus-remote",
                accessToken: "access",
                refreshToken: "refresh",
                idToken: "id",
                planType: "plus",
                primaryUsedPercent: 40,
                secondaryUsedPercent: 35
            ),
            TokenAccount(
                email: "alpha@example.com",
                accountId: "acct-team",
                openAIAccountId: "acct-team-remote",
                accessToken: "access",
                refreshToken: "refresh",
                idToken: "id",
                planType: "team",
                primaryUsedPercent: 10,
                secondaryUsedPercent: 15,
                organizationName: "Alpha Team"
            )
        ]

        let items = CLIProxyAPIManagementService.makeAccountUsageItems(
            files: files,
            usage: nil,
            localAccounts: localAccounts
        )

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].planType, "team")
        XCTAssertEqual(items[0].title, "Alpha Team")
        XCTAssertEqual(items[0].fiveHourRemainingPercent, 90)
    }

    func testMakeObservedAuthFilesPrefersStableLocalMetadataAndRuntimeFields() {
        let files = [
            CLIProxyAPIManagementListResponse.FileEntry(
                name: "codex-alpha-team.json",
                type: "codex",
                email: "alpha@example.com",
                authIndex: "auth-alpha",
                account: nil,
                accountType: nil,
                idToken: .init(planType: "team", chatGPTAccountID: "acct_openai_alpha"),
                status: "cooldown",
                statusMessage: "quota exhausted",
                disabled: false,
                unavailable: true,
                nextRetryAfter: ISO8601DateFormatter().date(from: "2026-04-21T04:30:00Z"),
                priority: 11,
                localAccountID: "local-alpha"
            )
        ]
        let localAccounts = [
            TokenAccount(
                email: "alpha@example.com",
                accountId: "fallback-local-id",
                openAIAccountId: "acct_openai_alpha",
                accessToken: "access",
                refreshToken: "refresh",
                idToken: "id",
                planType: "team"
            )
        ]

        let observed = CLIProxyAPIManagementService.makeObservedAuthFiles(
            files: files,
            localAccounts: localAccounts
        )

        XCTAssertEqual(observed.count, 1)
        XCTAssertEqual(observed[0].id, "auth-alpha")
        XCTAssertEqual(observed[0].fileName, "codex-alpha-team.json")
        XCTAssertEqual(observed[0].localAccountID, "local-alpha")
        XCTAssertEqual(observed[0].remoteAccountID, "acct_openai_alpha")
        XCTAssertEqual(observed[0].priority, 11)
        XCTAssertEqual(observed[0].status, "cooldown")
        XCTAssertEqual(observed[0].statusMessage, "quota exhausted")
        XCTAssertEqual(observed[0].unavailable, true)
        XCTAssertEqual(observed[0].nextRetryAfter, ISO8601DateFormatter().date(from: "2026-04-21T04:30:00Z"))
    }

    func testGroupedMemberAccountsAggregatesSameEmailWithMultipleSubscriptions() {
        let localAccounts = [
            TokenAccount(
                email: "furmanclaude@icloud.com",
                accountId: "team-auth",
                openAIAccountId: "acct-team",
                accessToken: "access",
                refreshToken: "refresh",
                idToken: "id",
                planType: "team",
                organizationName: "Sin Domir"
            ),
            TokenAccount(
                email: "furmanclaude@icloud.com",
                accountId: "plus-auth",
                openAIAccountId: "acct-plus",
                accessToken: "access",
                refreshToken: "refresh",
                idToken: "id",
                planType: "plus"
            )
        ]

        let groups = CLIProxyAPIAccountGrouping.groupedMemberAccounts(
            localAccounts: localAccounts,
            importedUsageItems: []
        )

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].title, "furmanclaude@icloud.com")
        XCTAssertEqual(groups[0].email, "furmanclaude@icloud.com")
        XCTAssertEqual(groups[0].memberItems.map(\.planType), ["team", "plus"])
    }

    func testGroupedMemberAccountsCollapsesSameEmailAndPlanIntoSingleSelectableRow() {
        let localAccounts = [
            TokenAccount(
                email: "furmanclaude@icloud.com",
                accountId: "team-auth-1",
                openAIAccountId: "acct-team-1",
                accessToken: "access",
                refreshToken: "refresh",
                idToken: "id",
                planType: "team",
                organizationName: "Sin Domir"
            ),
            TokenAccount(
                email: "furmanclaude@icloud.com",
                accountId: "team-auth-2",
                openAIAccountId: "acct-team-2",
                accessToken: "access",
                refreshToken: "refresh",
                idToken: "id",
                planType: "team",
                organizationName: "Sin Domir"
            ),
            TokenAccount(
                email: "furmanclaude@icloud.com",
                accountId: "plus-auth",
                openAIAccountId: "acct-plus",
                accessToken: "access",
                refreshToken: "refresh",
                idToken: "id",
                planType: "plus"
            )
        ]

        let groups = CLIProxyAPIAccountGrouping.groupedMemberAccounts(
            localAccounts: localAccounts,
            importedUsageItems: []
        )

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].title, "furmanclaude@icloud.com")
        XCTAssertEqual(groups[0].memberItems.count, 2)
        XCTAssertEqual(groups[0].memberItems.map(\.planType), ["team", "plus"])
        XCTAssertEqual(groups[0].memberItems[0].accountIDs.sorted(), ["team-auth-1", "team-auth-2"])
        XCTAssertEqual(groups[0].memberItems[1].accountIDs, ["plus-auth"])
    }

    func testGroupedUsageItemsCollapsesSameEmailAndPlanAndSumsMetrics() {
        let items = [
            CLIProxyAPIAccountUsageItem(
                id: "team-a",
                title: "Sin Domir",
                email: "furmanclaude@icloud.com",
                planType: "team",
                fiveHourRemainingPercent: 48,
                weeklyRemainingPercent: 66,
                successRequests: 3,
                failedRequests: 1,
                totalTokens: 90
            ),
            CLIProxyAPIAccountUsageItem(
                id: "team-b",
                title: "Sin Domir",
                email: "furmanclaude@icloud.com",
                planType: "team",
                fiveHourRemainingPercent: 46,
                weeklyRemainingPercent: 64,
                successRequests: 2,
                failedRequests: 0,
                inputTokens: 20,
                outputTokens: 5,
                reasoningTokens: 3,
                cachedTokens: 2,
                totalTokens: 30
            ),
            CLIProxyAPIAccountUsageItem(
                id: "plus-a",
                title: "Sin Domir",
                email: "furmanclaude@icloud.com",
                planType: "plus",
                fiveHourRemainingPercent: 80,
                weeklyRemainingPercent: 72,
                successRequests: 1,
                failedRequests: 0,
                inputTokens: 7,
                outputTokens: 2,
                reasoningTokens: 1,
                cachedTokens: 0,
                totalTokens: 10
            )
        ]

        let groups = CLIProxyAPIAccountGrouping.groupedUsageItems(items)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].title, "furmanclaude@icloud.com")
        XCTAssertEqual(groups[0].usageItems.count, 2)
        XCTAssertEqual(groups[0].usageItems.map(\.planType), ["team", "plus"])
        XCTAssertEqual(groups[0].usageItems[0].successRequests, 5)
        XCTAssertEqual(groups[0].usageItems[0].failedRequests, 1)
        XCTAssertEqual(groups[0].usageItems[0].inputTokens, 20)
        XCTAssertEqual(groups[0].usageItems[0].outputTokens, 5)
        XCTAssertEqual(groups[0].usageItems[0].reasoningTokens, 3)
        XCTAssertEqual(groups[0].usageItems[0].cachedTokens, 2)
        XCTAssertEqual(groups[0].usageItems[0].totalTokens, 120)
        XCTAssertEqual(groups[0].usageItems[0].fiveHourRemainingPercent, 46)
        XCTAssertEqual(groups[0].usageItems[0].weeklyRemainingPercent, 64)
    }
}
