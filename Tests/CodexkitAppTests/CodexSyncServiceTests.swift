import Foundation
import XCTest
@testable import CodexkitApp

final class CodexSyncServiceTests: CodexBarTestCase {
    func testRestoreNativeConfigurationStillUsesBakCodexkitLast() throws {
        try CodexPaths.ensureDirectories()

        let backupAuth = Data(#"{"auth_mode":"chatgpt","tokens":{"account_id":"backup"}}"#.utf8)
        let backupToml = Data("model = \"gpt-5.4\"\ncustom = true\n".utf8)
        try CodexPaths.writeSecureFile(backupAuth, to: CodexPaths.authBackupURL)
        try CodexPaths.writeSecureFile(backupToml, to: CodexPaths.configBackupURL)
        try CodexPaths.writeSecureFile(Data(#"{"auth_mode":"chatgpt","tokens":{"account_id":"current"}}"#.utf8), to: CodexPaths.authURL)
        try CodexPaths.writeSecureFile(Data("openai_base_url = \"http://127.0.0.1:9317/v1\"\n".utf8), to: CodexPaths.configTomlURL)

        let result = try CodexSyncService().restoreNativeConfiguration()

        XCTAssertEqual(result.auth, .restoredFromBackup)
        XCTAssertEqual(result.config, .restoredFromBackup)
        XCTAssertEqual(try Data(contentsOf: CodexPaths.authURL), backupAuth)
        XCTAssertEqual(try Data(contentsOf: CodexPaths.configTomlURL), backupToml)
    }

    func testRestoreNativeConfigurationRemovesInjectedStateWhenBackupsMissing() throws {
        try CodexPaths.ensureDirectories()

        try CodexPaths.writeSecureFile(
            Data(#"{"codexkit_managed":true,"auth_mode":"chatgpt","tokens":{"account_id":"current"}}"#.utf8),
            to: CodexPaths.authURL
        )
        try CodexPaths.writeSecureFile(
            Data(
                """
                model_provider = "custom"
                model = "gpt-5.4"
                review_model = "gpt-5.4"
                model_reasoning_effort = "high"
                custom_keep = "yes"
                
                [model_providers.custom]
                name = "CLIProxyAPI"
                wire_api = "openai"
                base_url = "http://127.0.0.1:9317/v1"
                requires_openai_auth = true
                """.utf8
            ),
            to: CodexPaths.configTomlURL
        )

        let result = try CodexSyncService().restoreNativeConfiguration()
        let restoredToml = try String(contentsOf: CodexPaths.configTomlURL, encoding: .utf8)

        XCTAssertEqual(result.auth, .removedInjectedState)
        XCTAssertEqual(result.config, .removedInjectedState)
        XCTAssertFalse(FileManager.default.fileExists(atPath: CodexPaths.authURL.path))
        XCTAssertFalse(restoredToml.contains("model_provider"))
        XCTAssertFalse(restoredToml.contains("[model_providers.custom]"))
        XCTAssertFalse(restoredToml.contains("requires_openai_auth"))
        XCTAssertFalse(restoredToml.contains("model_reasoning_effort"))
        XCTAssertTrue(restoredToml.contains(#"custom_keep = "yes""#))
    }

    func testRestoreNativeConfigurationWithoutBackupDoesNotDeleteUnmanagedAuthJSON() throws {
        try CodexPaths.writeSecureFile(
            Data(#"{"auth_mode":"chatgpt","tokens":{"account_id":"native"}}"#.utf8),
            to: CodexPaths.authURL
        )

        let result = try CodexSyncService().restoreNativeConfiguration()

        XCTAssertEqual(result.auth, .unchanged)
        XCTAssertTrue(FileManager.default.fileExists(atPath: CodexPaths.authURL.path))
    }

    func testSynchronizeRestoresPreviousFilesWhenConfigWriteFails() throws {
        try CodexPaths.ensureDirectories()

        let originalAuth = Data(#"{"auth_mode":"chatgpt","tokens":{"account_id":"old"}}"#.utf8)
        let originalToml = Data("model = \"gpt-5.4-mini\"\n".utf8)
        try CodexPaths.writeSecureFile(originalAuth, to: CodexPaths.authURL)
        try CodexPaths.writeSecureFile(originalToml, to: CodexPaths.configTomlURL)

        let account = CodexBarProviderAccount(
            id: "acct_new",
            kind: .oauthTokens,
            label: "new@example.com",
            email: "new@example.com",
            openAIAccountId: "acct_new",
            accessToken: "access-new",
            refreshToken: "refresh-new",
            idToken: "id-new"
        )
        let provider = CodexBarProvider(
            id: "openai-oauth",
            kind: .openAIOAuth,
            label: "OpenAI",
            activeAccountId: account.id,
            accounts: [account]
        )
        let config = CodexBarConfig(
            global: CodexBarGlobalSettings(serviceTier: .fast),
            active: CodexBarActiveSelection(providerId: provider.id, accountId: account.id),
            providers: [provider]
        )

        var configWriteAttempts = 0
        let service = CodexSyncService(
            writeSecureFile: { data, url in
                if url == CodexPaths.configTomlURL {
                    configWriteAttempts += 1
                    if configWriteAttempts == 1 {
                        throw SyncFailure.configWriteFailed
                    }
                }
                try CodexPaths.writeSecureFile(data, to: url)
            }
        )

        XCTAssertThrowsError(try service.synchronize(config: config)) { error in
            XCTAssertEqual(error as? SyncFailure, .configWriteFailed)
        }

        XCTAssertEqual(try Data(contentsOf: CodexPaths.authURL), originalAuth)
        XCTAssertEqual(try Data(contentsOf: CodexPaths.configTomlURL), originalToml)
    }

    func testSynchronizeAPIServiceWritesCodexkitManagedCustomBlock() throws {
        try CodexPaths.ensureDirectories()
        try CodexPaths.writeSecureFile(
            Data(
                """
                service_tier = "fast"
                preferred_auth_method = "chatgpt"
                custom_keep = "yes"
                model = "gpt-5.4-mini"
                """.utf8
            ),
            to: CodexPaths.configTomlURL
        )

        let account = self.makeOAuthAccount(id: "acct_pool")
        let provider = self.makeOAuthProvider(account: account)
        let config = CodexBarConfig(
            global: CodexBarGlobalSettings(serviceTier: .fast),
            active: CodexBarActiveSelection(providerId: provider.id, accountId: account.id),
            desktop: CodexBarDesktopSettings(
                cliProxyAPI: .init(
                    enabled: true,
                    host: "127.0.0.1",
                    port: 9317,
                    repositoryRootPath: "/tmp/CLIProxyAPI",
                    managementSecretKey: "secret",
                    clientAPIKey: "client-key",
                    memberAccountIDs: [account.id]
                )
            ),
            providers: [provider]
        )

        try CodexSyncService().synchronize(config: config)

        let authObject = try self.readAuthJSON()
        let tomlText = try String(contentsOf: CodexPaths.configTomlURL, encoding: .utf8)

        XCTAssertEqual(authObject["OPENAI_API_KEY"] as? String, "client-key")
        XCTAssertEqual(authObject["auth_mode"] as? String, "apikey")
        XCTAssertNil(authObject["tokens"])
        XCTAssertTrue(tomlText.contains(#"model_provider = "custom""#))
        XCTAssertTrue(tomlText.contains("[model_providers.custom]"))
        XCTAssertTrue(tomlText.contains(#"name = "codexkit""#))
        XCTAssertTrue(tomlText.contains(#"wire_api = "responses""#))
        XCTAssertTrue(tomlText.contains(#"base_url = "http://127.0.0.1:9317/v1""#))
        XCTAssertTrue(tomlText.contains("requires_openai_auth = true"))
        XCTAssertFalse(tomlText.contains("openai_base_url"))
        XCTAssertTrue(tomlText.contains(#"service_tier = "fast""#))
        XCTAssertTrue(tomlText.contains(#"custom_keep = "yes""#))
        XCTAssertFalse(tomlText.contains("preferred_auth_method"))
        self.assertManagedModelFieldsAbsent(in: tomlText)
    }

    func testSynchronizeHandlesMixedRestoreAndRewriteAcrossScopedTargets() throws {
        let rootA = try self.makeScopedRoot()
        let rootB = try self.makeScopedRoot()
        let targetA = self.scopedURLs(for: rootA)
        let targetB = self.scopedURLs(for: rootB)

        let matchingAuth = Data(
            #"""
            {
              "auth_mode":"chatgpt",
              "tokens":{
                "access_token":"access-restore",
                "refresh_token":"refresh-restore",
                "id_token":"id-restore",
                "account_id":"acct_scope_direct"
              }
            }
            """#.utf8
        )
        let matchingConfig = Data("custom_keep = \"restore\"\n".utf8)
        try CodexPaths.writeSecureFile(matchingAuth, to: targetA.authPreAPIBackupURL)
        try CodexPaths.writeSecureFile(matchingConfig, to: targetA.configPreAPIBackupURL)
        try CodexPaths.writeSecureFile(self.makeOAuthSnapshotAuthData(accountID: "acct_other"), to: targetB.authPreAPIBackupURL)
        try CodexPaths.writeSecureFile(Data("custom_keep = \"other\"\n".utf8), to: targetB.configPreAPIBackupURL)

        for target in [targetA, targetB] {
            try CodexPaths.writeSecureFile(Data(#"{"OPENAI_API_KEY":"client-key","auth_mode":"apikey"}"#.utf8), to: target.authURL)
            try CodexPaths.writeSecureFile(
                Data(
                    """
                    model_provider = "custom"
                    custom_keep = "yes"

                    [model_providers.custom]
                    name = "codexkit"
                    wire_api = "responses"
                    base_url = "http://127.0.0.1:9317/v1"
                    requires_openai_auth = true
                    """.utf8
                ),
                to: target.configTomlURL
            )
        }

        let account = self.makeOAuthAccount(id: "acct_scope_direct")
        let provider = self.makeOAuthProvider(account: account)
        let config = CodexBarConfig(
            active: CodexBarActiveSelection(providerId: provider.id, accountId: account.id),
            desktop: CodexBarDesktopSettings(
                accountActivationScope: .init(mode: .specificPaths, rootPaths: [rootA.path, rootB.path])
            ),
            providers: [provider]
        )

        try CodexSyncService().synchronize(config: config, intent: .disableAPIServiceAndSwitch)

        XCTAssertEqual(try Data(contentsOf: targetA.authURL), matchingAuth)
        XCTAssertEqual(try Data(contentsOf: targetA.configTomlURL), matchingConfig)

        let rewrittenAuth = try self.readJSONObject(at: targetB.authURL)
        let rewrittenTokens = try XCTUnwrap(rewrittenAuth["tokens"] as? [String: Any])
        let rewrittenToml = try String(contentsOf: targetB.configTomlURL, encoding: .utf8)
        XCTAssertEqual(rewrittenTokens["account_id"] as? String, "acct_scope_direct")
        XCTAssertFalse(rewrittenToml.contains("model_provider"))
        XCTAssertFalse(rewrittenToml.contains("[model_providers.custom]"))
        XCTAssertTrue(rewrittenToml.contains(#"custom_keep = "yes""#))
        self.assertManagedModelFieldsAbsent(in: rewrittenToml)
    }

    func testSynchronizeRestoresPreAPISnapshotWhenBackupMatchesTarget() throws {
        try CodexPaths.ensureDirectories()
        let preAPIAuth = Data(
            #"""
            {
              "auth_mode":"chatgpt",
              "tokens":{
                "access_token":"access-restore",
                "refresh_token":"refresh-restore",
                "id_token":"id-restore",
                "account_id":"acct_restore"
              }
            }
            """#.utf8
        )
        let preAPIConfig = Data("custom_keep = \"restore\"\n".utf8)
        try CodexPaths.writeSecureFile(preAPIAuth, to: CodexPaths.authPreAPIBackupURL)
        try CodexPaths.writeSecureFile(preAPIConfig, to: CodexPaths.configPreAPIBackupURL)
        try CodexPaths.writeSecureFile(Data(#"{"OPENAI_API_KEY":"client-key","auth_mode":"apikey"}"#.utf8), to: CodexPaths.authURL)
        try CodexPaths.writeSecureFile(Data(#"openai_base_url = "http://127.0.0.1:9317/v1""#.utf8), to: CodexPaths.configTomlURL)

        let account = self.makeOAuthAccount(id: "acct_restore")
        let provider = self.makeOAuthProvider(account: account)

        try CodexSyncService().synchronize(
            config: CodexBarConfig(
                active: .init(providerId: provider.id, accountId: account.id),
                providers: [provider]
            ),
            intent: .disableAPIServiceAndSwitch
        )

        XCTAssertEqual(try Data(contentsOf: CodexPaths.authURL), preAPIAuth)
        XCTAssertEqual(try Data(contentsOf: CodexPaths.configTomlURL), preAPIConfig)
    }

    func testSynchronizeRewritesDirectWhenBackupMismatchesTarget() throws {
        try CodexPaths.ensureDirectories()
        try CodexPaths.writeSecureFile(
            Data(
                #"""
                {
                  "auth_mode":"chatgpt",
                  "tokens":{
                    "access_token":"access-other",
                    "refresh_token":"refresh-other",
                    "id_token":"id-other",
                    "account_id":"acct_other"
                  }
                }
                """#.utf8
            ),
            to: CodexPaths.authPreAPIBackupURL
        )
        try CodexPaths.writeSecureFile(Data("custom_keep = \"old\"\n".utf8), to: CodexPaths.configPreAPIBackupURL)
        try CodexPaths.writeSecureFile(Data(#"{"OPENAI_API_KEY":"client-key","auth_mode":"apikey"}"#.utf8), to: CodexPaths.authURL)
        try CodexPaths.writeSecureFile(
            Data(
                """
                model_provider = "custom"
                custom_keep = "yes"

                [model_providers.custom]
                name = "codexkit"
                wire_api = "responses"
                base_url = "http://127.0.0.1:9317/v1"
                requires_openai_auth = true
                """.utf8
            ),
            to: CodexPaths.configTomlURL
        )

        let account = self.makeOAuthAccount(id: "acct_rewrite")
        let provider = self.makeOAuthProvider(account: account)

        try CodexSyncService().synchronize(
            config: CodexBarConfig(
                active: .init(providerId: provider.id, accountId: account.id),
                providers: [provider]
            ),
            intent: .disableAPIServiceAndSwitch
        )

        let authObject = try self.readAuthJSON()
        let tokens = try XCTUnwrap(authObject["tokens"] as? [String: Any])
        let toml = try String(contentsOf: CodexPaths.configTomlURL, encoding: .utf8)
        XCTAssertEqual(tokens["account_id"] as? String, "acct_rewrite")
        XCTAssertEqual(tokens["access_token"] as? String, "access-acct_rewrite")
        XCTAssertFalse(toml.contains("model_provider"))
        XCTAssertFalse(toml.contains("[model_providers.custom]"))
        XCTAssertTrue(toml.contains(#"custom_keep = "yes""#))
        self.assertManagedModelFieldsAbsent(in: toml)
    }

    func testSynchronizeRefreshesPreAPISnapshotOnlyAfterAllTargetsSucceed() throws {
        let rootA = try self.makeScopedRoot()
        let rootB = try self.makeScopedRoot()
        let targetA = self.scopedURLs(for: rootA)
        let targetB = self.scopedURLs(for: rootB)
        let directAuthA = Data(#"{"auth_mode":"chatgpt","tokens":{"account_id":"acct_pre_api"}}"#.utf8)
        let directAuthB = Data(#"{"auth_mode":"chatgpt","tokens":{"account_id":"acct_pre_api"},"custom":"b"}"#.utf8)
        let directConfigA = Data("custom_keep = \"yes-a\"\n".utf8)
        let directConfigB = Data("custom_keep = \"yes-b\"\n".utf8)

        try CodexPaths.writeSecureFile(directAuthA, to: targetA.authURL)
        try CodexPaths.writeSecureFile(directAuthB, to: targetB.authURL)
        try CodexPaths.writeSecureFile(directConfigA, to: targetA.configTomlURL)
        try CodexPaths.writeSecureFile(directConfigB, to: targetB.configTomlURL)
        try CodexPaths.writeSecureFile(Data("old-pre-api-auth-a".utf8), to: targetA.authPreAPIBackupURL)
        try CodexPaths.writeSecureFile(Data("old-pre-api-config-a".utf8), to: targetA.configPreAPIBackupURL)
        try CodexPaths.writeSecureFile(Data("old-pre-api-auth-b".utf8), to: targetB.authPreAPIBackupURL)
        try CodexPaths.writeSecureFile(Data("old-pre-api-config-b".utf8), to: targetB.configPreAPIBackupURL)

        let account = self.makeOAuthAccount(id: "acct_pre_api")
        let provider = self.makeOAuthProvider(account: account)
        let config = CodexBarConfig(
            active: .init(providerId: provider.id, accountId: account.id),
            desktop: CodexBarDesktopSettings(
                accountActivationScope: .init(mode: .specificPaths, rootPaths: [rootA.path, rootB.path]),
                cliProxyAPI: .init(
                    enabled: true,
                    host: "127.0.0.1",
                    port: 9317,
                    repositoryRootPath: nil,
                    managementSecretKey: "management-secret",
                    clientAPIKey: "client-key",
                    memberAccountIDs: [account.id]
                )
            ),
            providers: [provider]
        )

        try CodexSyncService().synchronize(config: config, intent: .enableAPIService)

        XCTAssertEqual(try Data(contentsOf: targetA.authPreAPIBackupURL), directAuthA)
        XCTAssertEqual(try Data(contentsOf: targetA.configPreAPIBackupURL), directConfigA)
        XCTAssertEqual(try Data(contentsOf: targetB.authPreAPIBackupURL), directAuthB)
        XCTAssertEqual(try Data(contentsOf: targetB.configPreAPIBackupURL), directConfigB)
    }

    func testSynchronizeDoesNotWriteModelFieldsInAnyMode() throws {
        try CodexPaths.ensureDirectories()

        let oauthAccount = self.makeOAuthAccount(id: "acct_no_model_fields")
        let oauthProvider = self.makeOAuthProvider(account: oauthAccount)
        let compatibleAccount = CodexBarProviderAccount(
            id: "acct-compatible-no-model",
            kind: .apiKey,
            label: "Compatible",
            apiKey: "sk-compatible-no-model"
        )
        let compatibleProvider = CodexBarProvider(
            id: "compatible-no-model",
            kind: .openAICompatible,
            label: "Compatible",
            enabled: true,
            baseURL: "https://compatible.example.com/v1",
            activeAccountId: compatibleAccount.id,
            accounts: [compatibleAccount]
        )

        let cases: [(String, CodexBarConfig, CodexSyncIntent)] = [
            (
                "official",
                CodexBarConfig(
                    active: .init(providerId: oauthProvider.id, accountId: oauthAccount.id),
                    providers: [oauthProvider]
                ),
                .directSwitch
            ),
            (
                "custom",
                CodexBarConfig(
                    active: .init(providerId: compatibleProvider.id, accountId: compatibleAccount.id),
                    providers: [compatibleProvider]
                ),
                .directSwitch
            ),
            (
                "api-service",
                CodexBarConfig(
                    active: .init(providerId: oauthProvider.id, accountId: oauthAccount.id),
                    desktop: CodexBarDesktopSettings(
                        cliProxyAPI: .init(
                            enabled: true,
                            host: "127.0.0.1",
                            port: 9317,
                            managementSecretKey: "secret",
                            clientAPIKey: "client-key",
                            memberAccountIDs: [oauthAccount.id]
                        )
                    ),
                    providers: [oauthProvider]
                ),
                .enableAPIService
            ),
        ]

        for (label, config, intent) in cases {
            try CodexPaths.writeSecureFile(Data("custom_keep = \"\(label)\"\n".utf8), to: CodexPaths.configTomlURL)
            try CodexSyncService().synchronize(config: config, intent: intent)
            let toml = try String(contentsOf: CodexPaths.configTomlURL, encoding: .utf8)
            self.assertManagedModelFieldsAbsent(in: toml, label: label)
        }
    }

    func testSynchronizeCleansLegacyAllowlistWithoutTouchingUnmanagedProviderBlocks() throws {
        try CodexPaths.ensureDirectories()
        try CodexPaths.writeSecureFile(
            Data(
                """
                model_provider = "custom"
                openai_base_url = "https://legacy.example.com/v1"
                model = "gpt-5.4"
                review_model = "gpt-5.4"
                model_reasoning_effort = "high"
                oss_provider = "legacy"
                model_catalog_json = "[]"
                preferred_auth_method = "chatgpt"
                custom_keep = "yes"
                # preserve me

                [model_providers.custom]
                name = "CLIProxyAPI"
                wire_api = "openai"
                base_url = "https://legacy.example.com/v1"
                requires_openai_auth = true

                [model_providers.openai]
                base_url = "https://legacy-openai.example.com/v1"

                [model_providers.unmanaged]
                name = "KeepMe"
                base_url = "https://safe.example.com/v1"
                """.utf8
            ),
            to: CodexPaths.configTomlURL
        )

        let account = CodexBarProviderAccount(
            id: "acct_compatible_cleanup",
            kind: .apiKey,
            label: "Compatible",
            apiKey: "sk-compatible-cleanup"
        )
        let provider = CodexBarProvider(
            id: "compatible-cleanup",
            kind: .openAICompatible,
            label: "Compatible",
            enabled: true,
            baseURL: "https://compatible.example.com/v1",
            activeAccountId: account.id,
            accounts: [account]
        )

        try CodexSyncService().synchronize(
            config: CodexBarConfig(
                active: .init(providerId: provider.id, accountId: account.id),
                providers: [provider]
            )
        )

        let toml = try String(contentsOf: CodexPaths.configTomlURL, encoding: .utf8)
        XCTAssertTrue(toml.contains(#"custom_keep = "yes""#))
        XCTAssertTrue(toml.contains("# preserve me"))
        XCTAssertTrue(toml.contains("[model_providers.unmanaged]"))
        XCTAssertTrue(toml.contains(#"base_url = "https://safe.example.com/v1""#))
        XCTAssertFalse(toml.contains("oss_provider"))
        XCTAssertFalse(toml.contains("model_catalog_json"))
        XCTAssertFalse(toml.contains("preferred_auth_method"))
        XCTAssertFalse(toml.contains("[model_providers.openai]"))
        XCTAssertFalse(toml.contains(#"name = "CLIProxyAPI""#))
    }

    func testSynchronizeFailsFastWhenModelProvidersTableIsStructurallyInvalid() throws {
        try CodexPaths.ensureDirectories()
        let invalidToml = Data(
            """
            model_provider = "custom"
            model_providers = "invalid"
            custom_keep = "yes"
            """.utf8
        )
        try CodexPaths.writeSecureFile(invalidToml, to: CodexPaths.configTomlURL)

        let account = CodexBarProviderAccount(
            id: "acct_invalid_structure",
            kind: .apiKey,
            label: "Compatible",
            apiKey: "sk-compatible-invalid"
        )
        let provider = CodexBarProvider(
            id: "compatible-invalid",
            kind: .openAICompatible,
            label: "Compatible",
            enabled: true,
            baseURL: "https://compatible.example.com/v1",
            activeAccountId: account.id,
            accounts: [account]
        )

        XCTAssertThrowsError(
            try CodexSyncService().synchronize(
                config: CodexBarConfig(
                    active: .init(providerId: provider.id, accountId: account.id),
                    providers: [provider]
                )
            )
        )
        XCTAssertEqual(try Data(contentsOf: CodexPaths.configTomlURL), invalidToml)
    }

    func testSynchronizeAllowsManagedFieldsAtTopOrInPlace() throws {
        let account = CodexBarProviderAccount(
            id: "acct_position_tolerance",
            kind: .apiKey,
            label: "Compatible",
            apiKey: "sk-compatible-position"
        )
        let provider = CodexBarProvider(
            id: "compatible-position",
            kind: .openAICompatible,
            label: "Compatible",
            enabled: true,
            baseURL: "https://compatible.example.com/v1",
            activeAccountId: account.id,
            accounts: [account]
        )
        let cases = [
            """
            model_provider = "custom"
            custom_keep = "top"

            [model_providers.custom]
            name = "CLIProxyAPI"
            wire_api = "openai"
            base_url = "http://127.0.0.1:9317/v1"
            requires_openai_auth = true
            """,
            """
            custom_keep = "middle"

            [model_providers.unmanaged]
            name = "KeepMe"
            base_url = "https://safe.example.com/v1"

            model_provider = "custom"

            [model_providers.custom]
            name = "CLIProxyAPI"
            wire_api = "openai"
            base_url = "http://127.0.0.1:9317/v1"
            requires_openai_auth = true
            """,
        ]

        for (index, existingText) in cases.enumerated() {
            try CodexPaths.ensureDirectories()
            try CodexPaths.writeSecureFile(Data(existingText.utf8), to: CodexPaths.configTomlURL)
            try CodexSyncService().synchronize(
                config: CodexBarConfig(
                    active: .init(providerId: provider.id, accountId: account.id),
                    providers: [provider]
                )
            )

            let toml = try String(contentsOf: CodexPaths.configTomlURL, encoding: .utf8)
            XCTAssertTrue(toml.contains(#"model_provider = "custom""#), "case \(index)")
            XCTAssertTrue(toml.contains("[model_providers.custom]"), "case \(index)")
            XCTAssertTrue(toml.contains("[model_providers.unmanaged]") || toml.contains(#"custom_keep = "top""#), "case \(index)")
            XCTAssertTrue(toml.contains(#"base_url = "https://compatible.example.com/v1""#), "case \(index)")
        }
    }

    func testSynchronizeRollsBackAllTargetsAndPreAPISlotsWhenOneScopedTargetFails() throws {
        let rootA = try self.makeScopedRoot()
        let rootB = try self.makeScopedRoot()
        let targetA = self.scopedURLs(for: rootA)
        let targetB = self.scopedURLs(for: rootB)

        let originalAuthA = Data(#"{"auth_mode":"chatgpt","tokens":{"account_id":"acct_a"}}"#.utf8)
        let originalAuthB = Data(#"{"auth_mode":"chatgpt","tokens":{"account_id":"acct_b"}}"#.utf8)
        let originalConfigA = Data("custom_keep = \"orig-a\"\n".utf8)
        let originalConfigB = Data("custom_keep = \"orig-b\"\n".utf8)
        let preAPIAuthA = Data("pre-api-auth-a".utf8)
        let preAPIAuthB = Data("pre-api-auth-b".utf8)
        let preAPIConfigA = Data("pre-api-config-a".utf8)
        let preAPIConfigB = Data("pre-api-config-b".utf8)

        try CodexPaths.writeSecureFile(originalAuthA, to: targetA.authURL)
        try CodexPaths.writeSecureFile(originalAuthB, to: targetB.authURL)
        try CodexPaths.writeSecureFile(originalConfigA, to: targetA.configTomlURL)
        try CodexPaths.writeSecureFile(originalConfigB, to: targetB.configTomlURL)
        try CodexPaths.writeSecureFile(preAPIAuthA, to: targetA.authPreAPIBackupURL)
        try CodexPaths.writeSecureFile(preAPIAuthB, to: targetB.authPreAPIBackupURL)
        try CodexPaths.writeSecureFile(preAPIConfigA, to: targetA.configPreAPIBackupURL)
        try CodexPaths.writeSecureFile(preAPIConfigB, to: targetB.configPreAPIBackupURL)

        let account = self.makeOAuthAccount(id: "acct_scope_rollback")
        let provider = self.makeOAuthProvider(account: account)
        let config = CodexBarConfig(
            active: .init(providerId: provider.id, accountId: account.id),
            desktop: CodexBarDesktopSettings(
                accountActivationScope: .init(mode: .specificPaths, rootPaths: [rootA.path, rootB.path])
            ),
            providers: [provider]
        )

        let service = CodexSyncService(
            writeSecureFile: { data, url in
                if url == targetB.configTomlURL {
                    throw SyncFailure.configWriteFailed
                }
                try CodexPaths.writeSecureFile(data, to: url)
            }
        )

        XCTAssertThrowsError(try service.synchronize(config: config)) { error in
            XCTAssertEqual(error as? SyncFailure, .configWriteFailed)
        }

        XCTAssertEqual(try Data(contentsOf: targetA.authURL), originalAuthA)
        XCTAssertEqual(try Data(contentsOf: targetA.configTomlURL), originalConfigA)
        XCTAssertEqual(try Data(contentsOf: targetB.authURL), originalAuthB)
        XCTAssertEqual(try Data(contentsOf: targetB.configTomlURL), originalConfigB)
        XCTAssertEqual(try Data(contentsOf: targetA.authPreAPIBackupURL), preAPIAuthA)
        XCTAssertEqual(try Data(contentsOf: targetA.configPreAPIBackupURL), preAPIConfigA)
        XCTAssertEqual(try Data(contentsOf: targetB.authPreAPIBackupURL), preAPIAuthB)
        XCTAssertEqual(try Data(contentsOf: targetB.configPreAPIBackupURL), preAPIConfigB)
    }

    func testSynchronizeWritesFastServiceTierToSpecificActivationPaths() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let account = CodexBarProviderAccount(
            id: "acct_scope_fast",
            kind: .oauthTokens,
            label: "scoped-fast@example.com",
            email: "scoped-fast@example.com",
            openAIAccountId: "acct_scope_fast",
            accessToken: "access-scope-fast",
            refreshToken: "refresh-scope-fast",
            idToken: "id-scope-fast"
        )
        let provider = CodexBarProvider(
            id: "openai-oauth",
            kind: .openAIOAuth,
            label: "OpenAI",
            activeAccountId: account.id,
            accounts: [account]
        )
        let config = CodexBarConfig(
            global: CodexBarGlobalSettings(serviceTier: .fast),
            active: CodexBarActiveSelection(providerId: provider.id, accountId: account.id),
            desktop: CodexBarDesktopSettings(
                accountActivationScope: .init(
                    mode: .specificPaths,
                    rootPaths: [root.path]
                )
            ),
            providers: [provider]
        )

        try CodexSyncService().synchronize(config: config)

        let scopedTomlURL = root.appendingPathComponent(".codex/config.toml")
        let scopedToml = try String(contentsOf: scopedTomlURL, encoding: .utf8)
        XCTAssertTrue(scopedToml.contains(#"service_tier = "fast""#))
        XCTAssertFalse(FileManager.default.fileExists(atPath: CodexPaths.configTomlURL.path))
    }

    func testSynchronizeOfficialOAuthDirectRemovesManagedProviderFields() throws {
        try CodexPaths.ensureDirectories()
        try CodexPaths.writeSecureFile(
            Data(
                """
                model_provider = "custom"
                openai_base_url = "http://127.0.0.1:9317/v1"
                service_tier = "fast"
                model = "gpt-5.4"
                review_model = "gpt-5.4"
                model_reasoning_effort = "high"
                custom_keep = "yes"

                [model_providers.custom]
                name = "codexkit"
                wire_api = "responses"
                base_url = "http://127.0.0.1:9317/v1"
                requires_openai_auth = true
                """.utf8
            ),
            to: CodexPaths.configTomlURL
        )

        let account = self.makeOAuthAccount(id: "acct_pool_disabled")
        let provider = self.makeOAuthProvider(account: account)
        let config = CodexBarConfig(
            global: CodexBarGlobalSettings(serviceTier: .fast),
            active: CodexBarActiveSelection(providerId: provider.id, accountId: account.id),
            desktop: CodexBarDesktopSettings(
                cliProxyAPI: .init(
                    enabled: false,
                    host: "127.0.0.1",
                    port: 9317,
                    repositoryRootPath: "/tmp/CLIProxyAPI",
                    managementSecretKey: "secret",
                    memberAccountIDs: [account.id]
                )
            ),
            providers: [provider]
        )

        try CodexSyncService().synchronize(config: config)

        let authObject = try self.readAuthJSON()
        let tokens = try XCTUnwrap(authObject["tokens"] as? [String: Any])
        let tomlText = try String(contentsOf: CodexPaths.configTomlURL, encoding: .utf8)

        XCTAssertEqual(authObject["auth_mode"] as? String, "chatgpt")
        XCTAssertEqual(tokens["account_id"] as? String, "acct_pool_disabled")
        XCTAssertFalse(tomlText.contains("model_provider"))
        XCTAssertFalse(tomlText.contains("openai_base_url"))
        XCTAssertFalse(tomlText.contains("[model_providers.custom]"))
        XCTAssertFalse(tomlText.contains("requires_openai_auth"))
        XCTAssertTrue(tomlText.contains(#"custom_keep = "yes""#))
        self.assertManagedModelFieldsAbsent(in: tomlText)
    }

    func testSynchronizeWritesOAuthLifecycleMetadataToAuthJSON() throws {
        let tokenLastRefreshAt = Date(timeIntervalSince1970: 1_790_000_000)
        let account = CodexBarProviderAccount(
            id: "acct_sync_metadata",
            kind: .oauthTokens,
            label: "sync@example.com",
            email: "sync@example.com",
            openAIAccountId: "acct_sync_metadata",
            accessToken: "access-sync",
            refreshToken: "refresh-sync",
            idToken: "id-sync",
            expiresAt: Date(timeIntervalSince1970: 1_790_003_600),
            oauthClientID: "app_sync_client",
            tokenLastRefreshAt: tokenLastRefreshAt,
            lastRefresh: tokenLastRefreshAt
        )
        let provider = CodexBarProvider(
            id: "openai-oauth",
            kind: .openAIOAuth,
            label: "OpenAI",
            activeAccountId: account.id,
            accounts: [account]
        )
        let config = CodexBarConfig(
            active: CodexBarActiveSelection(providerId: provider.id, accountId: account.id),
            providers: [provider]
        )

        try CodexSyncService().synchronize(config: config)

        let authObject = try self.readAuthJSON()
        let tokens = try XCTUnwrap(authObject["tokens"] as? [String: Any])
        let formatter = ISO8601DateFormatter()

        XCTAssertEqual(authObject["client_id"] as? String, "app_sync_client")
        XCTAssertEqual(authObject["last_refresh"] as? String, formatter.string(from: tokenLastRefreshAt))
        XCTAssertEqual(tokens["access_token"] as? String, "access-sync")
        XCTAssertEqual(tokens["refresh_token"] as? String, "refresh-sync")
        XCTAssertEqual(tokens["account_id"] as? String, "acct_sync_metadata")
    }

    func testSynchronizeWritesToSpecificActivationPathsOnly() throws {
        let rootA = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let rootB = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootB, withIntermediateDirectories: true)

        let account = CodexBarProviderAccount(
            id: "acct_specific",
            kind: .oauthTokens,
            label: "specific@example.com",
            email: "specific@example.com",
            openAIAccountId: "acct_specific",
            accessToken: "access-specific",
            refreshToken: "refresh-specific",
            idToken: "id-specific"
        )
        let provider = CodexBarProvider(
            id: "openai-oauth",
            kind: .openAIOAuth,
            label: "OpenAI",
            activeAccountId: account.id,
            accounts: [account]
        )
        let config = CodexBarConfig(
            active: CodexBarActiveSelection(providerId: provider.id, accountId: account.id),
            desktop: CodexBarDesktopSettings(
                accountActivationScope: .init(
                    mode: .specificPaths,
                    rootPaths: [rootA.path, rootB.path]
                )
            ),
            providers: [provider]
        )

        try CodexSyncService().synchronize(config: config)

        XCTAssertFalse(FileManager.default.fileExists(atPath: CodexPaths.codexRoot.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: CodexPaths.authURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: rootA.appendingPathComponent(".codex/auth.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: rootA.appendingPathComponent(".codex/config.toml").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: rootB.appendingPathComponent(".codex/auth.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: rootB.appendingPathComponent(".codex/config.toml").path))
    }

    func testSynchronizeWritesToGlobalAndSpecificActivationPaths() throws {
        try CodexPaths.ensureDirectories()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let account = CodexBarProviderAccount(
            id: "acct_mixed",
            kind: .oauthTokens,
            label: "mixed@example.com",
            email: "mixed@example.com",
            openAIAccountId: "acct_mixed",
            accessToken: "access-mixed",
            refreshToken: "refresh-mixed",
            idToken: "id-mixed"
        )
        let provider = CodexBarProvider(
            id: "openai-oauth",
            kind: .openAIOAuth,
            label: "OpenAI",
            activeAccountId: account.id,
            accounts: [account]
        )
        let config = CodexBarConfig(
            active: CodexBarActiveSelection(providerId: provider.id, accountId: account.id),
            desktop: CodexBarDesktopSettings(
                accountActivationScope: .init(
                    mode: .globalAndSpecificPaths,
                    rootPaths: [root.path]
                )
            ),
            providers: [provider]
        )

        try CodexSyncService().synchronize(config: config)

        XCTAssertTrue(FileManager.default.fileExists(atPath: CodexPaths.authURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: CodexPaths.configTomlURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(".codex/auth.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(".codex/config.toml").path))
    }

    func testPrimaryNativeTargetUsesFirstSpecificRootWhenGlobalIsExcluded() {
        let desktopSettings = CodexBarDesktopSettings(
            accountActivationScope: .init(
                mode: .specificPaths,
                rootPaths: ["/tmp/project-b", "/tmp/project-a"]
            )
        )

        let primaryTarget = CodexPaths.primaryNativeTarget(for: desktopSettings)

        XCTAssertEqual(primaryTarget.rootURL.path, "/tmp/project-b")
        XCTAssertEqual(primaryTarget.codexRootURL.path, "/tmp/project-b/.codex")
        XCTAssertFalse(primaryTarget.isGlobal)
    }

    func testCleanupRemovedTargetsOnlyTouchesManagedFilesInsideRemovedCodexRoot() throws {
        let removedRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let keptRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let removedCodexRoot = removedRoot.appendingPathComponent(".codex", isDirectory: true)
        let keptCodexRoot = keptRoot.appendingPathComponent(".codex", isDirectory: true)

        try FileManager.default.createDirectory(at: removedCodexRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: keptCodexRoot, withIntermediateDirectories: true)

        try Data("removed-backup-auth".utf8).write(to: removedCodexRoot.appendingPathComponent("auth.json.bak-codexkit-last"))
        try Data("removed-backup-config".utf8).write(to: removedCodexRoot.appendingPathComponent("config.toml.bak-codexkit-last"))
        try Data("removed-current-auth".utf8).write(to: removedCodexRoot.appendingPathComponent("auth.json"))
        try Data("removed-current-config".utf8).write(to: removedCodexRoot.appendingPathComponent("config.toml"))
        try Data("preserve-me".utf8).write(to: removedCodexRoot.appendingPathComponent("custom.json"))
        try Data("kept-auth".utf8).write(to: keptCodexRoot.appendingPathComponent("auth.json"))

        let service = CodexSyncService()
        try service.cleanupRemovedTargets(
            previousDesktopSettings: CodexBarDesktopSettings(
                accountActivationScope: .init(
                    mode: .specificPaths,
                    rootPaths: [removedRoot.path, keptRoot.path]
                )
            ),
            currentDesktopSettings: CodexBarDesktopSettings(
                accountActivationScope: .init(
                    mode: .specificPaths,
                    rootPaths: [keptRoot.path]
                )
            )
        )

        XCTAssertEqual(
            try String(contentsOf: removedCodexRoot.appendingPathComponent("auth.json"), encoding: .utf8),
            "removed-backup-auth"
        )
        XCTAssertEqual(
            try String(contentsOf: removedCodexRoot.appendingPathComponent("config.toml"), encoding: .utf8),
            "removed-backup-config"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: removedCodexRoot.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: removedCodexRoot.appendingPathComponent("custom.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: keptCodexRoot.appendingPathComponent("auth.json").path))
    }

    func testCleanupRemovedTargetsDeletesManagedCompatibleProviderAuthWithoutBackup() throws {
        let removedRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let removedCodexRoot = removedRoot.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: removedCodexRoot, withIntermediateDirectories: true)

        let account = CodexBarProviderAccount(
            id: "acct-compatible",
            kind: .apiKey,
            label: "Compatible",
            apiKey: "sk-compatible"
        )
        let provider = CodexBarProvider(
            id: "compatible",
            kind: .openAICompatible,
            label: "Compatible",
            enabled: true,
            baseURL: "https://compatible.example.com/v1",
            activeAccountId: account.id,
            accounts: [account]
        )
        let config = CodexBarConfig(
            active: CodexBarActiveSelection(providerId: provider.id, accountId: account.id),
            desktop: CodexBarDesktopSettings(
                accountActivationScope: .init(
                    mode: .specificPaths,
                    rootPaths: [removedRoot.path]
                )
            ),
            providers: [provider]
        )

        try CodexSyncService().synchronize(config: config)
        XCTAssertTrue(FileManager.default.fileExists(atPath: removedCodexRoot.appendingPathComponent("auth.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: removedCodexRoot.appendingPathComponent("auth.json.bak-codexkit-last").path))

        try CodexSyncService().cleanupRemovedTargets(
            previousDesktopSettings: config.desktop,
            currentDesktopSettings: CodexBarDesktopSettings(
                accountActivationScope: .init(
                    mode: .global,
                    rootPaths: []
                )
            )
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: removedCodexRoot.appendingPathComponent("auth.json").path))
    }

    func testSynchronizeWritesOpenRouterGatewayConfigAndProviderModel() throws {
        let account = CodexBarProviderAccount(
            id: "acct_openrouter",
            kind: .apiKey,
            label: "OpenRouter Primary",
            apiKey: "sk-or-v1-primary"
        )
        let provider = CodexBarProvider(
            id: "openrouter",
            kind: .openRouter,
            label: "OpenRouter",
            enabled: true,
            selectedModelID: "anthropic/claude-3.7-sonnet",
            activeAccountId: account.id,
            accounts: [account]
        )
        let config = CodexBarConfig(
            global: CodexBarGlobalSettings(
                defaultModel: "gpt-5.4",
                reviewModel: "gpt-5.4",
                reasoningEffort: "high"
            ),
            active: CodexBarActiveSelection(providerId: provider.id, accountId: account.id),
            providers: [provider]
        )

        try CodexSyncService().synchronize(config: config)

        let authObject = try self.readAuthJSON()
        let tomlText = try String(contentsOf: CodexPaths.configTomlURL, encoding: .utf8)

        XCTAssertEqual(authObject["OPENAI_API_KEY"] as? String, account.apiKey)
        XCTAssertEqual(authObject["auth_mode"] as? String, "apikey")
        XCTAssertTrue(tomlText.contains(#"model_provider = "custom""#))
        XCTAssertTrue(tomlText.contains("[model_providers.custom]"))
        XCTAssertTrue(tomlText.contains(#"name = "OpenRouter""#))
        XCTAssertTrue(tomlText.contains(#"wire_api = "responses""#))
        XCTAssertTrue(tomlText.contains(#"base_url = "https://openrouter.ai/api/v1""#))
        XCTAssertTrue(tomlText.contains("requires_openai_auth = true"))
        XCTAssertFalse(tomlText.contains("openai_base_url"))
        self.assertManagedModelFieldsAbsent(in: tomlText)
    }

    func testSynchronizeCustomProviderDirectWritesManagedCustomBlock() throws {
        let account = CodexBarProviderAccount(
            id: "acct_compatible_sync",
            kind: .apiKey,
            label: "Compatible Primary",
            apiKey: "sk-compatible-primary"
        )
        let provider = CodexBarProvider(
            id: "compatible",
            kind: .openAICompatible,
            label: "Compatible",
            enabled: true,
            baseURL: "https://compatible.example.com/v1",
            activeAccountId: account.id,
            accounts: [account]
        )
        let config = CodexBarConfig(
            global: CodexBarGlobalSettings(
                defaultModel: "gpt-5.4",
                reviewModel: "gpt-5.4",
                reasoningEffort: "high"
            ),
            active: CodexBarActiveSelection(providerId: provider.id, accountId: account.id),
            providers: [provider]
        )

        try CodexSyncService().synchronize(config: config)

        let authObject = try self.readAuthJSON()
        let tomlText = try String(contentsOf: CodexPaths.configTomlURL, encoding: .utf8)

        XCTAssertEqual(authObject["OPENAI_API_KEY"] as? String, "sk-compatible-primary")
        XCTAssertEqual(authObject["auth_mode"] as? String, "apikey")
        XCTAssertTrue(tomlText.contains(#"model_provider = "custom""#))
        XCTAssertTrue(tomlText.contains("[model_providers.custom]"))
        XCTAssertTrue(tomlText.contains(#"name = "Compatible""#))
        XCTAssertTrue(tomlText.contains(#"wire_api = "responses""#))
        XCTAssertTrue(tomlText.contains(#"base_url = "https://compatible.example.com/v1""#))
        XCTAssertTrue(tomlText.contains("requires_openai_auth = true"))
        XCTAssertFalse(tomlText.contains("openai_base_url"))
        self.assertManagedModelFieldsAbsent(in: tomlText)
    }

    private func makeOAuthAccount(id: String) -> CodexBarProviderAccount {
        CodexBarProviderAccount(
            id: id,
            kind: .oauthTokens,
            label: "\(id)@example.com",
            email: "\(id)@example.com",
            openAIAccountId: id,
            accessToken: "access-\(id)",
            refreshToken: "refresh-\(id)",
            idToken: "id-\(id)"
        )
    }

    private func makeOAuthSnapshotAuthData(accountID: String) -> Data {
        Data(
            #"""
            {
              "auth_mode":"chatgpt",
              "tokens":{
                "access_token":"access-\#(accountID)",
                "refresh_token":"refresh-\#(accountID)",
                "id_token":"id-\#(accountID)",
                "account_id":"\#(accountID)"
              }
            }
            """#.utf8
        )
    }

    private func makeOAuthProvider(account: CodexBarProviderAccount) -> CodexBarProvider {
        CodexBarProvider(
            id: "openai-oauth",
            kind: .openAIOAuth,
            label: "OpenAI",
            activeAccountId: account.id,
            accounts: [account]
        )
    }

    private func makeScopedRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".codex", isDirectory: true), withIntermediateDirectories: true)
        return root
    }

    private func scopedURLs(
        for root: URL
    ) -> (
        authURL: URL,
        configTomlURL: URL,
        authBackupURL: URL,
        configBackupURL: URL,
        authPreAPIBackupURL: URL,
        configPreAPIBackupURL: URL
    ) {
        let codexRoot = root.appendingPathComponent(".codex", isDirectory: true)
        return (
            authURL: codexRoot.appendingPathComponent("auth.json"),
            configTomlURL: codexRoot.appendingPathComponent("config.toml"),
            authBackupURL: codexRoot.appendingPathComponent("auth.json.bak-codexkit-last"),
            configBackupURL: codexRoot.appendingPathComponent("config.toml.bak-codexkit-last"),
            authPreAPIBackupURL: codexRoot.appendingPathComponent("auth.json.bak-codexkit-pre-api-service"),
            configPreAPIBackupURL: codexRoot.appendingPathComponent("config.toml.bak-codexkit-pre-api-service")
        )
    }

    private func readJSONObject(at url: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func assertManagedModelFieldsAbsent(
        in toml: String,
        label: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(toml.contains(#"model = ""#), label, file: file, line: line)
        XCTAssertFalse(toml.contains("review_model"), label, file: file, line: line)
        XCTAssertFalse(toml.contains("model_reasoning_effort"), label, file: file, line: line)
    }

    private enum SyncFailure: Error, Equatable {
        case configWriteFailed
    }
}
