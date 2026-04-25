import Foundation
import XCTest
@testable import CodexkitApp

@MainActor
final class UpdateCoordinatorTests: CodexBarTestCase {
    func testManualCheckStoresAvailableUpdateWithoutExecuting() async {
        let releaseLoader = MockReleaseLoader(release: self.makeRelease(version: "1.1.7"))
        let executor = MockUpdateExecutor()

        let coordinator = UpdateCoordinator(
            releaseLoader: releaseLoader,
            environment: MockUpdateEnvironment(
                currentVersion: "1.1.5",
                architecture: .arm64
            ),
            capabilityEvaluator: MockCapabilityEvaluator(
                blockers: [.guidedDownloadOnlyRelease]
            ),
            actionExecutor: executor
        )

        await coordinator.checkForUpdates(trigger: .manual)

        XCTAssertEqual(releaseLoader.loadCount, 1)
        XCTAssertTrue(executor.executed.isEmpty)
        XCTAssertEqual(coordinator.pendingAvailability?.release.version, "1.1.7")

        guard case let .updateAvailable(availability) = coordinator.state else {
            return XCTFail("Expected updateAvailable state")
        }
        XCTAssertEqual(availability.release.version, "1.1.7")
    }

    func testToolbarActionExecutesPendingUpdateWithoutRefetching() async {
        let releaseLoader = MockReleaseLoader(release: self.makeRelease(version: "1.1.7"))
        let executor = MockUpdateExecutor()

        let coordinator = UpdateCoordinator(
            releaseLoader: releaseLoader,
            environment: MockUpdateEnvironment(
                currentVersion: "1.1.5",
                architecture: .arm64
            ),
            capabilityEvaluator: MockCapabilityEvaluator(
                blockers: [.guidedDownloadOnlyRelease]
            ),
            actionExecutor: executor
        )

        await coordinator.checkForUpdates(trigger: .manual)
        releaseLoader.release = self.makeRelease(version: "1.1.5")

        await coordinator.handleToolbarAction()

        XCTAssertEqual(releaseLoader.loadCount, 1)
        XCTAssertEqual(executor.executed.count, 1)
        XCTAssertEqual(executor.executed.first?.release.version, "1.1.7")
        XCTAssertEqual(coordinator.pendingAvailability?.release.version, "1.1.7")
    }

    func testAutomaticAndManualChecksUseSameReleaseResolution() async {
        let releaseLoader = MockReleaseLoader(release: self.makeRelease(version: "1.1.7"))

        let coordinator = UpdateCoordinator(
            releaseLoader: releaseLoader,
            environment: MockUpdateEnvironment(
                currentVersion: "1.1.5",
                architecture: .x86_64
            ),
            capabilityEvaluator: MockCapabilityEvaluator(
                blockers: [.guidedDownloadOnlyRelease]
            ),
            actionExecutor: MockUpdateExecutor()
        )

        await coordinator.checkForUpdates(trigger: .automaticStartup)
        await coordinator.checkForUpdates(trigger: .manual)

        XCTAssertEqual(releaseLoader.loadCount, 2)
        XCTAssertEqual(coordinator.pendingAvailability?.release.version, "1.1.7")
        XCTAssertEqual(coordinator.pendingAvailability?.selectedArtifact.architecture, .x86_64)
    }

