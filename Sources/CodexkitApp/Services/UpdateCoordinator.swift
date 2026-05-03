import AppKit
import Combine
import CryptoKit
import Foundation

private let hardcodedCodexkitReleasesURL = URL(string: "https://api.github.com/repos/Lcc1ccl/Codexkit/releases")!
private let hardcodedCodexkitLatestReleasePageURL = URL(string: "https://github.com/Lcc1ccl/Codexkit/releases/latest")!
private let hardcodedCLIProxyAPILatestReleaseURL = URL(string: "https://api.github.com/repos/router-for-me/CLIProxyAPI/releases/latest")!
private let hardcodedCLIProxyAPIReleasePageURL = URL(string: "https://github.com/router-for-me/CLIProxyAPI/releases/latest")!

enum AppUpdateError: LocalizedError {
    case missingReleasesURL
    case invalidCurrentVersion(String)
    case invalidReleaseVersion(String)
    case invalidResponse
    case unexpectedStatusCode(Int)
    case noInstallableStableRelease
    case noCompatibleArtifact(UpdateArtifactArchitecture)
    case failedToOpenDownloadURL(URL)
    case automaticUpdateUnavailable

    var errorDescription: String? {
        switch self {
        case .missingReleasesURL:
            return L.updateErrorMissingReleasesURL
        case let .invalidCurrentVersion(version):
            return L.updateErrorInvalidCurrentVersion(version)
        case let .invalidReleaseVersion(version):
            return L.updateErrorInvalidReleaseVersion(version)
        case .invalidResponse:
            return L.updateErrorInvalidResponse
        case let .unexpectedStatusCode(statusCode):
            return L.updateErrorUnexpectedStatusCode(statusCode)
        case .noInstallableStableRelease:
            return L.updateErrorNoInstallableStableRelease
        case let .noCompatibleArtifact(architecture):
            return L.updateErrorNoCompatibleArtifact(architecture.displayName)
        case let .failedToOpenDownloadURL(url):
            return L.updateErrorFailedToOpenDownloadURL(url.absoluteString)
        case .automaticUpdateUnavailable:
            return L.updateErrorAutomaticUpdateUnavailable
        }
    }
}

protocol AppUpdateReleaseLoading {
    func loadLatestRelease() async throws -> AppUpdateRelease
}

protocol AppUpdateEnvironmentProviding {
    var currentVersion: String { get }
    var bundleURL: URL { get }
    var architecture: UpdateArtifactArchitecture { get }
    var githubReleasesURL: URL? { get }
}

protocol AppSignatureInspecting {
    func inspect(bundleURL: URL) -> AppSignatureInspection
}

protocol AppGatekeeperInspecting {
    func inspect(bundleURL: URL) -> AppGatekeeperInspection
}

protocol AppUpdateCapabilityEvaluating {
    func blockers(
        for release: AppUpdateRelease,
        environment: AppUpdateEnvironmentProviding
    ) -> [AppUpdateBlocker]
}

protocol AppUpdateActionExecuting {
    func execute(_ availability: AppUpdateAvailability) async throws
}

protocol AppUpdateRelaunching {
    func relaunch(appURL: URL) throws
}

enum CLIProxyAPIArtifactFormat: String, Equatable {
    case tarGzip
    case zip
    case executable
}

struct CLIProxyAPIReleaseArtifact: Equatable {
    var name: String
    var downloadURL: URL
    var architecture: UpdateArtifactArchitecture
    var format: CLIProxyAPIArtifactFormat
    var sha256: String?
}

struct CLIProxyAPIUpdateRelease: Equatable {
    var version: String
    var releasePageURL: URL
    var artifact: CLIProxyAPIReleaseArtifact? = nil
}

struct CLIProxyAPIUpdateAvailability: Equatable {
    var installedVersion: String
    var release: CLIProxyAPIUpdateRelease
}

enum CLIProxyAPIUpdateState: Equatable {
    case idle
    case checking(UpdateCheckTrigger)
    case upToDate(installedVersion: String, checkedVersion: String)
    case updateAvailable(CLIProxyAPIUpdateAvailability)
    case executing(CLIProxyAPIUpdateAvailability)
    case failed(String)
}

protocol CLIProxyAPIInstalledVersionProviding {
    func resolveInstalledVersion() -> String
}

protocol CLIProxyAPIReleaseLoading {
    func loadLatestRelease() async throws -> CLIProxyAPIUpdateRelease
}

protocol CLIProxyAPIUpdateActionExecuting {
    func execute(_ availability: CLIProxyAPIUpdateAvailability) async throws
}

protocol AppUpdateAutomaticCheckCancelling {
    func cancel()
}

protocol AppUpdateAutomaticCheckScheduling {
    func scheduleRepeating(
        every interval: TimeInterval,
        operation: @escaping @Sendable @MainActor () async -> Void
    ) -> AppUpdateAutomaticCheckCancelling
}

struct AppSignatureInspection: Equatable {
    var hasUsableSignature: Bool
    var summary: String
}

struct AppGatekeeperInspection: Equatable {
    var passesAssessment: Bool
    var summary: String
}

final class TaskBasedAutomaticCheckHandle: AppUpdateAutomaticCheckCancelling {
    private var task: Task<Void, Never>?

    init(task: Task<Void, Never>) {
        self.task = task
    }

    func cancel() {
        self.task?.cancel()
        self.task = nil
    }

    deinit {
        self.cancel()
    }
}

struct TaskBasedAutomaticCheckScheduler: AppUpdateAutomaticCheckScheduling {
    func scheduleRepeating(
        every interval: TimeInterval,
        operation: @escaping @Sendable @MainActor () async -> Void
    ) -> AppUpdateAutomaticCheckCancelling {
        let clampedInterval = max(interval, 1)
        let sleepNanoseconds = UInt64(clampedInterval * 1_000_000_000)

        let task = Task {
            while Task.isCancelled == false {
                do {
                    try await Task.sleep(nanoseconds: sleepNanoseconds)
                } catch {
                    return
                }

                guard Task.isCancelled == false else { return }
                await operation()
            }
        }

        return TaskBasedAutomaticCheckHandle(task: task)
    }
}

