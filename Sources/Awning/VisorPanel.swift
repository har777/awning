import AppKit

/// A borderless, non-activating panel that drops down from the top of the screen, either
/// sliding down from under the menu bar or growing out of the notch.
///
/// Non-activating means showing the visor doesn't take activation from the app you were in
/// (the way Spotlight works): no title bars greying out, nothing to "restore" when it hides,
/// and no fighting with macOS 14+ activation rules.
final class VisorPanel: NSPanel {
    var keyEquivalentHandler: ((NSEvent) -> Bool)?
    var onEscape: (() -> Void)?
    var onResignKey: (() -> Void)?

    let container: VisorContainer
    private(set) var isShown = false
    /// Bumped on every show/hide so a stale animation completion can't act on a newer state.
    private var generation = 0
    private var previousApp: NSRunningApplication?
    /// False for the "None" animation: appear and disappear at once.
    private var animated = true

    init(editor: EditorView) {
        container = VisorContainer(editor: editor)
        super.init(contentRect: NSRect(x: 0, y: 0, width: 900, height: 420),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        contentView = container
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
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Don't let AppKit push the window down out of the menu bar / notch area.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

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

    /// The editor's height, without the notch collar.
    var contentHeight: CGFloat { frame.height - container.collarHeight }

    /// Slide style: centred, just under the menu bar. Notch style: hanging from the top of the
    /// screen, centred on the notch, with room for the collar and the ears.
    static func targetFrame(on screen: NSScreen, height: CGFloat, notch: NSRect?) -> NSRect {
        let area = screen.visibleFrame
        let width = min(max(area.width * 0.72, 560), area.width - 24).rounded()
        let h = clampedHeight(height, on: screen)
        guard let notch else {
            return NSRect(x: (area.midX - width / 2).rounded(), y: area.maxY - h, width: width, height: h)
        }
        let ear = VisorContainer.ear
        let total = h + notch.height
        return NSRect(x: (notch.midX - width / 2 - ear).rounded(), y: screen.frame.maxY - total,
                      width: width + 2 * ear, height: total)
    }

    private static func clampedHeight(_ height: CGFloat, on screen: NSScreen) -> CGFloat {
        min(max(height, 220), screen.visibleFrame.height - 40)
    }

    /// Resize from the bottom edge, keeping the top pinned.
    func setHeight(_ height: CGFloat) {
        guard let screen else { return }
        let h = Self.clampedHeight(height, on: screen) + container.collarHeight
        setFrame(NSRect(x: frame.minX, y: frame.maxY - h, width: frame.width, height: h), display: true)
    }

    // MARK: - Show / hide

    /// `notch` is the notch to grow out of, or nil to slide down (or, if not `animated`,
    /// to simply appear under the menu bar).
    func show(on screen: NSScreen, height: CGFloat, notch: NSRect?, animated: Bool, reduceMotion: Bool) {
        let target = Self.targetFrame(on: screen, height: height, notch: notch)
        generation += 1
        let token = generation

        if !isVisible {
            previousApp = NSWorkspace.shared.frontmostApplication
        }
        // Continue from wherever a hide got to if it's the same place and style (no jump);
        // otherwise start from scratch.
        let resume = isVisible && self.screen == screen && frame.width == target.width
            && container.notchSize == notch?.size
        container.configure(notch: notch?.size)
        level = notch == nil ? .floating : .statusBar // above the menu bar, to sit in it
        self.animated = animated

        if !animated {
            setFrame(target, display: false)
            container.open()
            alphaValue = 1
            hasShadow = true
            orderIn()
            invalidateShadow()
        } else if notch != nil {
            showFromNotch(target: target, resume: resume, reduceMotion: reduceMotion, token: token)
        } else {
            slideDown(target: target, resume: resume, reduceMotion: reduceMotion, token: token)
        }
    }

    private func slideDown(target: NSRect, resume: Bool, reduceMotion: Bool, token: Int) {
        if !resume {
            if reduceMotion {
                setFrame(target, display: false)
                alphaValue = 0
            } else {
                setFrame(target.offsetBy(dx: 0, dy: target.height), display: false)
                alphaValue = 1
            }
        }
        hasShadow = true // the notch style turns it off while morphing
        orderIn()

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

    private func showFromNotch(target: NSRect, resume: Bool, reduceMotion: Bool, token: Int) {
        if !resume {
            setFrame(target, display: false)
            container.layoutSubtreeIfNeeded()
            if reduceMotion { container.open() } else { container.close() }
            alphaValue = reduceMotion ? 0 : 1
        }
        hasShadow = false // the shadow can't follow the morph; it comes back once it's open
        orderIn()

        let finish = { [weak self] in
            guard let self, self.generation == token else { return }
            self.hasShadow = true
            self.invalidateShadow()
        }
        if reduceMotion {
            container.open()
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.1
                self.animator().alphaValue = 1
            }, completionHandler: finish)
        } else {
            alphaValue = 1
            container.morph(opening: true, completion: finish)
        }
    }

    private func orderIn() {
        isShown = true
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
        makeKeyAndOrderFront(nil)
    }

    func hide(reduceMotion: Bool) {
        guard isShown else { return }
        isShown = false
        generation += 1
        let token = generation

        let finish = { [weak self] in
            guard let self, self.generation == token else { return } // re-shown mid-animation
            self.orderOut(nil)
            self.alphaValue = 1
            // Only needed if something (an alert, the file picker) activated us meanwhile.
            if NSApp.isActive, let previous = self.previousApp, !previous.isTerminated,
               previous != NSRunningApplication.current {
                previous.activate()
            }
        }

        if !animated {
            finish()
            return
        }
        if container.notchSize != nil, !reduceMotion {
            hasShadow = false
            container.morph(opening: false, completion: finish)
            return
        }
        let start = frame
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = reduceMotion ? 0.08 : 0.1
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            if reduceMotion || self.container.notchSize != nil {
                self.animator().alphaValue = 0
            } else {
                self.animator().setFrame(start.offsetBy(dx: 0, dy: start.height), display: true)
            }
        }, completionHandler: finish)
    }
}
