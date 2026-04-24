import AppKit
import Combine
import Foundation

private let hardcodedCodexkitReleasesURL = URL(string: "https://api.github.com/repos/lcc-project/Codexkit/releases")!
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

struct CLIProxyAPIUpdateRelease: Equatable {
    var version: String
    var releasePageURL: URL
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

struct LiveCLIProxyAPIReleaseLoader: CLIProxyAPIReleaseLoading {
    var session: URLSession = .shared

    private struct ReleaseInfo: Decodable {
        var tagName: String
        var htmlURL: URL?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
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

        return CLIProxyAPIUpdateRelease(
            version: version,
            releasePageURL: releaseInfo.htmlURL ?? hardcodedCLIProxyAPIReleasePageURL
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
    func execute(_ availability: AppUpdateAvailability) async throws {
        guard availability.isAutomaticUpdateAllowed == false else {
            throw AppUpdateError.automaticUpdateUnavailable
        }

        guard NSWorkspace.shared.open(availability.selectedArtifact.downloadURL) else {
            throw AppUpdateError.failedToOpenDownloadURL(availability.selectedArtifact.downloadURL)
        }
    }
}

struct LiveCLIProxyAPIUpdateActionExecutor: CLIProxyAPIUpdateActionExecuting {
    func execute(_ availability: CLIProxyAPIUpdateAvailability) async throws {
        guard NSWorkspace.shared.open(availability.release.releasePageURL) else {
            throw AppUpdateError.failedToOpenDownloadURL(availability.release.releasePageURL)
        }
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
                automaticUpdaterAvailable: false
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
            if let availability = self.resolveCLIProxyAPIAvailability(
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
    ) -> CLIProxyAPIUpdateAvailability? {
        if let installedSemanticVersion = AppSemanticVersion(installedVersion),
           let releaseSemanticVersion = AppSemanticVersion(release.version) {
            guard installedSemanticVersion < releaseSemanticVersion else {
                return nil
            }
        } else if installedVersion == release.version {
            return nil
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
            self.cliProxyAPIPendingAvailability = availability
            self.cliProxyAPIState = .updateAvailable(availability)
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
