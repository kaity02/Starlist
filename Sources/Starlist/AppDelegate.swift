import AppKit
import ServiceManagement
import StarlistKit
import SwiftUI

/// A borderless panel that can still take the keyboard, so you can type a task
/// without the app coming to the front.
final class SkyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model: AppModel
    private var statusItem: NSStatusItem!
    private var panel: SkyPanel!
    private var keyMonitor: Any?
    private var outsideClickMonitor: Any?

    /// When the panel last closed by itself (focus moved elsewhere).
    private var lastAutoClose = Date.distantPast
    /// True while a menu or the folder chooser is up, so the panel doesn't close under it.
    private var holdsPanelOpen = false

    init(paths: AppPaths) {
        model = AppModel(paths: paths)
        super.init()
    }

    // MARK: Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()
        setUpStatusItem()
        setUpPanel()
        setUpMonitors()

        model.onRequestClose = { [weak self] in self?.hidePanel() }
        model.onShowSettingsMenu = { [weak self] in
            // After the click finishes, so the button isn't left looking pressed.
            DispatchQueue.main.async { self?.showSettingsMenu() }
        }
        model.onChooseArchiveFolder = { [weak self] in
            DispatchQueue.main.async { self?.chooseArchiveFolder() }
        }

        if model.isFirstLaunch || CommandLine.arguments.contains("--show") {
            // Give the menu bar a moment to place the icon, then introduce the panel.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showPanel()
            }
        }
    }

    /// Opening the app again (Spotlight, Finder) shows the panel. That is also the
    /// way in if the menu bar is too crowded for the icon to fit.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showPanel()
        return false
    }

    // MARK: Status item

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "StarlistStatusItem"
        guard let button = statusItem.button else { return }
        button.image = StatusGlyph.image()
        button.imagePosition = .imageOnly
        button.toolTip = "Starlist"
        button.setAccessibilityLabel("Starlist to-do list")
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseDown, .rightMouseUp])
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
        if wantsMenu {
            hidePanel()
            showStatusMenu()
        } else {
            togglePanel()
        }
    }

    private func togglePanel() {
        if panel.isVisible {
            hidePanel()
        } else if Date().timeIntervalSince(lastAutoClose) > 0.3 {
            // Otherwise this is the very click that just closed the panel.
            showPanel()
        }
    }

    // MARK: Panel

    private func setUpPanel() {
        let size = NSSize(width: PanelMetrics.width, height: PanelMetrics.height)
        panel = SkyPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Starlist"
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.delegate = self

        let host = NSHostingView(rootView: RootView(model: model))
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host
    }

    private func showPanel(showing screen: AppModel.Screen = .list) {
        model.panelWillAppear(showing: screen)
        panel.setFrameOrigin(panelOrigin())
        // No fade: the panel must never depend on an animation finishing to be visible.
        panel.alphaValue = 1
        panel.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.isVisible else { return }
            // After the click has finished, or the button clears its own highlight.
            self.statusItem.button?.highlight(true)
            self.panel.invalidateShadow()
        }
        // The shadow is cut from the SwiftUI content, which can draw a beat later.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.panel.invalidateShadow()
        }
    }

    private func hidePanel() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        statusItem.button?.highlight(false)
    }

    /// The panel closed because attention moved somewhere else.
    private func autoClosePanel() {
        guard panel.isVisible, !holdsPanelOpen else { return }
        lastAutoClose = Date()
        hidePanel()
    }

    /// Directly under the menu bar icon, kept on screen. If the icon isn't
    /// showing (a crowded menu bar), the top right corner of the main screen.
    private func panelOrigin() -> NSPoint {
        let size = panel.frame.size
        let gap: CGFloat = 6
        if let buttonWindow = statusItem.button?.window,
           let screen = buttonWindow.screen,
           buttonWindow.occlusionState.contains(.visible) {
            let anchor = buttonWindow.frame
            let visible = screen.visibleFrame
            let x = min(
                max(anchor.midX - size.width / 2, visible.minX + 8),
                visible.maxX - size.width - 8
            )
            let top = min(anchor.minY, visible.maxY)
            return NSPoint(x: x, y: top - gap - size.height)
        }
        let visible = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        return NSPoint(
            x: visible.maxX - size.width - 12,
            y: visible.maxY - gap - size.height
        )
    }

    func windowDidResignKey(_ notification: Notification) {
        autoClosePanel()
    }

    // MARK: Keyboard and outside clicks

    private func setUpMonitors() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated {
                guard let self, self.panel.isKeyWindow else { return false }
                return self.handleKeyDown(event)
            }
            return handled ? nil : event
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.autoClosePanel()
            }
        }
    }

    /// The panel takes keys without the app being frontmost, so the usual menu
    /// shortcuts are handled here.
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let escapeKey: UInt16 = 53
        if event.keyCode == escapeKey {
            if model.editingID != nil {
                model.cancelEditing()
            } else {
                hidePanel()
            }
            return true
        }

        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return false }

        if flags == .command {
            switch key {
            case "q":
                NSApp.terminate(nil)
            case "w":
                hidePanel()
            case "x":
                NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self)
            case "c":
                NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self)
            case "v":
                NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self)
            case "a":
                NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self)
            case "z":
                NSApp.sendAction(Selector(("undo:")), to: nil, from: self)
            default:
                return false
            }
            return true
        }
        if flags == [.command, .shift], key == "z" {
            NSApp.sendAction(Selector(("redo:")), to: nil, from: self)
            return true
        }
        return false
    }

    // MARK: Menus

    /// Settings and Quit. Shown from the panel's "..." button and by
    /// right-clicking the menu bar icon.
    private func makeSettingsMenu(includesOpen: Bool) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        func add(_ title: String, _ action: Selector, key: String = "", checked: Bool? = nil) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            if let checked { item.state = checked ? .on : .off }
            menu.addItem(item)
        }

        if includesOpen {
            add("Open Starlist", #selector(openFromMenu))
            menu.addItem(.separator())
        }
        add("Keep unfinished tasks when archiving", #selector(toggleKeepsUnfinished),
            checked: model.keepsUnfinished)
        add("Open at login", #selector(toggleOpenAtLogin),
            checked: SMAppService.mainApp.status == .enabled)
        menu.addItem(.separator())
        add("Show archive folder", #selector(showArchiveFolder))
        add("Change archive folder…", #selector(changeArchiveFolder))
        menu.addItem(.separator())
        add("Quit Starlist", #selector(quit), key: "q")
        return menu
    }

    private func showSettingsMenu() {
        holdsPanelOpen = true
        makeSettingsMenu(includesOpen: false)
            .popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        holdsPanelOpen = false
        // If the menu was dismissed by clicking into another app, follow it out.
        if panel.isVisible, !panel.isKeyWindow {
            autoClosePanel()
        }
    }

    private func showStatusMenu() {
        statusItem.menu = makeSettingsMenu(includesOpen: true)
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openFromMenu() {
        DispatchQueue.main.async { [weak self] in self?.showPanel() }
    }

    @objc private func toggleKeepsUnfinished() {
        model.keepsUnfinished.toggle()
    }

    @objc private func toggleOpenAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            model.showFailure(
                "Couldn't change the login setting. You can add Starlist in System Settings, under General, Login Items."
            )
        }
    }

    @objc private func showArchiveFolder() {
        model.revealArchiveFolder()
    }

    @objc private func changeArchiveFolder() {
        DispatchQueue.main.async { [weak self] in self?.chooseArchiveFolder() }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func chooseArchiveFolder() {
        holdsPanelOpen = true
        hidePanel()
        NSApp.activate(ignoringOtherApps: true)

        let chooser = NSOpenPanel()
        chooser.title = "Archive folder"
        chooser.message = "Choose where Starlist saves archived lists."
        chooser.prompt = "Use this folder"
        chooser.canChooseFiles = false
        chooser.canChooseDirectories = true
        chooser.canCreateDirectories = true
        chooser.allowsMultipleSelection = false
        chooser.directoryURL = model.archive.folderURL.deletingLastPathComponent()

        let response = chooser.runModal()
        holdsPanelOpen = false
        if response == .OK, let url = chooser.url {
            model.dismissBanner()
            model.setArchiveFolder(url)
        }
        showPanel(showing: .history)
    }

    /// The app has no menu bar of its own, but a main menu still supplies the
    /// standard shortcuts inside the folder chooser.
    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "Quit Starlist", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"
        )
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(
            withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"
        )
        editItem.submenu = editMenu
        main.addItem(editItem)

        return main
    }
}