struct LiveAppUpdateEnvironment: AppUpdateEnvironmentProviding {
    var currentVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return version?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? version! : "0.0.0"
    }

    var bundleURL: URL {
        Bundle.main.bundleURL
    }

    var architecture: UpdateArtifactArchitecture {
        #if arch(arm64)
        return .arm64
        #elseif arch(x86_64)
        return .x86_64
        #else
        return .universal
        #endif
    }

    var githubReleasesURL: URL? {
        hardcodedCodexkitReleasesURL
    }
}

struct LocalCLIProxyAPIInstalledVersionProvider: CLIProxyAPIInstalledVersionProviding {
    var service: CLIProxyAPIService = .shared

    func resolveInstalledVersion() -> String {
        if let version = self.service.resolveManagedRuntimeDescriptor()?.version
            .trimmingCharacters(in: .whitespacesAndNewlines),
            version.isEmpty == false {
            return version
        }

        if let descriptor = self.service.resolveBundledRuntimeDescriptor(),
           let version = descriptor.version?.trimmingCharacters(in: .whitespacesAndNewlines),
           version.isEmpty == false {
            return version
        }

        guard let repoRoot = self.service.resolveBundledRepoRoot() else {
            return "unknown"
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", repoRoot.path, "describe", "--tags", "--always", "--dirty"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let version = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return version?.isEmpty == false ? version! : "unknown"
        } catch {
            return "unknown"
        }
    }
}

enum CLIProxyAPIReleaseArtifactSelector {
    static func artifact(
        from asset: GitHubReleaseAsset
    ) -> CLIProxyAPIReleaseArtifact? {
        let normalizedName = asset.name.lowercased()
        guard normalizedName.contains("darwin") || normalizedName.contains("macos") else {
            return nil
        }
        guard let format = Self.inferFormat(from: normalizedName) else {
            return nil
        }

        return CLIProxyAPIReleaseArtifact(
            name: asset.name,
            downloadURL: asset.browserDownloadURL,
            architecture: Self.inferArchitecture(from: normalizedName),
            format: format,
            sha256: Self.normalizeDigest(asset.digest)
        )
    }

    static func selectArtifact(
        for architecture: UpdateArtifactArchitecture,
        artifacts: [CLIProxyAPIReleaseArtifact]
    ) throws -> CLIProxyAPIReleaseArtifact {
        let architecturePreference: [UpdateArtifactArchitecture]
        switch architecture {
        case .arm64:
            architecturePreference = [.arm64, .universal]
        case .x86_64:
            architecturePreference = [.x86_64, .universal]
        case .universal:
            architecturePreference = [.universal, .arm64, .x86_64]
        }

        let formatPreference: [CLIProxyAPIArtifactFormat] = [.tarGzip, .zip, .executable]

        for preferredFormat in formatPreference {
            for preferredArchitecture in architecturePreference {
                if let artifact = artifacts.first(where: {
                    $0.architecture == preferredArchitecture && $0.format == preferredFormat
                }) {
                    return artifact
                }
            }
        }

        throw AppUpdateError.noCompatibleArtifact(architecture)
    }

    private static func inferFormat(from normalizedName: String) -> CLIProxyAPIArtifactFormat? {
        if normalizedName.hasSuffix(".tar.gz") || normalizedName.hasSuffix(".tgz") {
            return .tarGzip
        }
        if normalizedName.hasSuffix(".zip") {
            return .zip
        }
        if normalizedName.hasSuffix("/cli-proxy-api") || normalizedName == "cli-proxy-api" {
            return .executable
        }
        return nil
    }

    private static func inferArchitecture(from normalizedName: String) -> UpdateArtifactArchitecture {
        if normalizedName.contains("x86_64")
            || normalizedName.contains("x64")
            || normalizedName.contains("amd64")
            || normalizedName.contains("intel") {
            return .x86_64
        }
        if normalizedName.contains("arm64")
            || normalizedName.contains("aarch64")
            || normalizedName.contains("apple-silicon") {
            return .arm64
        }
        return .universal
    }

    private static func normalizeDigest(_ digest: String?) -> String? {
        guard let trimmed = digest?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmed.isEmpty == false else {
            return nil
        }
        guard trimmed.hasPrefix("sha256:") else {
            return nil
        }
        return String(trimmed.dropFirst("sha256:".count))
    }
}

struct LiveCLIProxyAPIReleaseLoader: CLIProxyAPIReleaseLoading {
    var session: URLSession = .shared
    var architecture: UpdateArtifactArchitecture = LiveAppUpdateEnvironment().architecture

