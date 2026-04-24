import XCTest
@testable import CodexkitApp

final class SettingsSaveRequestApplierTests: XCTestCase {
    func testCLIProxyAPIRequestAppliesExplicitClientAPIKey() {
        var config = CodexBarConfig()
        let request = CLIProxyAPISettingsUpdate(
            enabled: true,
            host: "127.0.0.1",
            port: 8317,
            repositoryRootPath: nil,
            managementSecretKey: "management-secret",
            clientAPIKey: "client-secret",
            memberAccountIDs: []
        )

        SettingsSaveRequestApplier.apply(request, to: &config)

        XCTAssertEqual(config.desktop.cliProxyAPI.clientAPIKey, "client-secret")
    }

    func testCLIProxyAPIRequestPreservesExistingClientAPIKeyWhenRequestOmitsIt() {
        var config = CodexBarConfig()
        config.desktop.cliProxyAPI.clientAPIKey = "existing-client-secret"

        let request = CLIProxyAPISettingsUpdate(
            enabled: true,
            host: "127.0.0.1",
            port: 8317,
            repositoryRootPath: nil,
            managementSecretKey: "management-secret",
            clientAPIKey: nil,
            memberAccountIDs: []
        )

        SettingsSaveRequestApplier.apply(request, to: &config)

        XCTAssertEqual(config.desktop.cliProxyAPI.clientAPIKey, "existing-client-secret")
    }

    func testCLIProxyAPIRequestGeneratesClientAPIKeyWhenMissing() {
        var config = CodexBarConfig()

        let request = CLIProxyAPISettingsUpdate(
            enabled: true,
            host: "127.0.0.1",
            port: 8317,
            repositoryRootPath: nil,
            managementSecretKey: "management-secret",
            clientAPIKey: nil,
            memberAccountIDs: []
        )

        SettingsSaveRequestApplier.apply(request, to: &config)

        XCTAssertFalse((config.desktop.cliProxyAPI.clientAPIKey ?? "").isEmpty)
        XCTAssertNotEqual(config.desktop.cliProxyAPI.clientAPIKey, "management-secret")
    }
}
