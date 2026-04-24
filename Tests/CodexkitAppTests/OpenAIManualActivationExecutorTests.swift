import XCTest
@testable import CodexkitApp

final class OpenAIManualActivationExecutorTests: XCTestCase {
    func testPrimaryTapExecutesConfigOnlyActivationWithoutLaunching() async throws {
        let tracker = ManualActivationEffectTracker()

        let result = try await OpenAIManualActivationExecutor.execute(
            targetAccountID: "acct-primary",
            configuredBehavior: .updateConfigOnly,
            trigger: .primaryTap
        ) {
            tracker.activateOnlyCount += 1
        } launchNewInstance: {
            tracker.launchCount += 1
        }

        XCTAssertEqual(result.action, .updateConfigOnly)
        XCTAssertEqual(result.targetAccountID, "acct-primary")
        XCTAssertFalse(result.launchedNewInstance)
        XCTAssertFalse(result.affectsRunningThreads)
        XCTAssertEqual(result.copyKey, .defaultTargetUpdated)
        XCTAssertEqual(result.immediateEffectRecommendation, .launchNewInstance)
        XCTAssertEqual(tracker.activateOnlyCount, 1)
        XCTAssertEqual(tracker.launchCount, 0)
    }

    func testContextOverrideLaunchExecutesLaunchPathEvenWhenDefaultIsConfigOnly() async throws {
        let tracker = ManualActivationEffectTracker()

        let result = try await OpenAIManualActivationExecutor.execute(
            targetAccountID: "acct-launch",
            configuredBehavior: .updateConfigOnly,
            trigger: .contextOverride(.launchNewInstance)
        ) {
            tracker.activateOnlyCount += 1
        } launchNewInstance: {
            tracker.launchCount += 1
        }

        XCTAssertEqual(result.action, .launchNewInstance)
        XCTAssertTrue(result.launchedNewInstance)
        XCTAssertEqual(result.copyKey, .launchedNewInstance)
        XCTAssertEqual(result.immediateEffectRecommendation, .noneNeeded)
        XCTAssertEqual(tracker.activateOnlyCount, 0)
        XCTAssertEqual(tracker.launchCount, 1)
    }

    func testContextOverrideConfigOnlyExecutesActivationWithoutLaunchingWhenDefaultIsLaunch() async throws {
        let tracker = ManualActivationEffectTracker()

        let result = try await OpenAIManualActivationExecutor.execute(
            targetAccountID: "acct-config",
            configuredBehavior: .launchNewInstance,
            trigger: .contextOverride(.updateConfigOnly)
        ) {
            tracker.activateOnlyCount += 1
        } launchNewInstance: {
            tracker.launchCount += 1
        }

        XCTAssertEqual(result.action, .updateConfigOnly)
        XCTAssertEqual(tracker.activateOnlyCount, 1)
        XCTAssertEqual(tracker.launchCount, 0)
    }
}

private final class ManualActivationEffectTracker {
    var activateOnlyCount = 0
    var launchCount = 0
}
