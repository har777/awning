import AppKit
import AwningCore

/// Wires the panel, editor UI and note session together, and owns the visor's shortcuts.
final class VisorController: NSObject, NSTextViewDelegate {
    let panel: VisorPanel
    private let settings = Settings.shared
    private let highlighter: Highlighter
    private let editor: EditorView
    private var session: NoteSession!
    private var textView: NoteTextView { editor.textView }

    private var statsTimer: Timer?
    private var clickMonitor: Any?
    private var lastAutoHide = Date.distantPast

    var hotKeyTitle = HotKeyPreset.all[0].title {
        didSet { editor.setHints(hotKey: hotKeyTitle) }
    }

    var isShown: Bool { panel.isShown }
    var notesURL: URL { session.file.url }

    var appearance: AppearanceMode {
        get { settings.appearance }
        set {
            settings.appearance = newValue
            panel.appearance = newValue.nsAppearance
            panel.invalidateShadow()
        }
    }

    var animation: VisorAnimation {
        get { settings.animation }
        set { settings.animation = newValue }
    }

    var keepOpen: Bool {
        get { settings.keepOpenWhenUnfocused }
        set {
            settings.keepOpenWhenUnfocused = newValue
            editor.pinButton.isActive = newValue
        }
    }

    override init() {
        highlighter = Highlighter(fontSize: CGFloat(settings.fontSize))
        editor = EditorView(highlighter: highlighter)
        panel = VisorPanel(editor: editor)
        super.init()

        panel.appearance = settings.appearance.nsAppearance
        panel.keyEquivalentHandler = { [weak self] in self?.handleKeyEquivalent($0) ?? false }
        panel.onEscape = { [weak self] in self?.hide() }
        panel.onResignKey = { [weak self] in self?.autoHide() }

        textView.delegate = self
        textView.onEscape = { [weak self] in self?.hide() }
        textView.placeholder = "Start typing…   ⌘D timestamp · ⌘L checkbox · esc hides"

        editor.stampButton.onClick = { [weak self] in self?.insertTimestamp() }
        editor.externalButton.onClick = { [weak self] in self?.openInDefaultEditor() }
        editor.pinButton.onClick = { [weak self] in self?.keepOpen.toggle() }
        editor.closeButton.onClick = { [weak self] in self?.hide() }
        editor.pathButton.onClick = { [weak self] in self?.revealInFinder() }
        editor.statusButton.onClick = { [weak self] in self?.revealConflictBackup() }
        editor.resizeHandle.onDrag = { [weak self] dy in
            guard let self else { return }
            self.panel.setHeight(self.panel.contentHeight - dy)
        }
        editor.resizeHandle.onEnd = { [weak self] in
            guard let self else { return }
            self.settings.visorHeight = Double(self.panel.contentHeight)
        }
        editor.pinButton.isActive = settings.keepOpenWhenUnfocused
        editor.setHints(hotKey: hotKeyTitle)

        session = NoteSession(url: settings.notesURL, textView: textView)
        session.onStatus = { [weak self] in self?.editor.setStatus($0) }
        session.onExternalChange = { [weak self] in self?.updateStats() }
        editor.setStatus(.saved)
        editor.setPath(Settings.displayPath(settings.notesURL))
        session.open()
        updateStats()
    }

    // MARK: - Show / hide

    func toggle() {
        panel.isShown ? hide() : show()
    }

    /// Toggle from a click on the menu bar icon. Clicking the icon steals focus from the
    /// visor first, which auto-hides it; don't immediately re-open it in that case.
    func toggleFromStatusItem() {
        if !panel.isShown, Date().timeIntervalSince(lastAutoHide) < 0.3 { return }
        toggle()
    }

    func show() {
        let screen = screenUnderMouse()
        let notch = settings.animation == .notch ? screen.notch : nil
        panel.show(on: screen, height: preferredHeight(for: screen), notch: notch,
                   animated: settings.animation != .instant, reduceMotion: reduceMotion)
        if !(panel.firstResponder is NSTextView) {
            panel.makeFirstResponder(textView)
        }
        startClickMonitor()
        // The watcher keeps us in sync; this is only a safety net, so don't let a file
        // read delay the animation: do it on the next run loop pass.
        DispatchQueue.main.async { [weak self] in self?.session.syncFromDisk() }
    }