    func testStartSchedulesDailyAutomaticChecks() async {
        let scheduler = MockAutomaticCheckScheduler()
        let releaseLoader = MockReleaseLoader(release: self.makeRelease(version: "1.1.7"))

        let coordinator = UpdateCoordinator(
            releaseLoader: releaseLoader,
            environment: MockUpdateEnvironment(
                currentVersion: "1.1.5",
                architecture: .arm64
            ),
            capabilityEvaluator: MockCapabilityEvaluator(
                blockers: [.guidedDownloadOnlyRelease]
            ),
            actionExecutor: MockUpdateExecutor(),
            cliProxyAPIInstalledVersionProvider: MockCLIProxyAPIInstalledVersionProvider(installedVersion: "v0.9.0"),
            cliProxyAPIReleaseLoader: MockCLIProxyAPIReleaseLoader(
                release: CLIProxyAPIUpdateRelease(
                    version: "v1.0.0",
                    releasePageURL: URL(string: "https://example.com/cliproxyapi")!
                )
            ),
            cliProxyAPIActionExecutor: MockCLIProxyAPIUpdateExecutor(),
            automaticCheckScheduler: scheduler,
            desktopSettingsProvider: {
                var settings = CodexBarDesktopSettings()
                settings.codexkitUpdate = .init(
                    automaticallyChecksForUpdates: true,
                    automaticallyInstallsUpdates: false,
                    checkSchedule: .daily
                )
                settings.cliProxyAPIUpdate = .init(
                    automaticallyChecksForUpdates: false,
                    automaticallyInstallsUpdates: false,
                    checkSchedule: .daily
                )
                return settings
            }
        )

        coordinator.start()
        await scheduler.waitUntilScheduled()
        while releaseLoader.loadCount < 1 {
            await Task.yield()
        }
        XCTAssertEqual(scheduler.scheduledIntervals, [CodexBarUpdateCheckSchedule.daily.interval])

        await scheduler.fire()
        while releaseLoader.loadCount < 2 {
            await Task.yield()
        }

        XCTAssertEqual(releaseLoader.loadCount, 2)
        XCTAssertEqual(coordinator.pendingAvailability?.release.version, "1.1.7")
    }

    func testStartSkipsSchedulingWhenAutomaticChecksDisabled() async {
        let scheduler = MockAutomaticCheckScheduler()
        let releaseLoader = MockReleaseLoader(release: self.makeRelease(version: "1.1.7"))

        let coordinator = UpdateCoordinator(
            releaseLoader: releaseLoader,
            environment: MockUpdateEnvironment(
                currentVersion: "1.1.5",
                architecture: .arm64
            ),
            capabilityEvaluator: MockCapabilityEvaluator(blockers: [.guidedDownloadOnlyRelease]),
            actionExecutor: MockUpdateExecutor(),
            cliProxyAPIInstalledVersionProvider: MockCLIProxyAPIInstalledVersionProvider(installedVersion: "v0.9.0"),
            cliProxyAPIReleaseLoader: MockCLIProxyAPIReleaseLoader(
                release: CLIProxyAPIUpdateRelease(
                    version: "v1.0.0",
                    releasePageURL: URL(string: "https://example.com/cliproxyapi")!
                )
            ),
            cliProxyAPIActionExecutor: MockCLIProxyAPIUpdateExecutor(),
            automaticCheckScheduler: scheduler,
            desktopSettingsProvider: {
                var settings = CodexBarDesktopSettings()
                settings.codexkitUpdate.automaticallyChecksForUpdates = false
                settings.cliProxyAPIUpdate.automaticallyChecksForUpdates = false
                return settings
            }
        )

        coordinator.start()
        await Task.yield()

        XCTAssertTrue(scheduler.scheduledIntervals.isEmpty)
        XCTAssertEqual(releaseLoader.loadCount, 0)
    }

    func testAutomaticCheckCanAutoExecuteWhenEnabled() async {
        let releaseLoader = MockReleaseLoader(release: self.makeRelease(version: "1.1.7"))
        let executor = MockUpdateExecutor()

        let coordinator = UpdateCoordinator(
            releaseLoader: releaseLoader,
            environment: MockUpdateEnvironment(
                currentVersion: "1.1.5",
                architecture: .arm64
            ),
            capabilityEvaluator: MockCapabilityEvaluator(blockers: [.guidedDownloadOnlyRelease]),
            actionExecutor: executor,
            cliProxyAPIInstalledVersionProvider: MockCLIProxyAPIInstalledVersionProvider(installedVersion: "v0.9.0"),
            cliProxyAPIReleaseLoader: MockCLIProxyAPIReleaseLoader(
                release: CLIProxyAPIUpdateRelease(
                    version: "v1.0.0",
                    releasePageURL: URL(string: "https://example.com/cliproxyapi")!
                )
            ),
            cliProxyAPIActionExecutor: MockCLIProxyAPIUpdateExecutor(),
            automaticCheckScheduler: MockAutomaticCheckScheduler(),
            desktopSettingsProvider: {
                var settings = CodexBarDesktopSettings()
                settings.codexkitUpdate.automaticallyChecksForUpdates = true
                settings.codexkitUpdate.automaticallyInstallsUpdates = true
                settings.cliProxyAPIUpdate.automaticallyChecksForUpdates = false
                return settings
            }
        )

        await coordinator.checkForUpdates(trigger: .automaticStartup)

        XCTAssertEqual(executor.executed.count, 1)
        XCTAssertEqual(executor.executed.first?.release.version, "1.1.7")
    }

