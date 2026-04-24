import AppKit
import SwiftUI

final class DetachedWindow: NSWindow {
    var shouldCloseHandler: (() -> Bool)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let character = event.charactersIgnoringModifiers?.lowercased()
        let isCloseShortcut = character == "w" && (modifiers == [.command] || modifiers == [.control])

        if isCloseShortcut {
            self.performClose(nil)
            return true
        }

        return super.performKeyEquivalent(with: event)
    }
}

private final class HoverPanelWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class DetachedWindowPresenter: NSObject, NSWindowDelegate {
    static let shared = DetachedWindowPresenter()

    private var windows: [String: NSWindow] = [:]
    private var originalActivationPolicy: NSApplication.ActivationPolicy?
    private var detachedWindowIDs: Set<String> = []
    private var hoverPanelIDs: Set<String> = []
    private var localKeyMonitor: Any?

    func show<Content: View>(
        id: String,
        title: String,
        size: CGSize,
        resizable: Bool = false,
        preserveExistingSize: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        let anyView = AnyView(content())

        if let existing = self.windows[id] {
            existing.title = title
            if preserveExistingSize == false {
                existing.setContentSize(size)
            }
            if let controller = existing.contentViewController as? NSHostingController<AnyView> {
                controller.rootView = anyView
            } else {
                existing.contentViewController = NSHostingController(rootView: anyView)
            }
            existing.styleMask = resizable
                ? existing.styleMask.union(.resizable)
                : existing.styleMask.subtracting(.resizable)
            if existing is DetachedWindow {
                self.noteDetachedWindowShown(id: id)
            }
            NSRunningApplication.current.activate(options: [.activateAllWindows])
            NSApp.activate(ignoringOtherApps: true)
            existing.orderFrontRegardless()
            existing.makeKeyAndOrderFront(nil)
            existing.makeMain()
            return
        }

        let controller = NSHostingController(rootView: anyView)
        let window = DetachedWindow(contentViewController: controller)
        window.identifier = NSUserInterfaceItemIdentifier(id)
        window.title = title
        window.styleMask = resizable
            ? [.titled, .closable, .miniaturizable, .resizable]
            : [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(size)
        window.center()
        window.delegate = self

        self.windows[id] = window
        self.noteDetachedWindowShown(id: id)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        window.makeMain()
    }

    func showHoverPanel<Content: View>(id: String, size: CGSize, origin: CGPoint, @ViewBuilder content: () -> Content) {
        let anyView = AnyView(content())

        if let existing = self.windows[id] {
            if existing.frame.size != size {
                existing.setContentSize(size)
            }
            if existing.frame.origin != origin {
                existing.setFrameOrigin(origin)
            }
            if let controller = existing.contentViewController as? NSHostingController<AnyView> {
                controller.rootView = anyView
            } else {
                existing.contentViewController = NSHostingController(rootView: anyView)
            }
            existing.orderFront(nil)
            return
        }

        let controller = NSHostingController(rootView: anyView)
        let window = HoverPanelWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier(id)
        window.contentViewController = controller
        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.hidesOnDeactivate = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.delegate = self

        self.windows[id] = window
        self.hoverPanelIDs.insert(id)
        window.orderFront(nil)
    }

    func close(id: String) {
        guard let window = self.windows[id] else { return }
        window.close()
        self.windows.removeValue(forKey: id)
        self.hoverPanelIDs.remove(id)
    }

    func closeHoverPanels() {
        let ids = Array(self.hoverPanelIDs)
        for id in ids {
            self.close(id: id)
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let id = window.identifier?.rawValue else { return }
        self.windows.removeValue(forKey: id)
        self.hoverPanelIDs.remove(id)
        if window is DetachedWindow {
            self.noteDetachedWindowClosed(id: id)
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let window = sender as? DetachedWindow,
              let shouldCloseHandler = window.shouldCloseHandler else {
            return true
        }
        return shouldCloseHandler()
    }

    private func noteDetachedWindowShown(id: String) {
        if self.detachedWindowIDs.isEmpty {
            self.originalActivationPolicy = NSApp.activationPolicy()
            if self.originalActivationPolicy != .regular {
                _ = NSApp.setActivationPolicy(.regular)
            }
            self.installLocalKeyMonitorIfNeeded()
        }
        self.detachedWindowIDs.insert(id)
    }

    private func noteDetachedWindowClosed(id: String) {
        self.detachedWindowIDs.remove(id)
        guard self.detachedWindowIDs.isEmpty,
              let originalActivationPolicy = self.originalActivationPolicy else { return }
        self.removeLocalKeyMonitor()
        _ = NSApp.setActivationPolicy(originalActivationPolicy)
        self.originalActivationPolicy = nil
    }

    private func installLocalKeyMonitorIfNeeded() {
        guard self.localKeyMonitor == nil else { return }
        self.localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard self != nil else { return event }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let character = event.charactersIgnoringModifiers?.lowercased()
            let isCloseShortcut = character == "w" && (modifiers == [.command] || modifiers == [.control])
            guard isCloseShortcut else { return event }

            let candidateWindow = NSApp.keyWindow ?? NSApp.mainWindow
            guard let detachedWindow = candidateWindow as? DetachedWindow else { return event }
            detachedWindow.performClose(nil)
            return nil
        }
    }

    private func removeLocalKeyMonitor() {
        guard let localKeyMonitor = self.localKeyMonitor else { return }
        NSEvent.removeMonitor(localKeyMonitor)
        self.localKeyMonitor = nil
    }
}
