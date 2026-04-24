import Foundation
import XCTest
@testable import CodexkitApp

final class CLIProxyAPIAuthExporterTests: XCTestCase {
    func testExportWritesCodexAuthJSONFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let exporter = CLIProxyAPIAuthExporter()
        let account = TokenAccount(
            email: "alpha@example.com",
            accountId: "acct_alpha",
            openAIAccountId: "remote_alpha",
            accessToken: "access-token",
            refreshToken: "refresh-token",
            idToken: "id-token",
            planType: "plus"
        )

        let files = try exporter.export(accounts: [account], to: tempDir)

        XCTAssertEqual(files.count, 1)
        let data = try Data(contentsOf: files[0])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["type"] as? String, "codex")
        XCTAssertEqual(object["email"] as? String, "alpha@example.com")
        XCTAssertEqual(object["account_id"] as? String, "remote_alpha")
        XCTAssertEqual(object["access_token"] as? String, "access-token")
        XCTAssertEqual(object["refresh_token"] as? String, "refresh-token")
        XCTAssertEqual(object["id_token"] as? String, "id-token")
    }

    func testExportIncludesPriorityAndStableLocalAccountMetadataWhenProvided() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let exporter = CLIProxyAPIAuthExporter()
        let account = TokenAccount(
            email: "alpha@example.com",
            accountId: "acct_alpha",
            openAIAccountId: "remote_alpha",
            accessToken: "access-token",
            refreshToken: "refresh-token",
            idToken: "id-token",
            planType: "team"
        )

        let files = try exporter.export(
            accounts: [account],
            prioritiesByAccountID: ["acct_alpha": 7],
            to: tempDir
        )

        let data = try Data(contentsOf: files[0])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["priority"] as? Int, 7)
        XCTAssertEqual(object["codexkit_local_account_id"] as? String, "acct_alpha")
    }
}
