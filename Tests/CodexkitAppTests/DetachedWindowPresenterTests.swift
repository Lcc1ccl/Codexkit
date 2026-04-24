import AppKit
import XCTest
@testable import CodexkitApp

@MainActor
final class DetachedWindowPresenterTests: XCTestCase {
    func testDetachedWindowCanBecomeKeyAndMain() {
        let window = DetachedWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 120),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        XCTAssertTrue(window.canBecomeKey)
        XCTAssertTrue(window.canBecomeMain)
    }

    func testWindowShouldCloseUsesDetachedWindowHandler() {
        let presenter = DetachedWindowPresenter.shared
        let window = DetachedWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 120),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.shouldCloseHandler = { false }
        XCTAssertFalse(presenter.windowShouldClose(window))

        window.shouldCloseHandler = { true }
        XCTAssertTrue(presenter.windowShouldClose(window))
    }
}