    func testCLIProxyAPIManualCheckStoresAvailableUpdateWithoutExecuting() async {
        let cliReleaseLoader = MockCLIProxyAPIReleaseLoader(
            release: CLIProxyAPIUpdateRelease(
                version: "v1.2.0",
                releasePageURL: URL(string: "https://example.com/cliproxyapi/releases/v1.2.0")!
            )
        )
        let cliExecutor = MockCLIProxyAPIUpdateExecutor()
        let coordinator = UpdateCoordinator(
            releaseLoader: MockReleaseLoader(release: self.makeRelease(version: "1.1.5")),
            environment: MockUpdateEnvironment(
                currentVersion: "1.1.5",
                architecture: .arm64
            ),
            capabilityEvaluator: MockCapabilityEvaluator(blockers: []),
            actionExecutor: MockUpdateExecutor(),
            cliProxyAPIInstalledVersionProvider: MockCLIProxyAPIInstalledVersionProvider(installedVersion: "v1.1.0"),
            cliProxyAPIReleaseLoader: cliReleaseLoader,
            cliProxyAPIActionExecutor: cliExecutor,
            automaticCheckScheduler: MockAutomaticCheckScheduler(),
            desktopSettingsProvider: { CodexBarDesktopSettings() }
        )

        await coordinator.checkCLIProxyAPIForUpdates(trigger: .manual)

        XCTAssertEqual(cliReleaseLoader.loadCount, 1)
        XCTAssertTrue(cliExecutor.executed.isEmpty)
        XCTAssertEqual(coordinator.cliProxyAPIPendingAvailability?.release.version, "v1.2.0")
        guard case let .updateAvailable(availability) = coordinator.cliProxyAPIState else {
            return XCTFail("Expected CLIProxyAPI updateAvailable state")
        }
        XCTAssertEqual(availability.installedVersion, "v1.1.0")
        XCTAssertEqual(availability.release.version, "v1.2.0")
    }

    func testLocalCLIProxyAPIInstalledVersionProviderPrefersManifestVersionWithoutSourceTree() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let bundleRoot = root
            .appendingPathComponent("Codexkit", isDirectory: true)
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("CodexkitApp", isDirectory: true)
            .appendingPathComponent("Bundled", isDirectory: true)
            .appendingPathComponent("CLIProxyAPIServiceBundle", isDirectory: true)
        try FileManager.default.createDirectory(at: bundleRoot, withIntermediateDirectories: true)
        try Data(
            """
            {"source":"forks/CLIProxyAPI","delivery":"bundled-service-binary","version":"v9.9.9","executable_relative_path":"bin/cli-proxy-api-darwin-arm64"}
            """.utf8
        ).write(to: bundleRoot.appendingPathComponent("bundle-manifest.json"))

        let provider = LocalCLIProxyAPIInstalledVersionProvider(
            service: CLIProxyAPIService(currentDirectoryURL: root)
        )