    private struct ReleaseInfo: Decodable {
        var tagName: String
        var htmlURL: URL?
        var assets: [GitHubReleaseAsset]?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case assets
        }
    }

    func loadLatestRelease() async throws -> CLIProxyAPIUpdateRelease {
        var request = URLRequest(url: hardcodedCLIProxyAPILatestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("CLIProxyAPI", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await self.session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppUpdateError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 403 || httpResponse.statusCode == 429 {
                return try await self.loadLatestReleaseFromReleasePageFallback()
            }
            throw AppUpdateError.unexpectedStatusCode(httpResponse.statusCode)
        }

        let releaseInfo: ReleaseInfo
        do {
            releaseInfo = try JSONDecoder().decode(ReleaseInfo.self, from: data)
        } catch {
            throw AppUpdateError.invalidResponse
        }

        let version = releaseInfo.tagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard version.isEmpty == false else {
            throw AppUpdateError.invalidResponse
        }

        let artifacts = (releaseInfo.assets ?? []).compactMap(CLIProxyAPIReleaseArtifactSelector.artifact(from:))
        let selectedArtifact = try? CLIProxyAPIReleaseArtifactSelector.selectArtifact(
            for: self.architecture,
            artifacts: artifacts
        )

        return CLIProxyAPIUpdateRelease(
            version: version,
            releasePageURL: releaseInfo.htmlURL ?? hardcodedCLIProxyAPIReleasePageURL,
            artifact: selectedArtifact
        )
    }

    private func loadLatestReleaseFromReleasePageFallback() async throws -> CLIProxyAPIUpdateRelease {
        var request = URLRequest(url: hardcodedCLIProxyAPIReleasePageURL)
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.setValue("CLIProxyAPI", forHTTPHeaderField: "User-Agent")

        let (_, response) = try await self.session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppUpdateError.invalidResponse
        }
        guard (200...399).contains(httpResponse.statusCode) else {
            throw AppUpdateError.unexpectedStatusCode(httpResponse.statusCode)
        }

        let resolvedURL = self.resolvedLatestReleaseURL(from: httpResponse)
        guard let tag = Self.releaseTag(from: resolvedURL),
              AppSemanticVersion(tag) != nil else {
            throw AppUpdateError.invalidResponse
        }

        return CLIProxyAPIUpdateRelease(
            version: tag,
            releasePageURL: resolvedURL,
            artifact: Self.fallbackArtifact(tag: tag, architecture: self.architecture)
        )
    }

    private func resolvedLatestReleaseURL(from response: HTTPURLResponse) -> URL {
        if let responseURL = response.url,
           Self.releaseTag(from: responseURL) != nil {
            return responseURL
        }
        if let location = response.value(forHTTPHeaderField: "Location"),
           let locationURL = URL(string: location),
           Self.releaseTag(from: locationURL) != nil {
            return locationURL
        }
        return hardcodedCLIProxyAPIReleasePageURL
    }

    private static func releaseTag(from url: URL) -> String? {
        let components = url.pathComponents
        guard let tagIndex = components.firstIndex(of: "tag"),
              components.index(after: tagIndex) < components.endIndex else {
            return nil
        }

        let tag = components[components.index(after: tagIndex)]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return tag.isEmpty ? nil : tag
    }

    private static func fallbackArtifact(
        tag: String,
        architecture: UpdateArtifactArchitecture
    ) -> CLIProxyAPIReleaseArtifact {
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let resolvedArchitecture: UpdateArtifactArchitecture
        let architectureSlug: String
        switch architecture {
        case .x86_64:
            resolvedArchitecture = .x86_64
            architectureSlug = "amd64"
        case .arm64, .universal:
            resolvedArchitecture = .arm64
            architectureSlug = "arm64"
        }

        let name = "CLIProxyAPI_\(version)_darwin_\(architectureSlug).tar.gz"
        return CLIProxyAPIReleaseArtifact(
            name: name,
            downloadURL: URL(string: "https://github.com/router-for-me/CLIProxyAPI/releases/download/\(tag)/\(name)")!,
            architecture: resolvedArchitecture,
            format: .tarGzip,
            sha256: nil
        )
    }
}

struct LiveGitHubReleasesUpdateLoader: AppUpdateReleaseLoading {
    var environment: AppUpdateEnvironmentProviding
    var session: URLSession = .shared

    func loadLatestRelease() async throws -> AppUpdateRelease {
        guard let releasesURL = self.environment.githubReleasesURL else {
            throw AppUpdateError.missingReleasesURL
        }

        var request = URLRequest(url: releasesURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Codexkit", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await self.session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppUpdateError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 403 || httpResponse.statusCode == 429 {
                return try await self.loadLatestReleaseFromReleasePageFallback()
            }
            throw AppUpdateError.unexpectedStatusCode(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let releases: [GitHubReleaseIndexEntry]

        do {
            releases = try decoder.decode([GitHubReleaseIndexEntry].self, from: data)
        } catch {
            throw AppUpdateError.invalidResponse
        }

        guard let release = GitHubReleaseAdapter.firstInstallableStableRelease(from: releases) else {
            throw AppUpdateError.noInstallableStableRelease
        }

        return release
    }

    private func loadLatestReleaseFromReleasePageFallback() async throws -> AppUpdateRelease {
        var request = URLRequest(url: hardcodedCodexkitLatestReleasePageURL)
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.setValue("Codexkit", forHTTPHeaderField: "User-Agent")

        let (_, response) = try await self.session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppUpdateError.invalidResponse
        }
        guard (200...399).contains(httpResponse.statusCode) else {
            throw AppUpdateError.unexpectedStatusCode(httpResponse.statusCode)
        }

        let resolvedURL = self.resolvedLatestReleaseURL(from: httpResponse)
        guard let tag = Self.releaseTag(from: resolvedURL) else {
            throw AppUpdateError.invalidResponse
        }

        return try Self.fallbackRelease(tag: tag, releaseURL: resolvedURL)
    }

    private func resolvedLatestReleaseURL(from response: HTTPURLResponse) -> URL {
        if let responseURL = response.url,
           Self.releaseTag(from: responseURL) != nil {
            return responseURL
        }
        if let location = response.value(forHTTPHeaderField: "Location"),
           let locationURL = URL(string: location),
           Self.releaseTag(from: locationURL) != nil {
            return locationURL
        }
        return hardcodedCodexkitLatestReleasePageURL
    }

    private static func releaseTag(from url: URL) -> String? {
        let components = url.pathComponents
        guard let tagIndex = components.firstIndex(of: "tag"),
              components.index(after: tagIndex) < components.endIndex else {
            return nil
        }

        let tag = components[components.index(after: tagIndex)]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return tag.isEmpty ? nil : tag
    }