    func hide() {
        guard panel.isShown else { return }
        stopClickMonitor()
        session.flush()
        panel.hide(reduceMotion: reduceMotion)
    }

    private func autoHide() {
        guard panel.isShown, !settings.keepOpenWhenUnfocused else { return }
        lastAutoHide = Date()
        hide()
    }

    private func startClickMonitor() {
        stopClickMonitor()
        // Clicks in other apps. Mouse-only global monitors need no special permission.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) {
            [weak self] _ in
            guard let self, self.panel.isShown,
                  !NSMouseInRect(NSEvent.mouseLocation, self.panel.frame, false) else { return }
            self.autoHide()
        }
    }

    private func stopClickMonitor() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }

    private func screenUnderMouse() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func preferredHeight(for screen: NSScreen) -> CGFloat {
        if settings.visorHeight > 0 { return CGFloat(settings.visorHeight) }
        return min(max(screen.visibleFrame.height * 0.42, 300), 620)
    }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    // MARK: - File

    func flush() { session.flush() }

    func switchNotes(to url: URL) {
        session.switchTo(url)
        editor.setPath(Settings.displayPath(url))
        updateStats()
    }

    func openInDefaultEditor() {
        session.flush()
        NSWorkspace.shared.open(session.file.url)
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([session.file.url])
    }

    private func revealConflictBackup() {
        if case .conflict(let url) = session.status {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    // MARK: - Text

    func textDidChange(_ notification: Notification) {
        session.textDidChange()
        scheduleStats()
    }

    private func scheduleStats() {
        statsTimer?.invalidate()
        let timer = Timer(timeInterval: 0.15, repeats: false) { [weak self] _ in self?.updateStats() }
        RunLoop.main.add(timer, forMode: .common)
        statsTimer = timer
    }

    private func updateStats() {
        statsTimer?.invalidate()
        editor.setStats(TextOps.stats(of: editor.storage.mutableString))
    }

    private func insertTimestamp() {
        panel.makeFirstResponder(textView)
        textView.insertTimestamp()
    }

    private func setFontSize(_ size: Double) {
        let clamped = min(max(size, 9), 32)
        settings.fontSize = clamped
        highlighter.setFontSize(CGFloat(clamped))
        textView.baseAttributes = highlighter.baseAttributes
        highlighter.highlightAll(editor.storage)
    }

    // MARK: - Shortcuts

    /// All visor shortcuts live here. They're resolved before the menu system, which doesn't
    /// reliably see key equivalents while the app isn't active (non-activating panel).
    private func handleKeyEquivalent(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let isReturn = event.keyCode == 36 || event.keyCode == 76

        if flags == .command {
            if isReturn { hide(); return true }
            switch key {
            case "c": return perform(#selector(NSText.copy(_:)))
            case "x": return perform(#selector(NSText.cut(_:)))
            case "v": return perform(#selector(NSText.paste(_:)))
            case "a": return perform(#selector(NSText.selectAll(_:)))
            case "z": return perform(Selector(("undo:")))
            case "s": session.flush(); return true
            case "d": insertTimestamp(); return true
            case "l": panel.makeFirstResponder(textView); textView.toggleTask(); return true
            case "f": textFinder(.showFindInterface); return true
            case "g": textFinder(.nextMatch); return true
            case "e": textFinder(.setSearchString); return true
            case "o": openInDefaultEditor(); return true
            case "w": hide(); return true
            case "q": NSApp.terminate(nil); return true
            case "=", "+": setFontSize(settings.fontSize + 1); return true
            case "-": setFontSize(settings.fontSize - 1); return true
            case "0": setFontSize(Settings.defaultFontSize); return true
            default: return false
            }
        }
        if flags == [.command, .shift] {
            switch key {
            case "z": return perform(Selector(("redo:")))
            case "g": textFinder(.previousMatch); return true
            case "+": setFontSize(settings.fontSize + 1); return true // ⌘+ on layouts where + needs shift
            default: return false
            }
        }
        return false
    }

    /// Sends an action up the responder chain from the focused view (editor or find field).
    private func perform(_ action: Selector) -> Bool {
        guard let responder = panel.firstResponder else { return false }
        return responder.tryToPerform(action, with: nil)
    }

    private func textFinder(_ action: NSTextFinder.Action) {
        let item = NSMenuItem()
        item.tag = action.rawValue
        textView.performTextFinderAction(item)
    }
}