        XCTAssertEqual(provider.resolveInstalledVersion(), "v9.9.9")
    }

    func testLocalCLIProxyAPIInstalledVersionProviderPrefersManagedActiveVersion() throws {
        let service = CLIProxyAPIService()
        let executable = CLIProxyAPIService.managedVersionsDirectoryURL
            .appendingPathComponent("v10.0.0", isDirectory: true)
            .appendingPathComponent("cli-proxy-api")
        try self.writeExecutable(at: executable)
        try service.writeManagedRuntimeDescriptor(
            CLIProxyAPIService.ManagedRuntimeDescriptor(
                version: "v10.0.0",
                executableRelativePath: "versions/v10.0.0/cli-proxy-api",
                artifactName: nil,
                downloadURL: nil,
                installedAt: nil,
                previousVersion: nil,
                previousExecutableRelativePath: nil
            )
        )
        let provider = LocalCLIProxyAPIInstalledVersionProvider(service: service)

        XCTAssertEqual(provider.resolveInstalledVersion(), "v10.0.0")
    }

    func testCLIProxyAPIReleaseLoaderSelectsCompatibleDarwinTarballArtifact() async throws {
        let releasesURL = URL(string: "https://api.github.com/repos/router-for-me/CLIProxyAPI/releases/latest")!
        let session = self.makeMockSession()
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url, releasesURL)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")

            let body = """
            {
              "tag_name": "v6.9.37",
              "html_url": "https://github.com/router-for-me/CLIProxyAPI/releases/tag/v6.9.37",
              "assets": [
                {
                  "name": "CLIProxyAPI_6.9.37_linux_arm64.tar.gz",
                  "browser_download_url": "https://example.com/linux-arm64.tar.gz"
                },
                {
                  "name": "CLIProxyAPI_6.9.37_darwin_amd64.tar.gz",
                  "browser_download_url": "https://example.com/darwin-amd64.tar.gz",
                  "digest": "sha256:aaa111"
                },
                {
                  "name": "CLIProxyAPI_6.9.37_darwin_arm64.tar.gz",
                  "browser_download_url": "https://example.com/darwin-arm64.tar.gz",
                  "digest": "sha256:bbb222"
                }
              ]
            }
            """

            return (
                HTTPURLResponse(url: releasesURL, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(body.utf8)
            )
        }

        let release = try await LiveCLIProxyAPIReleaseLoader(
            session: session,
            architecture: .arm64
        ).loadLatestRelease()

        XCTAssertEqual(release.version, "v6.9.37")
        XCTAssertEqual(release.artifact?.name, "CLIProxyAPI_6.9.37_darwin_arm64.tar.gz")
        XCTAssertEqual(release.artifact?.format, .tarGzip)
        XCTAssertEqual(release.artifact?.architecture, .arm64)
        XCTAssertEqual(release.artifact?.sha256, "bbb222")
    }

    func testCLIProxyAPIUpdateExecutorInstallsTarballIntoManagedRuntime() async throws {
        let artifactURL = URL(string: "https://example.com/CLIProxyAPI_10.0.1_darwin_arm64.tar.gz")!
        let tarballData = try self.makeCLIProxyAPITarball()
        let session = self.makeMockSession()
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url, artifactURL)
            return (
                HTTPURLResponse(url: artifactURL, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                tarballData
            )
        }
        let service = CLIProxyAPIService(session: session)
        let executor = LiveCLIProxyAPIUpdateActionExecutor(service: service)
        let release = CLIProxyAPIUpdateRelease(
            version: "v10.0.1",
            releasePageURL: URL(string: "https://example.com/releases/v10.0.1")!,
            artifact: CLIProxyAPIReleaseArtifact(
                name: "CLIProxyAPI_10.0.1_darwin_arm64.tar.gz",
                downloadURL: artifactURL,
                architecture: .arm64,
                format: .tarGzip,
                sha256: nil
            )
        )
        let availability = CLIProxyAPIUpdateAvailability(
            installedVersion: "v10.0.0",
            release: release
        )

        try await executor.execute(availability)

        let descriptor = try XCTUnwrap(service.resolveManagedRuntimeDescriptor())
        XCTAssertEqual(descriptor.version, "v10.0.1")
        XCTAssertEqual(descriptor.artifactName, "CLIProxyAPI_10.0.1_darwin_arm64.tar.gz")
        XCTAssertEqual(descriptor.previousVersion, nil)
        XCTAssertTrue(descriptor.executableRelativePath.hasPrefix("versions/"))
        XCTAssertEqual(service.managedExecutableURL()?.lastPathComponent, "cli-proxy-api")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: service.managedExecutableURL()?.path ?? ""))
        XCTAssertTrue(FileManager.default.fileExists(atPath: CLIProxyAPIService.activeManagedVersionURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: CLIProxyAPIService.logsDirectoryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: CLIProxyAPIService.staticDirectoryURL.path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: CLIProxyAPIService.managedDownloadsDirectoryURL
                    .appendingPathComponent("v10.0.1", isDirectory: true)
                    .appendingPathComponent("CLIProxyAPI_10.0.1_darwin_arm64.tar.gz")
                    .path
            )
        )
    }

    func testManualCheckShowsUpToDateStateWhenVersionsMatch() async {
        let coordinator = UpdateCoordinator(
            releaseLoader: MockReleaseLoader(release: self.makeRelease(version: "1.1.5")),
            environment: MockUpdateEnvironment(
                currentVersion: "1.1.5",
                architecture: .arm64
            ),
            capabilityEvaluator: MockCapabilityEvaluator(blockers: []),
            actionExecutor: MockUpdateExecutor()
        )

        await coordinator.checkForUpdates(trigger: .manual)

        XCTAssertNil(coordinator.pendingAvailability)
        guard case let .upToDate(currentVersion, checkedVersion) = coordinator.state else {
            return XCTFail("Expected upToDate state")
        }
        XCTAssertEqual(currentVersion, "1.1.5")
        XCTAssertEqual(checkedVersion, "1.1.5")
    }

    func testCoordinatorFailsWhenCompatibleArtifactIsMissing() async {
        let feed = self.makeFeed(
            version: "1.1.7",
            artifacts: [
                AppUpdateArtifact(
                    architecture: .x86_64,
                    format: .dmg,
                    downloadURL: URL(string: "https://example.com/intel.dmg")!,
                    sha256: nil
                )
            ]
        )

        let coordinator = UpdateCoordinator(
            releaseLoader: MockReleaseLoader(release: feed.release),
            environment: MockUpdateEnvironment(
                currentVersion: "1.1.5",
                architecture: .arm64
            ),
            capabilityEvaluator: MockCapabilityEvaluator(blockers: []),
            actionExecutor: MockUpdateExecutor()
        )

        await coordinator.checkForUpdates(trigger: .manual)

        guard case let .failed(message) = coordinator.state else {
            return XCTFail("Expected failed state")
        }
        XCTAssertEqual(message, L.updateErrorNoCompatibleArtifact("Apple Silicon"))
    }

    func testArtifactSelectorPrefersArmThenUniversal() throws {
        let artifact = try AppUpdateArtifactSelector.selectArtifact(
            for: .arm64,
            artifacts: [
                AppUpdateArtifact(
                    architecture: .universal,
                    format: .dmg,
                    downloadURL: URL(string: "https://example.com/universal.dmg")!,
                    sha256: nil
                ),
                AppUpdateArtifact(
                    architecture: .arm64,
                    format: .zip,
                    downloadURL: URL(string: "https://example.com/arm.zip")!,
                    sha256: nil
                ),
            ]
        )

        XCTAssertEqual(artifact.architecture, .universal)
        XCTAssertEqual(artifact.format, .dmg)
    }

    func testArtifactSelectorPrefersIntelSpecificBuild() throws {
        let artifact = try AppUpdateArtifactSelector.selectArtifact(
            for: .x86_64,
            artifacts: [
                AppUpdateArtifact(
                    architecture: .universal,
                    format: .zip,
                    downloadURL: URL(string: "https://example.com/universal.zip")!,
                    sha256: nil
                ),
                AppUpdateArtifact(
                    architecture: .x86_64,
                    format: .dmg,
                    downloadURL: URL(string: "https://example.com/intel.dmg")!,
                    sha256: nil
                ),
            ]
        )

        XCTAssertEqual(artifact.architecture, .x86_64)
        XCTAssertEqual(artifact.format, .dmg)
    }

    func testGitHubReleasesLoaderSkipsDraftPrereleaseAndMissingArtifacts() async throws {
        let releasesURL = URL(string: "https://api.github.com/repos/lizhelang/codexkit/releases")!
        let session = self.makeMockSession()
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url, releasesURL)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")

            let body = """
            [
              {
                "tag_name": "v1.2.1-beta.1",
                "name": "v1.2.1 beta 1",
                "body": "pre",
                "html_url": "https://github.com/lizhelang/codexkit/releases/tag/v1.2.1-beta.1",
                "draft": false,
                "prerelease": true,
                "published_at": "2026-04-15T11:49:02Z",
                "assets": [
                  {
                    "name": "codexkit-1.2.1-beta.1-macOS.dmg",
                    "browser_download_url": "https://example.com/pre.dmg"
                  }
                ]
              },
              {
                "tag_name": "v1.2.0",
                "name": "v1.2.0",
                "body": "stable but not installable",
                "html_url": "https://github.com/lizhelang/codexkit/releases/tag/v1.2.0",
                "draft": false,
                "prerelease": false,
                "published_at": "2026-04-15T11:48:02Z",
                "assets": [
                  {
                    "name": "codexkit-1.2.0.pkg",
                    "browser_download_url": "https://example.com/ignored.pkg"
                  }
                ]
              },
              {
                "tag_name": "v1.1.9",
                "name": "v1.1.9",
                "body": "reissued stable",
                "html_url": "https://github.com/lizhelang/codexkit/releases/tag/v1.1.9",
                "draft": false,
                "prerelease": false,
                "published_at": "2026-04-15T11:47:02Z",
                "assets": [
                  {
                    "name": "codexkit-1.1.9-macOS.dmg",
                    "browser_download_url": "https://example.com/universal.dmg",
                    "digest": "sha256:abc123"
                  },
                  {
                    "name": "codexkit-1.1.9-macOS-intel.zip",
                    "browser_download_url": "https://example.com/intel.zip",
                    "digest": "sha256:def456"
                  }
                ]
              }
            ]
            """

            return (
                HTTPURLResponse(url: releasesURL, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(body.utf8)
            )
        }

        let loader = LiveGitHubReleasesUpdateLoader(
            environment: MockUpdateEnvironment(
                currentVersion: "1.1.8",
                architecture: .arm64,
                githubReleasesURL: releasesURL
            ),
            session: session
        )

        let release = try await loader.loadLatestRelease()

        XCTAssertEqual(release.version, "1.1.9")
        XCTAssertEqual(release.deliveryMode, .guidedDownload)
        XCTAssertEqual(release.artifacts.count, 2)
        XCTAssertEqual(release.artifacts[0].architecture, .universal)
        XCTAssertEqual(release.artifacts[0].format, .dmg)
        XCTAssertEqual(release.artifacts[0].sha256, "abc123")
        XCTAssertEqual(release.artifacts[1].architecture, .x86_64)
        XCTAssertEqual(release.artifacts[1].format, .zip)
        XCTAssertEqual(release.artifacts[1].sha256, "def456")
    }

    func testManualCheckDoesNotTreatReissued119AsUpgradeable() async {
        let coordinator = UpdateCoordinator(
            releaseLoader: MockReleaseLoader(release: self.makeRelease(version: "1.1.9")),
            environment: MockUpdateEnvironment(
                currentVersion: "1.1.9",
                architecture: .arm64
            ),
            capabilityEvaluator: MockCapabilityEvaluator(blockers: []),
            actionExecutor: MockUpdateExecutor()
        )

        await coordinator.checkForUpdates(trigger: .manual)

        XCTAssertNil(coordinator.pendingAvailability)
        guard case let .upToDate(currentVersion, checkedVersion) = coordinator.state else {
            return XCTFail("Expected upToDate state")
        }
        XCTAssertEqual(currentVersion, "1.1.9")
        XCTAssertEqual(checkedVersion, "1.1.9")
    }

    func testStableFeedUsesGuidedDownloadArtifacts() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let feedURL = rootURL.appendingPathComponent("release-feed/stable.json")
        let data = try Data(contentsOf: feedURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let feed = try decoder.decode(AppUpdateFeed.self, from: data)
        let releaseVersion = feed.release.version

        XCTAssertFalse(releaseVersion.isEmpty)
        XCTAssertEqual(feed.release.deliveryMode, .guidedDownload)
        XCTAssertTrue(feed.release.downloadPageURL.absoluteString.contains("/releases/tag/v\(releaseVersion)"))
        XCTAssertEqual(feed.release.artifacts.count, 2)
        XCTAssertTrue(feed.release.artifacts.allSatisfy { $0.sha256?.isEmpty == false })
        XCTAssertTrue(feed.release.artifacts.allSatisfy {
            $0.downloadURL.absoluteString.contains("/releases/download/v\(releaseVersion)/")
        })
        XCTAssertEqual(Set(feed.release.artifacts.map(\.format)), Set([.dmg, .zip]))
    }

    func testBootstrapGateKeeps115InGuidedMode() {
        let evaluator = DefaultAppUpdateCapabilityEvaluator(
            signatureInspector: MockSignatureInspector(
                inspection: AppSignatureInspection(
                    hasUsableSignature: true,
                    summary: "Signature=Developer ID; TeamIdentifier=TEAMID"
                )
            ),
            gatekeeperInspector: MockGatekeeperInspector(
                inspection: AppGatekeeperInspection(
                    passesAssessment: true,
                    summary: "accepted | source=Developer ID"
                )
            ),
            automaticUpdaterAvailable: true
        )

        let blockers = evaluator.blockers(
            for: AppUpdateRelease(
                version: "1.1.7",
                publishedAt: nil,
                summary: nil,
                releaseNotesURL: URL(string: "https://example.com/release-notes")!,
                downloadPageURL: URL(string: "https://example.com/download")!,
                deliveryMode: .automatic,
                minimumAutomaticUpdateVersion: "1.1.6",
                artifacts: []
            ),
            environment: MockUpdateEnvironment(
                currentVersion: "1.1.5",
                bundleURL: URL(fileURLWithPath: "/Applications/codexkit.app"),
                architecture: .arm64
            )
        )

        XCTAssertEqual(
            blockers,
            [
                .bootstrapRequired(
                    currentVersion: "1.1.5",
                    minimumAutomaticVersion: "1.1.6"
                )
            ]
        )
    }

    func testPhase0GateIncludesGatekeeperAssessmentBlocker() {
        let evaluator = DefaultAppUpdateCapabilityEvaluator(
            signatureInspector: MockSignatureInspector(
                inspection: AppSignatureInspection(
                    hasUsableSignature: true,
                    summary: "Signature=Developer ID; TeamIdentifier=TEAMID"
                )
            ),
            gatekeeperInspector: MockGatekeeperInspector(
                inspection: AppGatekeeperInspection(
                    passesAssessment: false,
                    summary: "accepted | source=no usable signature"
                )
            ),
            automaticUpdaterAvailable: true
        )

        let blockers = evaluator.blockers(
            for: AppUpdateRelease(
                version: "1.1.7",
                publishedAt: nil,
                summary: nil,
                releaseNotesURL: URL(string: "https://example.com/release-notes")!,
                downloadPageURL: URL(string: "https://example.com/download")!,
                deliveryMode: .automatic,
                minimumAutomaticUpdateVersion: "1.1.5",
                artifacts: []
            ),
            environment: MockUpdateEnvironment(
                currentVersion: "1.1.5",
                bundleURL: URL(fileURLWithPath: "/Applications/codexkit.app"),
                architecture: .arm64
            )
        )

        XCTAssertEqual(
            blockers,
            [.failingGatekeeperAssessment(summary: "accepted | source=no usable signature")]
        )
    }

    private func makeFeed(
        version: String,
        artifacts: [AppUpdateArtifact]? = nil
    ) -> AppUpdateFeed {
        AppUpdateFeed(
            schemaVersion: 1,
            channel: "stable",
            release: AppUpdateRelease(
                version: version,
                publishedAt: nil,
                summary: "Guided release",
                releaseNotesURL: URL(string: "https://example.com/release-notes")!,
                downloadPageURL: URL(string: "https://example.com/download")!,
                deliveryMode: .guidedDownload,
                minimumAutomaticUpdateVersion: "1.1.6",
                artifacts: artifacts ?? [
                    AppUpdateArtifact(
                        architecture: .arm64,
                        format: .dmg,
                        downloadURL: URL(string: "https://example.com/arm.dmg")!,
                        sha256: nil
                    ),
                    AppUpdateArtifact(
                        architecture: .x86_64,
                        format: .dmg,
                        downloadURL: URL(string: "https://example.com/intel.dmg")!,
                        sha256: nil
                    ),
                ]
            )
        )
    }

    private func makeRelease(
        version: String,
        artifacts: [AppUpdateArtifact]? = nil
    ) -> AppUpdateRelease {
        self.makeFeed(version: version, artifacts: artifacts).release
    }

    private func writeExecutable(at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: url.path
        )
    }

    private func makeCLIProxyAPITarball() throws -> Data {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let payloadRoot = root.appendingPathComponent("payload", isDirectory: true)
        let archiveURL = root.appendingPathComponent("cpa.tar.gz")
        try self.writeExecutable(at: payloadRoot.appendingPathComponent("cli-proxy-api"))
        try Data("fixture".utf8).write(to: payloadRoot.appendingPathComponent("README.md"))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-czf", archiveURL.path, "-C", payloadRoot.path, "."]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            XCTFail(String(data: data, encoding: .utf8) ?? "tar failed")
        }
        return try Data(contentsOf: archiveURL)
    }
}