    private static func fallbackRelease(tag: String, releaseURL: URL) throws -> AppUpdateRelease {
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              AppSemanticVersion(version) != nil else {
            throw AppUpdateError.invalidReleaseVersion(tag)
        }

        let downloadBaseURL = URL(string: "https://github.com/Lcc1ccl/Codexkit/releases/download/\(tag)/")!
        let artifacts: [AppUpdateArtifact] = [
            Self.fallbackArtifact(
                version: version,
                architecture: .arm64,
                format: .dmg,
                downloadBaseURL: downloadBaseURL
            ),
            Self.fallbackArtifact(
                version: version,
                architecture: .arm64,
                format: .zip,
                downloadBaseURL: downloadBaseURL
            ),
            Self.fallbackArtifact(
                version: version,
                architecture: .x86_64,
                format: .dmg,
                downloadBaseURL: downloadBaseURL
            ),
            Self.fallbackArtifact(
                version: version,
                architecture: .x86_64,
                format: .zip,
                downloadBaseURL: downloadBaseURL
            ),
        ]

        return AppUpdateRelease(
            version: version,
            publishedAt: nil,
            summary: nil,
            releaseNotesURL: releaseURL,
            downloadPageURL: releaseURL,
            deliveryMode: .automatic,
            minimumAutomaticUpdateVersion: nil,
            artifacts: artifacts
        )
    }

    private static func fallbackArtifact(
        version: String,
        architecture: UpdateArtifactArchitecture,
        format: UpdateArtifactFormat,
        downloadBaseURL: URL
    ) -> AppUpdateArtifact {
        let filename = "codexkit-\(version)-macOS-\(architecture.rawValue).\(format.rawValue)"
        return AppUpdateArtifact(
            architecture: architecture,
            format: format,
            downloadURL: downloadBaseURL.appendingPathComponent(filename),
            sha256: nil
        )
    }
}

struct LocalCodesignSignatureInspector: AppSignatureInspecting {
    func inspect(bundleURL: URL) -> AppSignatureInspection {
        let output = Self.captureOutput(
            launchPath: "/usr/bin/codesign",
            arguments: ["-dv", "--verbose=4", bundleURL.path]
        )

        let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedOutput.isEmpty == false else {
            return AppSignatureInspection(
                hasUsableSignature: false,
                summary: L.updateSignatureUnknown
            )
        }

        let lines = trimmedOutput.split(separator: "\n").map(String.init)
        let signatureLine = lines.first(where: { $0.hasPrefix("Signature=") }) ?? "Signature=unknown"
        let teamLine = lines.first(where: { $0.hasPrefix("TeamIdentifier=") }) ?? "TeamIdentifier=unknown"
        let summary = "\(signatureLine); \(teamLine)"
        let isAdHoc = signatureLine.localizedCaseInsensitiveContains("adhoc")
        let teamMissing = teamLine.localizedCaseInsensitiveContains("not set")

        return AppSignatureInspection(
            hasUsableSignature: isAdHoc == false && teamMissing == false,
            summary: summary
        )
    }

    fileprivate static func captureOutput(
        launchPath: String,
        arguments: [String]
    ) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: launchPath)
        task.arguments = arguments

        let outputPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = outputPipe

        do {
            try task.run()
            task.waitUntilExit()
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return error.localizedDescription
        }
    }
}

struct LocalGatekeeperInspector: AppGatekeeperInspecting {
    func inspect(bundleURL: URL) -> AppGatekeeperInspection {
        let output = LocalCodesignSignatureInspector.captureOutput(
            launchPath: "/usr/sbin/spctl",
            arguments: ["-a", "-vv", bundleURL.path]
        )

        let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedOutput.isEmpty == false else {
            return AppGatekeeperInspection(
                passesAssessment: false,
                summary: L.updateSignatureUnknown
            )
        }

        let passesAssessment = trimmedOutput.localizedCaseInsensitiveContains("accepted")
            && trimmedOutput.localizedCaseInsensitiveContains("no usable signature") == false
        let summary = trimmedOutput.split(separator: "\n").prefix(2).joined(separator: " | ")

        return AppGatekeeperInspection(
            passesAssessment: passesAssessment,
            summary: summary
        )
    }
}

struct DefaultAppUpdateCapabilityEvaluator: AppUpdateCapabilityEvaluating {
    var signatureInspector: AppSignatureInspecting
    var gatekeeperInspector: AppGatekeeperInspecting
    var automaticUpdaterAvailable: Bool

    func blockers(
        for release: AppUpdateRelease,
        environment: AppUpdateEnvironmentProviding
    ) -> [AppUpdateBlocker] {
        var blockers: [AppUpdateBlocker] = []

        if release.deliveryMode == .guidedDownload {
            blockers.append(.guidedDownloadOnlyRelease)
        }

        if let minimumAutomaticUpdateVersion = release.minimumAutomaticUpdateVersion,
           let currentVersion = AppSemanticVersion(environment.currentVersion),
           let minimumVersion = AppSemanticVersion(minimumAutomaticUpdateVersion),
           currentVersion < minimumVersion {
            blockers.append(
                .bootstrapRequired(
                    currentVersion: environment.currentVersion,
                    minimumAutomaticVersion: minimumAutomaticUpdateVersion
                )
            )
        }

        if self.automaticUpdaterAvailable == false {
            blockers.append(.automaticUpdaterUnavailable)
        }

        let signatureInspection = self.signatureInspector.inspect(bundleURL: environment.bundleURL)
        if signatureInspection.hasUsableSignature == false {
            blockers.append(.missingTrustedSignature(summary: signatureInspection.summary))
        }

        let gatekeeperInspection = self.gatekeeperInspector.inspect(bundleURL: environment.bundleURL)
        if gatekeeperInspection.passesAssessment == false {
            blockers.append(.failingGatekeeperAssessment(summary: gatekeeperInspection.summary))
        }

        let installLocation = Self.installLocation(for: environment.bundleURL)
        if installLocation == .other {
            blockers.append(.unsupportedInstallLocation(installLocation))
        }

        return blockers
    }

