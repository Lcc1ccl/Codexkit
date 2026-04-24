import Foundation
import XCTest
@testable import CodexkitApp

@MainActor
final class TokenStoreSettingsTests: CodexBarTestCase {
    func testSaveOpenAIAccountSettingsWritesAccountOrderModeAndManualActivationBehavior() throws {
        let store = TokenStore.shared
        store.load()
        store.addOrUpdate(try self.makeOAuthAccount(accountID: "acct_alpha", email: "alpha@example.com"))
        store.addOrUpdate(try self.makeOAuthAccount(accountID: "acct_beta", email: "beta@example.com"))

        try store.saveOpenAIAccountSettings(
            OpenAIAccountSettingsUpdate(
                accountOrder: ["acct_beta", "acct_alpha"],
                accountOrderingMode: .manual,
                manualActivationBehavior: .launchNewInstance
            )
        )

        XCTAssertEqual(store.config.openAI.accountOrder, ["acct_beta", "acct_alpha"])
        XCTAssertEqual(store.config.openAI.accountOrderingMode, .manual)
        XCTAssertEqual(store.config.openAI.manualActivationBehavior, .launchNewInstance)
    }

    func testSaveOpenAIUsageSettingsOnlyTouchesUsageFields() throws {
        let store = TokenStore.shared
        store.load()
        store.addOrUpdate(try self.makeOAuthAccount(accountID: "acct_alpha", email: "alpha@example.com"))
        try store.saveOpenAIAccountSettings(
            OpenAIAccountSettingsUpdate(
                accountOrder: ["acct_alpha"],
                accountOrderingMode: .manual,
                manualActivationBehavior: .launchNewInstance
            )
        )

        try store.saveOpenAIUsageSettings(
            OpenAIUsageSettingsUpdate(
                usageDisplayMode: .remaining,
                plusRelativeWeight: 6,
                proRelativeToPlusMultiplier: 14,
                teamRelativeToPlusMultiplier: 2
            )
        )

        XCTAssertEqual(store.config.openAI.usageDisplayMode, .remaining)
        XCTAssertEqual(store.config.openAI.quotaSort.plusRelativeWeight, 6)
        XCTAssertEqual(store.config.openAI.quotaSort.proRelativeToPlusMultiplier, 14)
        XCTAssertEqual(store.config.openAI.quotaSort.teamRelativeToPlusMultiplier, 2)
        XCTAssertEqual(store.config.openAI.accountOrder, ["acct_alpha"])
        XCTAssertEqual(store.config.openAI.accountOrderingMode, .manual)
        XCTAssertEqual(store.config.openAI.manualActivationBehavior, .launchNewInstance)
    }

