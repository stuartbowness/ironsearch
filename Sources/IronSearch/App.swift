import AppKit
import Carbon
import QuartzCore
import SwiftUI

@main
struct IronSearchApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class SearchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = SearchModel()
    private var panel: SearchPanel!
    private var statusItem: NSStatusItem!
    private var hotKey: GlobalHotKey?
    private var keyMonitor: Any?
    private var requestedHeight: CGFloat = 76
    private var showingPanel = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        makeMainMenu()
        panel = SearchPanel(contentRect: NSRect(x: 0, y: 0, width: 740, height: model.panelHeight),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Iron Search"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.delegate = self
        let hostingView = NSHostingView(rootView: SearchView(model: model))
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        model.dismiss = { [weak self] in self?.hide() }
        model.presentationChanged = { [weak self] in self?.resizePanel() }
        makeStatusMenu()
        hotKey = GlobalHotKey { [weak self] in self?.toggle() }
        model.shortcutAvailable = hotKey?.registered == true
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            if event.keyCode == 53 {
                self.model.escape()
                return nil
            }
            if self.model.showsResults,
               event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command, .option] {
                switch event.charactersIgnoringModifiers {
                case "0": self.model.scope = .all; return nil
                case "1": self.model.scope = .applications; return nil
                case "2": self.model.scope = .contacts; return nil
                default: break
                }
            }
            return event
        }
        show()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !panel.isVisible { show() }
        return true
    }

    private func makeMainMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Iron Search", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        menu.addItem(editItem)
        NSApp.mainMenu = menu
    }

    private func makeStatusMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "magnifyingglass.circle", accessibilityDescription: "Iron Search")
        statusItem.button?.toolTip = "Iron Search · ⌘Space"
        let menu = NSMenu()
        let showItem = menu.addItem(withTitle: "Search Apps & Contacts    ⌘Space", action: #selector(showFromMenu), keyEquivalent: "")
        showItem.target = self
        menu.addItem(.separator())
        let refreshItem = menu.addItem(withTitle: "Refresh Apps & Contacts", action: #selector(refresh), keyEquivalent: "")
        refreshItem.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Iron Search", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func showFromMenu() { show() }
    @objc private func refresh() { Task { await model.refresh() } }

    private func toggle() {
        if panel.isVisible { hide() } else { show() }
    }

    private func show() {
        showingPanel = true
        defer { showingPanel = false }
        model.resetSearch()
        model.detail = nil
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            // Anchor the search field in the upper quarter of the usable screen.
            // AppKit coordinates grow upward; results expand below this top edge.
            let searchCenterY = frame.minY + frame.height * 0.75
            let panelTop = searchCenterY + model.panelHeight / 2
            model.expandedPanelHeight = min(556, panelTop - frame.minY - 12)
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2,
                y: searchCenterY - model.panelHeight / 2))
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        focusSearch(in: panel.contentView)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.isKeyWindow, self.model.detail == nil else { return }
            self.focusSearch(in: self.panel.contentView)
        }
        Task { await model.refresh() }
    }

    private func focusSearch(in view: NSView?) {
        guard let view else { return }
        if let field = view as? NSTextField, field.isEditable {
            panel.makeFirstResponder(field)
            return
        }
        for child in view.subviews { focusSearch(in: child) }
    }

    private func resizePanel() {
        guard requestedHeight != model.panelHeight else { return }
        requestedHeight = model.panelHeight
        var frame = panel.frame
        frame.origin.y += frame.height - model.panelHeight
        frame.size.height = model.panelHeight
        let animate = panel.isVisible && !showingPanel
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animate ? 0.18 : 0
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    private func hide() { panel.orderOut(nil) }
    func windowDidResignKey(_ notification: Notification) { hide() }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        hotKey = nil
    }
}

// Carbon hotkeys don't require Accessibility or Input Monitoring permission.
@MainActor
final class GlobalHotKey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    private(set) var registered = false

    init(action: @escaping () -> Void) {
        self.action = action
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { hotKey.action() }
            return noErr
        }, 1, &eventType, context, &handler)
        guard handlerStatus == noErr else { return }
        let identifier = EventHotKeyID(signature: 0x49524F4E, id: 1)
        registered = RegisterEventHotKey(UInt32(kVK_Space), UInt32(cmdKey), identifier,
            GetApplicationEventTarget(), 0, &reference) == noErr
    }

    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }
}