    static func installLocation(for bundleURL: URL) -> UpdateInstallLocation {
        let standardizedPath = bundleURL.standardizedFileURL.path
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
        let userApplications = URL(fileURLWithPath: homeDirectory, isDirectory: true)
            .appendingPathComponent("Applications", isDirectory: true)
            .path

        if standardizedPath.hasPrefix("/Applications/") || standardizedPath == "/Applications" {
            return .applications
        }
        if standardizedPath.hasPrefix(userApplications + "/") || standardizedPath == userApplications {
            return .userApplications
        }
        return .other
    }
}

enum AppUpdateArtifactSelector {
    static func selectArtifact(
        for architecture: UpdateArtifactArchitecture,
        artifacts: [AppUpdateArtifact]
    ) throws -> AppUpdateArtifact {
        let architecturePreference: [UpdateArtifactArchitecture]
        switch architecture {
        case .arm64:
            architecturePreference = [.arm64, .universal]
        case .x86_64:
            architecturePreference = [.x86_64, .universal]
        case .universal:
            architecturePreference = [.universal, .arm64, .x86_64]
        }

        let formatPreference: [UpdateArtifactFormat] = [.dmg, .zip]

        for preferredFormat in formatPreference {
            for preferredArchitecture in architecturePreference {
                if let artifact = artifacts.first(where: {
                    $0.architecture == preferredArchitecture && $0.format == preferredFormat
                }) {
                    return artifact
                }
            }
        }

        throw AppUpdateError.noCompatibleArtifact(architecture)
    }
}

struct LiveAppUpdateActionExecutor: AppUpdateActionExecuting {
    var session: URLSession = .shared
    var fileManager: FileManager = .default
    var currentBundleURL: URL = Bundle.main.bundleURL
    var updateRootURL: URL = CodexPaths.codexBarRoot.appendingPathComponent("app-updates", isDirectory: true)
    var relauncher: AppUpdateRelaunching = SystemAppUpdateRelauncher()

    func execute(_ availability: AppUpdateAvailability) async throws {
        let installedAppURL = try await self.install(availability)
        try self.relauncher.relaunch(appURL: installedAppURL)
    }

    @discardableResult
    func install(_ availability: AppUpdateAvailability) async throws -> URL {
        try self.fileManager.createDirectory(at: self.updateRootURL, withIntermediateDirectories: true)

        let downloadedArtifactURL = try await self.download(availability.selectedArtifact, version: availability.release.version)
        let stagedAppURL = try self.stageApp(
            artifact: availability.selectedArtifact,
            downloadedArtifactURL: downloadedArtifactURL,
            version: availability.release.version
        )
        return try self.replaceCurrentApp(with: stagedAppURL)
    }

    private func download(
        _ artifact: AppUpdateArtifact,
        version: String
    ) async throws -> URL {
        let safeVersion = Self.safePathComponent(version)
        let downloadDirectoryURL = self.updateRootURL
            .appendingPathComponent("downloads", isDirectory: true)
            .appendingPathComponent(safeVersion, isDirectory: true)
        try self.fileManager.createDirectory(at: downloadDirectoryURL, withIntermediateDirectories: true)

        let fileName = artifact.downloadURL.lastPathComponent.isEmpty
            ? "codexkit-\(safeVersion).\(artifact.format.rawValue)"
            : artifact.downloadURL.lastPathComponent
        let downloadedArtifactURL = downloadDirectoryURL
            .appendingPathComponent(Self.safePathComponent(fileName))

        let (data, response) = try await self.session.data(from: artifact.downloadURL)
        if let http = response as? HTTPURLResponse,
           (200...299).contains(http.statusCode) == false {
            throw NSError(
                domain: "CodexkitAppUpdate",
                code: http.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey: "Codexkit update artifact download failed with status code \(http.statusCode).",
                ]
            )
        }

