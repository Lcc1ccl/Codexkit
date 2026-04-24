import XCTest
@testable import CodexkitApp

@MainActor
final class CoalescedBackgroundRefreshControllerTests: XCTestCase {
    func testCoalescesRepeatedRequestsWhileRefreshIsInFlight() {
        let controller = CoalescedBackgroundRefreshController<Int>()
        let firstStarted = expectation(description: "first load started")
        let secondStarted = expectation(description: "second load started")
        let delivered = expectation(description: "deliveries")
        delivered.expectedFulfillmentCount = 2

        let loadCounter = LockedCounter()
        var values: [Int] = []

        let loader: @Sendable (Date) -> Int = { _ in
            let current = loadCounter.increment()

            if current == 1 {
                firstStarted.fulfill()
                Thread.sleep(forTimeInterval: 0.2)
            } else if current == 2 {
                secondStarted.fulfill()
            }

            return current
        }

        controller.requestRefresh(load: loader) { value in
            values.append(value)
            delivered.fulfill()
        }

        wait(for: [firstStarted], timeout: 1)
        controller.requestRefresh(load: loader) { value in
            values.append(value)
            delivered.fulfill()
        }
        controller.requestRefresh(load: loader) { value in
            values.append(value)
            delivered.fulfill()
        }

        wait(for: [secondStarted, delivered], timeout: 2)
        XCTAssertEqual(loadCounter.value, 2)
        XCTAssertEqual(values, [1, 2])
    }

    func testResetPreventsStaleResultFromApplying() {
        let controller = CoalescedBackgroundRefreshController<Int>()
        let staleDelivered = expectation(description: "stale delivery")
        staleDelivered.isInverted = true
        let freshDelivered = expectation(description: "fresh delivery")

        controller.requestRefresh(load: { _ in
            Thread.sleep(forTimeInterval: 0.2)
            return 1
        }) { _ in
            staleDelivered.fulfill()
        }

        controller.reset()

        controller.requestRefresh(load: { _ in
            2
        }) { value in
            XCTAssertEqual(value, 2)
            freshDelivered.fulfill()
        }

        wait(for: [freshDelivered], timeout: 2)
        wait(for: [staleDelivered], timeout: 0.3)
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    func increment() -> Int {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.storage += 1
        return self.storage
    }

    var value: Int {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.storage
    }
}
