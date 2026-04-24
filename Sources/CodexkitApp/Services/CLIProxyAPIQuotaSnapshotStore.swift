import Foundation

final class CLIProxyAPIQuotaSnapshotStore {
    private struct StoredSnapshot: Codable {
        var version: Int
        var snapshot: CLIProxyAPIQuotaSnapshot
    }

    static let shared = CLIProxyAPIQuotaSnapshotStore()

    private let url: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let version = 1

    init(url: URL = CodexPaths.cliProxyAPIQuotaSnapshotURL) {
        self.url = url
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func load() -> CLIProxyAPIQuotaSnapshot? {
        guard let data = try? Data(contentsOf: self.url),
              let stored = try? self.decoder.decode(StoredSnapshot.self, from: data),
              stored.version == self.version else {
            return nil
        }
        return stored.snapshot
    }

    func save(_ snapshot: CLIProxyAPIQuotaSnapshot) {
        let stored = StoredSnapshot(version: self.version, snapshot: snapshot)
        guard let data = try? self.encoder.encode(stored) else { return }
        try? CodexPaths.writeSecureFile(data, to: self.url)
    }
}