        if let expectedSHA256 = artifact.sha256?.trimmingCharacters(in: .whitespacesAndNewlines),
           expectedSHA256.isEmpty == false {
            let actualSHA256 = Self.sha256Hex(data)
            guard actualSHA256.caseInsensitiveCompare(expectedSHA256) == .orderedSame else {
                throw NSError(
                    domain: "CodexkitAppUpdate",
                    code: 1001,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Codexkit update artifact checksum mismatch.",
                    ]
                )
            }
        }

        try data.write(to: downloadedArtifactURL, options: .atomic)
        return downloadedArtifactURL
    }

    private func stageApp(
        artifact: AppUpdateArtifact,
        downloadedArtifactURL: URL,
        version: String
    ) throws -> URL {
        let stagingRootURL = self.updateRootURL
            .appendingPathComponent("staged", isDirectory: true)
            .appendingPathComponent("\(Self.safePathComponent(version))-\(UUID().uuidString)", isDirectory: true)
        try self.fileManager.createDirectory(at: stagingRootURL, withIntermediateDirectories: true)

        switch artifact.format {
        case .zip:
            try self.runTool(
                executablePath: "/usr/bin/ditto",
                arguments: ["-x", "-k", downloadedArtifactURL.path, stagingRootURL.path]
            )
            return try self.findAppBundle(in: stagingRootURL)
        case .dmg:
            return try self.stageAppFromDMG(
                downloadedArtifactURL: downloadedArtifactURL,
                stagingRootURL: stagingRootURL
            )
        }
    }

    private func stageAppFromDMG(
        downloadedArtifactURL: URL,
        stagingRootURL: URL
    ) throws -> URL {
        let mountURL = self.updateRootURL
            .appendingPathComponent("mounts", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try self.fileManager.createDirectory(at: mountURL, withIntermediateDirectories: true)

        var didAttach = false
        defer {
            if didAttach {
                try? self.runTool(
                    executablePath: "/usr/bin/hdiutil",
                    arguments: ["detach", mountURL.path, "-quiet"]
                )
            }
            try? self.fileManager.removeItem(at: mountURL)
        }

        do {
            try self.runTool(
                executablePath: "/usr/bin/hdiutil",
                arguments: ["attach", downloadedArtifactURL.path, "-nobrowse", "-readonly", "-mountpoint", mountURL.path]
            )
            didAttach = true
            let mountedAppURL = try self.findAppBundle(in: mountURL)
            let copiedAppURL = stagingRootURL.appendingPathComponent(mountedAppURL.lastPathComponent, isDirectory: true)
            if self.fileManager.fileExists(atPath: copiedAppURL.path) {
                try self.fileManager.removeItem(at: copiedAppURL)
            }
            try self.fileManager.copyItem(at: mountedAppURL, to: copiedAppURL)
            return copiedAppURL
        } catch {
            throw error
        }
    }

    private func replaceCurrentApp(with stagedAppURL: URL) throws -> URL {
        let targetAppURL = self.currentBundleURL.standardizedFileURL
        guard targetAppURL.pathExtension.lowercased() == "app" else {
            throw NSError(
                domain: "CodexkitAppUpdate",
                code: 1002,
                userInfo: [
                    NSLocalizedDescriptionKey: "Codexkit is not currently running from an app bundle.",
                ]
            )
        }

        guard self.fileManager.fileExists(atPath: stagedAppURL.appendingPathComponent("Contents", isDirectory: true).path) else {
            throw NSError(
                domain: "CodexkitAppUpdate",
                code: 1003,
                userInfo: [
                    NSLocalizedDescriptionKey: "Codexkit update artifact did not contain a valid app bundle.",
                ]
            )
        }

        let parentURL = targetAppURL.deletingLastPathComponent()
        try self.fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
        let transactionID = UUID().uuidString
        let installingURL = parentURL
            .appendingPathComponent(".\(targetAppURL.lastPathComponent).installing-\(transactionID)", isDirectory: true)
        let backupURL = parentURL
            .appendingPathComponent(".\(targetAppURL.lastPathComponent).backup-\(transactionID)", isDirectory: true)

        if self.fileManager.fileExists(atPath: installingURL.path) {
            try self.fileManager.removeItem(at: installingURL)
        }
        try self.fileManager.copyItem(at: stagedAppURL, to: installingURL)

        do {
            if self.fileManager.fileExists(atPath: targetAppURL.path) {
                try self.fileManager.moveItem(at: targetAppURL, to: backupURL)
            }
            try self.fileManager.moveItem(at: installingURL, to: targetAppURL)
            if self.fileManager.fileExists(atPath: backupURL.path) {
                try self.fileManager.removeItem(at: backupURL)
            }
            return targetAppURL
        } catch {
            if self.fileManager.fileExists(atPath: targetAppURL.path) == false,
               self.fileManager.fileExists(atPath: backupURL.path) {
                try? self.fileManager.moveItem(at: backupURL, to: targetAppURL)
            }
            if self.fileManager.fileExists(atPath: installingURL.path) {
                try? self.fileManager.removeItem(at: installingURL)
            }
            throw error
        }
    }

    private func findAppBundle(in rootURL: URL) throws -> URL {
        if let directMatch = try self.fileManager
            .contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension.lowercased() == "app" }) {
            return directMatch
        }

        let enumerator = self.fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        while let candidate = enumerator?.nextObject() as? URL {
            if candidate.pathExtension.lowercased() == "app" {
                return candidate
            }
        }

        throw NSError(
            domain: "CodexkitAppUpdate",
            code: 1004,
            userInfo: [
                NSLocalizedDescriptionKey: "Codexkit update artifact did not contain a .app bundle.",
            ]
        )
    }

    private func runTool(
        executablePath: String,
        arguments: [String]
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(
                domain: "CodexkitAppUpdate",
                code: Int(process.terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey: output?.isEmpty == false
                        ? output!
                        : "Update tool \(executablePath) failed with status \(process.terminationStatus).",
                ]
            )
        }
    }

    private static func safePathComponent(_ value: String) -> String {
        let safe = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return safe.isEmpty ? UUID().uuidString : safe
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private struct SystemAppUpdateRelauncher: AppUpdateRelaunching {
    func relaunch(appURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "sleep 0.5; /usr/bin/open -n \"$1\"",
            "codexkit-relaunch",
            appURL.path,
        ]
        try process.run()
        NSApp.terminate(nil)
    }
}

struct LiveCLIProxyAPIUpdateActionExecutor: CLIProxyAPIUpdateActionExecuting {
    var service: CLIProxyAPIService = .shared
    var restoreRuntimeAfterInstall: @MainActor () -> Bool = {
        let settings = TokenStore.shared.config.desktop.cliProxyAPI
        guard settings.enabled else { return false }
        return CLIProxyAPIRuntimeController.shared.applyConfiguration(settings)
    }

    func execute(_ availability: CLIProxyAPIUpdateAvailability) async throws {
        guard let artifact = availability.release.artifact else {
            throw AppUpdateError.noCompatibleArtifact(LiveAppUpdateEnvironment().architecture)
        }
        _ = try await self.service.installManagedRuntime(
            version: availability.release.version,
            artifact: artifact
        )
        _ = await self.restoreRuntimeAfterInstall()
    }
}

@MainActor
final class UpdateCoordinator: ObservableObject {
    static let shared = UpdateCoordinator()

    @Published private(set) var state: UpdateCoordinatorState = .idle
    @Published private(set) var pendingAvailability: AppUpdateAvailability?
    @Published private(set) var cliProxyAPIState: CLIProxyAPIUpdateState = .idle
    @Published private(set) var cliProxyAPIPendingAvailability: CLIProxyAPIUpdateAvailability?

