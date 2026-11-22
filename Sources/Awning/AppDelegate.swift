import AppKit
import ServiceManagement

extension Notification.Name {
    /// Posted by a second launch so the running instance toggles instead.
    static let awningToggle = Notification.Name("dev.awning.Awning.toggle")
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var visor: VisorController!
    private var statusItem: NSStatusItem!
    private let statusMenu = NSMenu()
    private let settings = Settings.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()

        visor = VisorController()
        installStatusItem()
        HotKeyCenter.shared.onPress = { [weak self] in self?.visor.toggle() }
        applyHotKey(HotKeyPreset.preset(id: settings.hotKeyID), userInitiated: false)

        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(toggleVisor), name: .awningToggle, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(flushNotes), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(flushNotes), name: NSWorkspace.willPowerOffNotification, object: nil)

        if !settings.hasLaunchedBefore {
            settings.hasLaunchedBefore = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.visor.show() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        visor.flush()
    }

    @objc private func flushNotes() { visor.flush() }
    @objc private func toggleVisor() { visor.toggle() }

    // MARK: - Hotkey

    private func applyHotKey(_ preset: HotKeyPreset, userInitiated: Bool) {
        settings.hotKeyID = preset.id
        let ok = HotKeyCenter.shared.register(preset)
        visor.hotKeyTitle = preset.title
        updateStatusIcon()
        if !ok && userInitiated {
            alert("\(preset.title) is already in use",
                  "Another app or a system shortcut has claimed it. Pick a different hotkey from the menu bar icon.")
        }
    }

    // MARK: - Menus

    /// A minimal main menu: gives text input the standard Edit services (dictation,
    /// emoji picker) whenever the app does become active.
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Awning", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSTextView.pasteAsPlainText(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    private func installStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusMenu.delegate = self
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        updateStatusIcon()
    }

    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        let ok = HotKeyCenter.shared.isRegistered
        let image = NSImage(systemSymbolName: ok ? "text.alignleft" : "exclamationmark.triangle",
                            accessibilityDescription: "Awning")
        image?.isTemplate = true
        button.image = image
        let title = HotKeyCenter.shared.current?.title ?? ""
        button.toolTip = ok ? "Awning — \(title)" : "Awning — hotkey \(title) unavailable, pick another"
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
            || event?.modifierFlags.contains(.option) == true
        if wantsMenu {
            statusItem.menu = statusMenu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil // so a plain left click toggles again
        } else {
            visor.toggleFromStatusItem()
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let hotKey = HotKeyCenter.shared.current?.title ?? ""

        menu.addItem(item(visor.isShown ? "Hide Visor" : "Show Visor", #selector(toggleVisor), detail: hotKey))
        menu.addItem(.separator())

        let path = NSMenuItem(title: Settings.displayPath(visor.notesURL), action: nil, keyEquivalent: "")
        path.isEnabled = false
        menu.addItem(path)
        menu.addItem(item("Open in Default Editor", #selector(openExternal)))
        menu.addItem(item("Reveal in Finder", #selector(revealFile)))
        menu.addItem(item("Choose Notes File…", #selector(chooseNotesFile)))
        if settings.notesPath != Settings.defaultNotesPath {
            menu.addItem(item("Use \(Settings.defaultNotesPath)", #selector(resetNotesFile)))
        }
        if hasConflictBackups {
            menu.addItem(item("Show Conflict Backups", #selector(showConflicts)))
        }
        menu.addItem(.separator())

        let hotKeyItem = NSMenuItem(title: "Hotkey", action: nil, keyEquivalent: "")
        let hotKeyMenu = NSMenu()
        for preset in HotKeyPreset.all {
            let entry = item(preset.title, #selector(pickHotKey(_:)))
            entry.representedObject = preset.id
            if preset.id == HotKeyCenter.shared.current?.id {
                entry.state = HotKeyCenter.shared.isRegistered ? .on : .mixed
                if !HotKeyCenter.shared.isRegistered { entry.title += "  (in use by another app)" }
            }
            hotKeyMenu.addItem(entry)
        }
        hotKeyItem.submenu = hotKeyMenu
        menu.addItem(hotKeyItem)

        let appearanceItem = NSMenuItem(title: "Appearance", action: nil, keyEquivalent: "")
        let appearanceMenu = NSMenu()
        for mode in AppearanceMode.allCases {
            let entry = item(mode.title, #selector(pickAppearance(_:)))
            entry.representedObject = mode.rawValue
            entry.state = mode == visor.appearance ? .on : .off
            appearanceMenu.addItem(entry)
        }
        appearanceItem.submenu = appearanceMenu
        menu.addItem(appearanceItem)

        let keepOpen = item("Keep Open When Unfocused", #selector(toggleKeepOpen))
        keepOpen.state = visor.keepOpen ? .on : .off
        menu.addItem(keepOpen)

        let login = item("Launch at Login", #selector(toggleLaunchAtLogin))
        switch SMAppService.mainApp.status {
        case .enabled: login.state = .on
        case .requiresApproval: login.state = .mixed
        default: login.state = .off
        }
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(item("Quit Awning", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "", detail: String? = nil) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = self
        if let detail, !detail.isEmpty {
            let text = NSMutableAttributedString(string: title + "    ")
            text.append(NSAttributedString(string: detail, attributes: [.foregroundColor: NSColor.secondaryLabelColor]))
            entry.attributedTitle = text
        }
        return entry
    }

    // MARK: - Menu actions

    @objc private func openExternal() { visor.openInDefaultEditor() }
    @objc private func revealFile() { visor.revealInFinder() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func toggleKeepOpen() { visor.keepOpen.toggle() }

    @objc private func pickAppearance(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = AppearanceMode(rawValue: raw) else { return }
        visor.appearance = mode
    }

    @objc private func pickHotKey(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        applyHotKey(HotKeyPreset.preset(id: id), userInitiated: true)
    }

    @objc private func chooseNotesFile() {
        visor.hide()
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "Choose a notes file"
        panel.prompt = "Use This File"
        panel.message = "Awning edits a single plain-text file. Pick an existing .txt / .md file."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = visor.notesURL.deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        useNotesFile(Settings.displayPath(url))
        visor.show()
    }

    @objc private func resetNotesFile() {
        useNotesFile(Settings.defaultNotesPath)
    }

    private func useNotesFile(_ path: String) {
        settings.notesPath = path
        visor.switchNotes(to: settings.notesURL)
    }

    private var hasConflictBackups: Bool {
        let items = try? FileManager.default.contentsOfDirectory(atPath: Settings.conflictsDirectory.path)
        return !(items ?? []).isEmpty
    }

    @objc private func showConflicts() {
        NSWorkspace.shared.open(Settings.conflictsDirectory)
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            switch service.status {
            case .enabled:
                try service.unregister()
            case .requiresApproval:
                SMAppService.openSystemSettingsLoginItems()
            default:
                try service.register()
                if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            }
        } catch {
            alert("Couldn't change Launch at Login", error.localizedDescription
                  + "\n\nMove Awning.app to /Applications (./build.sh install) and try again.")
        }
    }

    private func alert(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