private final class MockReleaseLoader: AppUpdateReleaseLoading {
    var release: AppUpdateRelease
    var loadCount = 0

    init(release: AppUpdateRelease) {
        self.release = release
    }

    func loadLatestRelease() async throws -> AppUpdateRelease {
        self.loadCount += 1
        return self.release
    }
}

private struct MockUpdateEnvironment: AppUpdateEnvironmentProviding {
    var currentVersion: String
    var bundleURL: URL = URL(fileURLWithPath: "/Applications/codexkit.app")
    var architecture: UpdateArtifactArchitecture
    var githubReleasesURL: URL? = URL(string: "https://api.github.com/repos/lizhelang/codexkit/releases")
}

private struct MockCapabilityEvaluator: AppUpdateCapabilityEvaluating {
    var blockers: [AppUpdateBlocker]

    func blockers(
        for release: AppUpdateRelease,
        environment: AppUpdateEnvironmentProviding
    ) -> [AppUpdateBlocker] {
        self.blockers
    }
}

private final class MockUpdateExecutor: AppUpdateActionExecuting {
    var executed: [AppUpdateAvailability] = []
    var error: Error?

    func execute(_ availability: AppUpdateAvailability) async throws {
        if let error {
            throw error
        }
        self.executed.append(availability)
    }
}