    private let releaseLoader: AppUpdateReleaseLoading
    private let environment: AppUpdateEnvironmentProviding
    private let capabilityEvaluator: AppUpdateCapabilityEvaluating
    private let actionExecutor: AppUpdateActionExecuting
    private let cliProxyAPIInstalledVersionProvider: CLIProxyAPIInstalledVersionProviding
    private let cliProxyAPIReleaseLoader: CLIProxyAPIReleaseLoading
    private let cliProxyAPIActionExecutor: CLIProxyAPIUpdateActionExecuting
    private let automaticCheckScheduler: AppUpdateAutomaticCheckScheduling
    private let desktopSettingsProvider: @MainActor () -> CodexBarDesktopSettings

    private var hasStarted = false
    private var codexkitAutomaticCheckHandle: AppUpdateAutomaticCheckCancelling?
    private var cliProxyAPIAutomaticCheckHandle: AppUpdateAutomaticCheckCancelling?

    convenience init() {
        let environment = LiveAppUpdateEnvironment()
        self.init(
            releaseLoader: LiveGitHubReleasesUpdateLoader(environment: environment),
            environment: environment,
            capabilityEvaluator: DefaultAppUpdateCapabilityEvaluator(
                signatureInspector: LocalCodesignSignatureInspector(),
                gatekeeperInspector: LocalGatekeeperInspector(),
                automaticUpdaterAvailable: true
            ),
            actionExecutor: LiveAppUpdateActionExecutor(),
            cliProxyAPIInstalledVersionProvider: LocalCLIProxyAPIInstalledVersionProvider(),
            cliProxyAPIReleaseLoader: LiveCLIProxyAPIReleaseLoader(),
            cliProxyAPIActionExecutor: LiveCLIProxyAPIUpdateActionExecutor(),
            automaticCheckScheduler: TaskBasedAutomaticCheckScheduler(),
            desktopSettingsProvider: { TokenStore.shared.config.desktop }
        )
    }

    convenience init(
        releaseLoader: AppUpdateReleaseLoading,
        environment: AppUpdateEnvironmentProviding,
        capabilityEvaluator: AppUpdateCapabilityEvaluating,
        actionExecutor: AppUpdateActionExecuting
    ) {
        self.init(
            releaseLoader: releaseLoader,
            environment: environment,
            capabilityEvaluator: capabilityEvaluator,
            actionExecutor: actionExecutor,
            cliProxyAPIInstalledVersionProvider: LocalCLIProxyAPIInstalledVersionProvider(),
            cliProxyAPIReleaseLoader: LiveCLIProxyAPIReleaseLoader(),
            cliProxyAPIActionExecutor: LiveCLIProxyAPIUpdateActionExecutor(),
            automaticCheckScheduler: TaskBasedAutomaticCheckScheduler(),
            desktopSettingsProvider: { TokenStore.shared.config.desktop }
        )
    }

    init(
        releaseLoader: AppUpdateReleaseLoading,
        environment: AppUpdateEnvironmentProviding,
        capabilityEvaluator: AppUpdateCapabilityEvaluating,
        actionExecutor: AppUpdateActionExecuting,
        cliProxyAPIInstalledVersionProvider: CLIProxyAPIInstalledVersionProviding,
        cliProxyAPIReleaseLoader: CLIProxyAPIReleaseLoading,
        cliProxyAPIActionExecutor: CLIProxyAPIUpdateActionExecuting,
        automaticCheckScheduler: AppUpdateAutomaticCheckScheduling,
        desktopSettingsProvider: @escaping @MainActor () -> CodexBarDesktopSettings
    ) {
        self.releaseLoader = releaseLoader
        self.environment = environment
        self.capabilityEvaluator = capabilityEvaluator
        self.actionExecutor = actionExecutor
        self.cliProxyAPIInstalledVersionProvider = cliProxyAPIInstalledVersionProvider
        self.cliProxyAPIReleaseLoader = cliProxyAPIReleaseLoader
        self.cliProxyAPIActionExecutor = cliProxyAPIActionExecutor
        self.automaticCheckScheduler = automaticCheckScheduler
        self.desktopSettingsProvider = desktopSettingsProvider
    }

    var isChecking: Bool {
        if case .checking = self.state {
            return true
        }
        return false
    }

    var isCheckingCLIProxyAPIUpdates: Bool {
        if case .checking = self.cliProxyAPIState {
            return true
        }
        return false
    }

    func start() {
        guard self.hasStarted == false else { return }
        self.hasStarted = true
        self.configureAutomaticChecks()
    }

    func reloadSettings() {
        guard self.hasStarted else { return }
        self.configureAutomaticChecks()
    }

    func stop() {
        self.codexkitAutomaticCheckHandle?.cancel()
        self.codexkitAutomaticCheckHandle = nil
        self.cliProxyAPIAutomaticCheckHandle?.cancel()
        self.cliProxyAPIAutomaticCheckHandle = nil
        self.hasStarted = false
    }

    func handleToolbarAction() async {
        if let pendingAvailability = self.pendingAvailability {
            await self.execute(pendingAvailability)
        } else {
            await self.checkForUpdates(trigger: .manual)
        }
    }

    func handleCLIProxyAPIAction() async {
        if let pendingAvailability = self.cliProxyAPIPendingAvailability {
            await self.executeCLIProxyAPIUpdate(pendingAvailability)
        } else {
            await self.checkCLIProxyAPIForUpdates(trigger: .manual)
        }
    }

