import Foundation

struct CLIProxyAPIAuthExporter {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func export(
        accounts: [TokenAccount],
        prioritiesByAccountID: [String: Int] = [:],
        to directory: URL
    ) throws -> [URL] {
        try self.fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let existing = try self.fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for url in existing where url.pathExtension.lowercased() == "json" {
            try? self.fileManager.removeItem(at: url)
        }

        return try accounts.map { account in
            let fileURL = directory.appendingPathComponent(self.fileName(for: account))
            let payload = self.payload(for: account, priority: prioritiesByAccountID[account.accountId])
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try CodexPaths.writeSecureFile(data, to: fileURL)
            return fileURL
        }
    }

    private func fileName(for account: TokenAccount) -> String {
        let email = account.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "@", with: "_at_")
            .replacingOccurrences(of: "/", with: "_")
        let plan = account.planType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: " ", with: "-")
        if plan == "team" {
            let digest = String(account.remoteAccountId.hashValue.magnitude, radix: 16).prefix(8)
            return "codex-\(digest)-\(email)-team.json"
        }
        return "codex-\(email)-\(plan.isEmpty ? "free" : plan).json"
    }

    private func payload(for account: TokenAccount, priority: Int?) -> [String: Any] {
        var payload: [String: Any] = [
            "type": "codex",
            "email": account.email,
            "account_id": account.remoteAccountId,
            "codexkit_local_account_id": account.accountId,
            "access_token": account.accessToken,
            "refresh_token": account.refreshToken,
            "id_token": account.idToken,
            "last_refresh": ISO8601DateFormatter().string(from: account.tokenLastRefreshAt ?? Date()),
            "plan_type": account.planType,
        ]
        if let priority {
            payload["priority"] = priority
        }
        if let expiresAt = account.expiresAt {
            payload["expired"] = ISO8601DateFormatter().string(from: expiresAt)
        }
        return payload
    }
}