private final class MockAutomaticCheckScheduler: AppUpdateAutomaticCheckScheduling {
    private(set) var scheduledIntervals: [TimeInterval] = []
    private var operations: [(@Sendable @MainActor () async -> Void)] = []

    func scheduleRepeating(
        every interval: TimeInterval,
        operation: @escaping @Sendable @MainActor () async -> Void
    ) -> AppUpdateAutomaticCheckCancelling {
        self.scheduledIntervals.append(interval)
        self.operations.append(operation)
        return MockAutomaticCheckHandle()
    }

    func waitUntilScheduled() async {
        while self.scheduledIntervals.isEmpty {
            await Task.yield()
        }
    }

    func fire() async {
        for operation in self.operations {
            await operation()
        }
    }
}

private struct MockAutomaticCheckHandle: AppUpdateAutomaticCheckCancelling {
    func cancel() {}
}

private struct MockSignatureInspector: AppSignatureInspecting {
    var inspection: AppSignatureInspection

    func inspect(bundleURL: URL) -> AppSignatureInspection {
        self.inspection
    }
}

private struct MockGatekeeperInspector: AppGatekeeperInspecting {
    var inspection: AppGatekeeperInspection

    func inspect(bundleURL: URL) -> AppGatekeeperInspection {
        self.inspection
    }
}

private struct MockCLIProxyAPIInstalledVersionProvider: CLIProxyAPIInstalledVersionProviding {
    var installedVersion: String

    func resolveInstalledVersion() -> String {
        self.installedVersion
    }
}

private final class MockCLIProxyAPIReleaseLoader: CLIProxyAPIReleaseLoading {
    var release: CLIProxyAPIUpdateRelease
    var loadCount = 0

    init(release: CLIProxyAPIUpdateRelease) {
        self.release = release
    }

    func loadLatestRelease() async throws -> CLIProxyAPIUpdateRelease {
        self.loadCount += 1
        return self.release
    }
}

private final class MockCLIProxyAPIUpdateExecutor: CLIProxyAPIUpdateActionExecuting {
    var executed: [CLIProxyAPIUpdateAvailability] = []
    var error: Error?

    func execute(_ availability: CLIProxyAPIUpdateAvailability) async throws {
        if let error {
            throw error
        }
        self.executed.append(availability)
    }
}