    func checkForUpdates(trigger: UpdateCheckTrigger) async {
        guard self.isChecking == false else { return }

        self.state = .checking(trigger)

        do {
            let release = try await self.releaseLoader.loadLatestRelease()
            if let availability = try self.resolveAvailability(from: release) {
                self.pendingAvailability = availability
                self.state = .updateAvailable(availability)
                if trigger != .manual,
                   self.desktopSettingsProvider().codexkitUpdate.automaticallyInstallsUpdates {
                    await self.execute(availability)
                }
            } else {
                self.pendingAvailability = nil
                self.state = .upToDate(
                    currentVersion: self.environment.currentVersion,
                    checkedVersion: release.version
                )
            }
        } catch {
            let message = error.localizedDescription
            self.state = .failed(message)
        }
    }

    func checkCLIProxyAPIForUpdates(trigger: UpdateCheckTrigger) async {
        guard self.isCheckingCLIProxyAPIUpdates == false else { return }

        self.cliProxyAPIState = .checking(trigger)

        do {
            let installedVersion = self.cliProxyAPIInstalledVersionProvider.resolveInstalledVersion()
            let release = try await self.cliProxyAPIReleaseLoader.loadLatestRelease()
            if let availability = try self.resolveCLIProxyAPIAvailability(
                installedVersion: installedVersion,
                release: release
            ) {
                self.cliProxyAPIPendingAvailability = availability
                self.cliProxyAPIState = .updateAvailable(availability)
                if trigger != .manual,
                   self.desktopSettingsProvider().cliProxyAPIUpdate.automaticallyInstallsUpdates {
                    await self.executeCLIProxyAPIUpdate(availability)
                }
            } else {
                self.cliProxyAPIPendingAvailability = nil
                self.cliProxyAPIState = .upToDate(
                    installedVersion: installedVersion,
                    checkedVersion: release.version
                )
            }
        } catch {
            self.cliProxyAPIPendingAvailability = nil
            self.cliProxyAPIState = .failed(error.localizedDescription)
        }
    }

    private func configureAutomaticChecks() {
        self.codexkitAutomaticCheckHandle?.cancel()
        self.codexkitAutomaticCheckHandle = nil
        self.cliProxyAPIAutomaticCheckHandle?.cancel()
        self.cliProxyAPIAutomaticCheckHandle = nil

        let desktopSettings = self.desktopSettingsProvider()

        if desktopSettings.codexkitUpdate.automaticallyChecksForUpdates {
            self.codexkitAutomaticCheckHandle = self.automaticCheckScheduler.scheduleRepeating(
                every: desktopSettings.codexkitUpdate.checkSchedule.interval
            ) { [weak self] in
                guard let self else { return }
                await self.checkForUpdates(trigger: .automaticDaily)
            }

            Task {
                await self.checkForUpdates(trigger: .automaticStartup)
            }
        }

        if desktopSettings.cliProxyAPIUpdate.automaticallyChecksForUpdates {
            self.cliProxyAPIAutomaticCheckHandle = self.automaticCheckScheduler.scheduleRepeating(
                every: desktopSettings.cliProxyAPIUpdate.checkSchedule.interval
            ) { [weak self] in
                guard let self else { return }
                await self.checkCLIProxyAPIForUpdates(trigger: .automaticDaily)
            }

            Task {
                await self.checkCLIProxyAPIForUpdates(trigger: .automaticStartup)
            }
        }
    }

    private func resolveAvailability(from release: AppUpdateRelease) throws -> AppUpdateAvailability? {
        guard let currentVersion = AppSemanticVersion(self.environment.currentVersion) else {
            throw AppUpdateError.invalidCurrentVersion(self.environment.currentVersion)
        }
        guard let releaseVersion = AppSemanticVersion(release.version) else {
            throw AppUpdateError.invalidReleaseVersion(release.version)
        }
        guard currentVersion < releaseVersion else {
            return nil
        }

        let selectedArtifact = try AppUpdateArtifactSelector.selectArtifact(
            for: self.environment.architecture,
            artifacts: release.artifacts
        )

        return AppUpdateAvailability(
            currentVersion: self.environment.currentVersion,
            release: release,
            selectedArtifact: selectedArtifact,
            blockers: self.capabilityEvaluator.blockers(
                for: release,
                environment: self.environment
            )
        )
    }

    private func resolveCLIProxyAPIAvailability(
        installedVersion: String,
        release: CLIProxyAPIUpdateRelease
    ) throws -> CLIProxyAPIUpdateAvailability? {
        if let installedSemanticVersion = AppSemanticVersion(installedVersion),
           let releaseSemanticVersion = AppSemanticVersion(release.version) {
            guard installedSemanticVersion < releaseSemanticVersion else {
                return nil
            }
        } else if installedVersion == release.version {
            return nil
        }

        guard release.artifact != nil else {
            throw AppUpdateError.noCompatibleArtifact(self.environment.architecture)
        }

        return CLIProxyAPIUpdateAvailability(
            installedVersion: installedVersion,
            release: release
        )
    }

    private func execute(_ availability: AppUpdateAvailability) async {
        self.state = .executing(availability)

        do {
            try await self.actionExecutor.execute(availability)
            self.pendingAvailability = availability
            self.state = .updateAvailable(availability)
        } catch {
            let message = error.localizedDescription
            self.state = .failed(message)
        }
    }

    private func executeCLIProxyAPIUpdate(_ availability: CLIProxyAPIUpdateAvailability) async {
        self.cliProxyAPIState = .executing(availability)

        do {
            try await self.cliProxyAPIActionExecutor.execute(availability)
            self.cliProxyAPIPendingAvailability = nil
            self.cliProxyAPIState = .upToDate(
                installedVersion: availability.release.version,
                checkedVersion: availability.release.version
            )
        } catch {
            self.cliProxyAPIState = .failed(error.localizedDescription)
        }
    }
}

private extension UpdateArtifactArchitecture {
    var displayName: String {
        switch self {
        case .arm64:
            return "Apple Silicon"
        case .x86_64:
            return "Intel"
        case .universal:
            return L.updateArchitectureUniversal
        }
    }
}
