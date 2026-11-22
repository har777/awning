import AppKit

/// A borderless, non-activating panel that drops down from the top of the screen.
///
/// Non-activating means showing the visor doesn't take activation from the app you were in
/// (the way Spotlight works): no title bars greying out, nothing to "restore" when it hides,
/// and no fighting with macOS 14+ activation rules.
final class VisorPanel: NSPanel {
    var keyEquivalentHandler: ((NSEvent) -> Bool)?
    var onEscape: (() -> Void)?
    var onResignKey: (() -> Void)?

    private(set) var isShown = false
    /// Bumped on every show/hide so a stale animation completion can't act on a newer state.
    private var generation = 0
    private var previousApp: NSRunningApplication?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 900, height: 420),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        animationBehavior = .none
        appearance = NSAppearance(named: .darkAqua)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if keyEquivalentHandler?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }

    // MARK: - Geometry

    static func targetFrame(on screen: NSScreen, height: CGFloat) -> NSRect {
        let area = screen.visibleFrame
        let width = min(max(area.width * 0.72, 560), area.width - 24)
        let h = min(max(height, 220), area.height - 40)
        return NSRect(x: (area.midX - width / 2).rounded(), y: area.maxY - h, width: width.rounded(), height: h)
    }

    /// Resize from the bottom edge, keeping the top pinned under the menu bar.
    func setHeight(_ height: CGFloat) {
        guard let area = screen?.visibleFrame else { return }
        let h = min(max(height, 220), area.height - 40)
        setFrame(NSRect(x: frame.minX, y: frame.maxY - h, width: frame.width, height: h), display: true)
    }

    // MARK: - Show / hide

    func show(on screen: NSScreen, height: CGFloat, reduceMotion: Bool) {
        let target = Self.targetFrame(on: screen, height: height)
        generation += 1
        let token = generation

        if !isVisible {
            previousApp = NSWorkspace.shared.frontmostApplication
        }
        // Start from above the screen edge, unless we're reversing a hide on the same screen
        // (then continue from wherever the animation currently is: no jump).
        if !isVisible || self.screen != screen || frame.width != target.width {
            if reduceMotion {
                setFrame(target, display: false)
                alphaValue = 0
            } else {
                setFrame(target.offsetBy(dx: 0, dy: target.height), display: false)
                alphaValue = 1
            }
        }
        isShown = true
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
        makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = reduceMotion ? 0.1 : 0.15
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            self.animator().setFrame(target, display: true)
            self.animator().alphaValue = 1
        }, completionHandler: { [weak self] in
            guard let self, self.generation == token else { return }
            self.invalidateShadow()
        })
    }

    func hide(reduceMotion: Bool) {
        guard isShown else { return }
        isShown = false
        generation += 1
        let token = generation
        let start = frame

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = reduceMotion ? 0.08 : 0.1
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            if reduceMotion {
                self.animator().alphaValue = 0
            } else {
                self.animator().setFrame(start.offsetBy(dx: 0, dy: start.height), display: true)
            }
        }, completionHandler: { [weak self] in
            guard let self, self.generation == token else { return } // re-shown mid-animation
            self.orderOut(nil)
            self.alphaValue = 1
            // Only needed if something (an alert, the file picker) activated us meanwhile.
            if NSApp.isActive, let previous = self.previousApp, !previous.isTerminated,
               previous != NSRunningApplication.current {
                previous.activate()
            }
        })
    }
}
