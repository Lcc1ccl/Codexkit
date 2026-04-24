import Foundation

protocol OpenRouterGatewayLeaseStoring {
    func loadLease() -> OpenRouterGatewayLeaseSnapshot?
    func saveLease(_ lease: OpenRouterGatewayLeaseSnapshot)
    func clear()
    func hasActiveLease() -> Bool
}

extension OpenRouterGatewayLeaseStoring {
    func hasActiveLease() -> Bool {
        guard let lease = self.loadLease() else { return false }
        return lease.leasedProcessIDs.isEmpty == false
    }
}

struct OpenRouterGatewayLeaseSnapshot: Codable, Equatable {
    var leasedProcessIDs: [Int32]
    var leasedAt: Date
    var sourceProviderId: String

    var processIDs: Set<pid_t> {
        Set(self.leasedProcessIDs.map { pid_t($0) })
    }

    init(
        processIDs: Set<pid_t>,
        leasedAt: Date = Date(),
        sourceProviderId: String = "openrouter"
    ) {
        self.leasedProcessIDs = processIDs.map { Int32($0) }.sorted()
        self.leasedAt = leasedAt
        self.sourceProviderId = sourceProviderId
    }
}

final class OpenRouterGatewayLeaseStore: OpenRouterGatewayLeaseStoring {
    private let fileURL: URL
    private let fileManager: FileManager

    init(
        fileURL: URL = CodexPaths.openRouterGatewayStateURL,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func loadLease() -> OpenRouterGatewayLeaseSnapshot? {
        guard let data = try? Data(contentsOf: self.fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(OpenRouterGatewayLeaseSnapshot.self, from: data)
    }

    func saveLease(_ lease: OpenRouterGatewayLeaseSnapshot) {
        guard lease.leasedProcessIDs.isEmpty == false else {
            self.clear()
            return
        }

        try? CodexPaths.ensureDirectories()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(lease) else { return }
        try? CodexPaths.writeSecureFile(data, to: self.fileURL)
    }

    func clear() {
        guard self.fileManager.fileExists(atPath: self.fileURL.path) else { return }
        try? self.fileManager.removeItem(at: self.fileURL)
    }
}