    func testSaveDesktopSettingsOnlyTouchesPreferredPathActivationScopeAndUpdateSettings() throws {
        let store = TokenStore.shared
        store.load()
        try store.saveOpenAIAccountSettings(
            OpenAIAccountSettingsUpdate(
                accountOrder: [],
                accountOrderingMode: .quotaSort,
                manualActivationBehavior: .launchNewInstance
            )
        )

        let validAppURL = try self.makeValidCodexApp(named: "Test/Codex.app")
        try store.saveDesktopSettings(
            DesktopSettingsUpdate(
                preferredCodexAppPath: validAppURL.path,
                accountActivationScopeMode: .specificPaths,
                accountActivationRootPaths: ["/tmp/project-b", "/tmp/project-a", "/tmp/project-b"],
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

        XCTAssertEqual(store.config.desktop.preferredCodexAppPath, validAppURL.path)
        XCTAssertEqual(store.config.desktop.accountActivationScope.mode, .specificPaths)
        XCTAssertEqual(store.config.desktop.accountActivationScope.rootPaths, ["/tmp/project-b", "/tmp/project-a"])
        XCTAssertFalse(store.config.desktop.codexkitUpdate.automaticallyChecksForUpdates)
        XCTAssertTrue(store.config.desktop.codexkitUpdate.automaticallyInstallsUpdates)
        XCTAssertEqual(store.config.desktop.codexkitUpdate.checkSchedule, .weekly)
        XCTAssertTrue(store.config.desktop.cliProxyAPIUpdate.automaticallyChecksForUpdates)
        XCTAssertTrue(store.config.desktop.cliProxyAPIUpdate.automaticallyInstallsUpdates)
        XCTAssertEqual(store.config.desktop.cliProxyAPIUpdate.checkSchedule, .monthly)
        XCTAssertEqual(store.config.openAI.accountOrderingMode, .quotaSort)
        XCTAssertEqual(store.config.openAI.manualActivationBehavior, .launchNewInstance)
    }

    func testRestoreActiveSelectionPersistsPreviousCompatibleProvider() throws {
        let store = TokenStore.shared
        store.load()

        try store.addCustomProvider(
            label: "Provider A",
            baseURL: "https://a.example.com/v1",
            accountLabel: "Alpha",
            apiKey: "sk-provider-a"
        )
        let providerA = try XCTUnwrap(store.activeProvider)
        let accountA = try XCTUnwrap(store.activeProviderAccount)

        try store.addCustomProvider(
            label: "Provider B",
            baseURL: "https://b.example.com/v1",
            accountLabel: "Beta",
            apiKey: "sk-provider-b"
        )
        XCTAssertEqual(store.activeProvider?.label, "Provider B")

        try store.restoreActiveSelection(
            activeProviderID: providerA.id,
            activeAccountID: accountA.id
        )

        XCTAssertEqual(store.activeProvider?.id, providerA.id)
        XCTAssertEqual(store.activeProviderAccount?.id, accountA.id)
    }

    func testAddCustomProviderNamedOpenRouterAvoidsReservedProviderID() throws {
        let store = TokenStore.shared
        store.load()

        try store.addCustomProvider(
            label: "OpenRouter",
            baseURL: "https://relay.example.com/v1",
            accountLabel: "Relay",
            apiKey: "sk-relay"
        )

        XCTAssertEqual(store.activeProvider?.kind, .openAICompatible)
        XCTAssertEqual(store.activeProvider?.id, "openrouter-custom")
    }

    func testOpenRouterManualModelFallbackWorksWithoutCatalog() throws {
        let store = self.makeTokenStore(
            openRouterCatalogService: OpenRouterModelCatalogServiceSpy(
                result: .failure(URLError(.notConnectedToInternet))
            )
        )

        try store.addOpenRouterProvider(accountLabel: "Primary", apiKey: "sk-or-v1-manual")

        XCTAssertNil(store.openRouterProvider?.openRouterEffectiveModelID)
        XCTAssertTrue(store.openRouterProvider?.cachedModelCatalog.isEmpty ?? true)

        try store.updateOpenRouterSelectedModel("google/gemini-2.5-pro")

        XCTAssertEqual(store.openRouterProvider?.selectedModelID, "google/gemini-2.5-pro")
        XCTAssertEqual(store.openRouterProvider?.openRouterEffectiveModelID, "google/gemini-2.5-pro")
        XCTAssertTrue(store.openRouterProvider?.cachedModelCatalog.isEmpty ?? true)

        let reloaded = try CodexBarConfigStore().loadOrMigrate()
        XCTAssertEqual(reloaded.openRouterProvider()?.selectedModelID, "google/gemini-2.5-pro")
    }

    func testOpenRouterPinnedModelsRemainAfterSwitchingCurrentModel() throws {
        let store = self.makeTokenStore(
            openRouterCatalogService: OpenRouterModelCatalogServiceSpy(
                result: .failure(URLError(.notConnectedToInternet))
            )
        )
        let fetchedAt = Date(timeIntervalSince1970: 1_710_000_500)
        let catalog = [
            CodexBarOpenRouterModel(id: "openai/gpt-4.1", name: "GPT-4.1"),
            CodexBarOpenRouterModel(id: "google/gemini-2.5-pro", name: "Gemini 2.5 Pro"),
        ]

        try store.addOpenRouterProvider(
            apiKey: "sk-or-v1-primary",
            selectedModelID: "openai/gpt-4.1",
            pinnedModelIDs: ["openai/gpt-4.1", "google/gemini-2.5-pro"],
            cachedModelCatalog: catalog,
            fetchedAt: fetchedAt
        )

        XCTAssertEqual(store.openRouterProvider?.pinnedModelIDs, ["openai/gpt-4.1", "google/gemini-2.5-pro"])
        XCTAssertEqual(store.openRouterProvider?.openRouterEffectiveModelID, "openai/gpt-4.1")

        try store.updateOpenRouterSelectedModel("google/gemini-2.5-pro")

        XCTAssertEqual(store.openRouterProvider?.openRouterEffectiveModelID, "google/gemini-2.5-pro")
        XCTAssertEqual(store.openRouterProvider?.pinnedModelIDs, ["openai/gpt-4.1", "google/gemini-2.5-pro"])
        XCTAssertEqual(store.openRouterProvider?.cachedModelCatalog.map(\.id), ["openai/gpt-4.1", "google/gemini-2.5-pro"])
    }

    func testRefreshOpenRouterModelCatalogCachesFetchedModels() async throws {
        let fetchedAt = Date(timeIntervalSince1970: 1_710_000_000)
        let catalogService = OpenRouterModelCatalogServiceSpy(
            result: .success(
                OpenRouterModelCatalogSnapshot(
                    models: [
                        CodexBarOpenRouterModel(id: "anthropic/claude-3.7-sonnet", name: "Claude 3.7 Sonnet"),
                        CodexBarOpenRouterModel(id: "openai/gpt-4.1", name: "GPT-4.1"),
                    ],
                    fetchedAt: fetchedAt
                )
            )
        )
        let store = self.makeTokenStore(openRouterCatalogService: catalogService)

        try store.addOpenRouterProvider(accountLabel: "Primary", apiKey: "sk-or-v1-primary")
        try await store.refreshOpenRouterModelCatalog()

        XCTAssertEqual(catalogService.requestedAPIKeys, ["sk-or-v1-primary"])
        XCTAssertEqual(
            store.openRouterProvider?.cachedModelCatalog.map(\.id),
            ["anthropic/claude-3.7-sonnet", "openai/gpt-4.1"]
        )
        XCTAssertEqual(store.openRouterProvider?.modelCatalogFetchedAt, fetchedAt)

        let reloaded = try CodexBarConfigStore().loadOrMigrate()
        XCTAssertEqual(
            reloaded.openRouterProvider()?.cachedModelCatalog.map(\.id),
            ["anthropic/claude-3.7-sonnet", "openai/gpt-4.1"]
        )
        XCTAssertEqual(reloaded.openRouterProvider()?.modelCatalogFetchedAt, fetchedAt)
    }

    func testRefreshOpenRouterCatalogFailurePreservesSelectedModelAndCache() async throws {
        let fetchedAt = Date(timeIntervalSince1970: 1_710_000_100)
        let catalogService = OpenRouterModelCatalogServiceSpy(
            result: .success(
                OpenRouterModelCatalogSnapshot(
                    models: [
                        CodexBarOpenRouterModel(id: "anthropic/claude-3.7-sonnet", name: "Claude 3.7 Sonnet"),
                        CodexBarOpenRouterModel(id: "google/gemini-2.5-pro", name: "Gemini 2.5 Pro"),
                    ],
                    fetchedAt: fetchedAt
                )
            )
        )
        let store = self.makeTokenStore(openRouterCatalogService: catalogService)

        try store.addOpenRouterProvider(accountLabel: "Primary", apiKey: "sk-or-v1-primary")
        try store.updateOpenRouterSelectedModel("anthropic/claude-3.7-sonnet")
        try await store.refreshOpenRouterModelCatalog()

        catalogService.result = .failure(URLError(.notConnectedToInternet))

        do {
            try await store.refreshOpenRouterModelCatalog()
            XCTFail("Expected refresh to fail")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
        }

        XCTAssertEqual(store.openRouterProvider?.openRouterEffectiveModelID, "anthropic/claude-3.7-sonnet")
        XCTAssertEqual(
            store.openRouterProvider?.cachedModelCatalog.map(\.id),
            ["anthropic/claude-3.7-sonnet", "google/gemini-2.5-pro"]
        )
        XCTAssertEqual(store.openRouterProvider?.modelCatalogFetchedAt, fetchedAt)
    }

    private func makeValidCodexApp(named relativePath: String) throws -> URL {
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CODEXBAR_HOME"] ?? NSTemporaryDirectory())
        let appURL = root.appendingPathComponent(relativePath)
        let resourcesURL = appURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        let executableURL = resourcesURL.appendingPathComponent("codex")
        try Data().write(to: executableURL)
        return appURL
    }

    private func makeTokenStore(
        openRouterCatalogService: any OpenRouterModelCatalogFetching
    ) -> TokenStore {
        TokenStore(
            syncService: CodexSyncServiceNoOp(),
            openRouterGatewayService: OpenRouterGatewayControllerStub(),
            openRouterModelCatalogService: openRouterCatalogService,
            codexRunningProcessIDs: { [] }
        )
    }
}

private final class CodexSyncServiceNoOp: CodexSynchronizing {
    func synchronize(config _: CodexBarConfig) throws {}
}

private final class OpenRouterGatewayControllerStub: OpenRouterGatewayControlling {
    func startIfNeeded() {}
    func stop() {}
    func updateState(provider _: CodexBarProvider?, isActiveProvider _: Bool) {}
}

private final class OpenRouterModelCatalogServiceSpy: OpenRouterModelCatalogFetching {
    var result: Result<OpenRouterModelCatalogSnapshot, Error>
    private(set) var requestedAPIKeys: [String] = []

    init(result: Result<OpenRouterModelCatalogSnapshot, Error>) {
        self.result = result
    }

    func fetchCatalog(apiKey: String) async throws -> OpenRouterModelCatalogSnapshot {
        self.requestedAPIKeys.append(apiKey)
        return try self.result.get()
    }
}
