import AppKit

/// How the visor appears.
enum VisorAnimation: String, CaseIterable {
    case slide, notch
    case instant = "none"

    var title: String {
        switch self {
        case .slide: return "Slide Down"
        case .notch: return "Grow from Notch"
        case .instant: return "None"
        }
    }
}

extension NSScreen {
    /// The camera housing at the top of the built-in display on recent MacBooks, in screen
    /// coordinates, or nil if this screen has none.
    var notch: NSRect? {
        if safeAreaInsets.top > 0, let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea {
            let width = frame.width - left.width - right.width
            if width > 0 {
                return NSRect(x: frame.midX - width / 2, y: frame.maxY - safeAreaInsets.top,
                              width: width, height: safeAreaInsets.top)
            }
        }
        // Developer aid for Macs without a notch: pretend the main screen has one.
        if Settings.shared.simulateNotch, self == NSScreen.screens.first {
            let height = max(frame.maxY - visibleFrame.maxY, 24)
            return NSRect(x: frame.midX - 100, y: frame.maxY - height, width: 200, height: height)
        }
        return nil
    }
}

/// The panel's content: hosts the editor and, in notch style, turns the visor into an
/// extension of the notch.
///
/// In notch style the visor hangs from the very top of the screen. A black collar the height
/// of the notch runs along its top edge (over the menu bar), with small flared "ears" at the
/// corners like the notch has. A mask morphs between the notch's outline and the visor's, and a
/// black wash fades out as it grows, so it looks like the notch itself is opening up.
final class VisorContainer: NSView {
    static let ear: CGFloat = 10

    let editor: EditorView
    /// The notch size when in notch style, nil when sliding.
    private(set) var notchSize: CGSize?
    var collarHeight: CGFloat { notchSize?.height ?? 0 }

    private let collar = CALayer()
    private let ink = CALayer()
    private let shape = CAShapeLayer()
    /// Bumped per morph so an interrupted morph's completion is ignored.
    private var morphID = 0
    private var isMorphing = false

    init(editor: EditorView) {
        self.editor = editor
        super.init(frame: editor.frame)
        wantsLayer = true
        addSubview(editor)
        for layer in [collar, ink] {
            layer.backgroundColor = NSColor.black.cgColor
            layer.zPosition = 100
            self.layer?.addSublayer(layer)
        }
        ink.opacity = 0
        collar.isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Switch between notch style (`notch` = the notch's size) and the plain slide style.
    func configure(notch: CGSize?) {
        guard notch != notchSize else { return }
        notchSize = notch
        withoutAnimation {
            collar.isHidden = notch == nil
            ink.opacity = 0
            layer?.mask = notch == nil ? nil : shape
        }
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    override func layout() {
        super.layout()
        let ear = notchSize == nil ? 0 : Self.ear
        editor.frame = NSRect(x: ear, y: 0, width: bounds.width - 2 * ear, height: bounds.height - collarHeight)
        withoutAnimation {
            collar.frame = CGRect(x: 0, y: bounds.height - collarHeight, width: bounds.width, height: collarHeight)
            ink.frame = bounds
            shape.frame = bounds
            if notchSize != nil, !isMorphing { shape.path = openPath }
        }
    }

    // MARK: - Morphing

    /// Snap to the closed state (just the notch, all black), ready to grow.
    func close() {
        withoutAnimation {
            shape.removeAllAnimations()
            ink.removeAllAnimations()
            shape.path = closedPath
            ink.opacity = 1
        }
    }

    /// Snap to the fully open state.
    func open() {
        withoutAnimation {
            shape.removeAllAnimations()
            ink.removeAllAnimations()
            shape.path = openPath
            ink.opacity = 0
        }
    }

    /// Grow out of the notch (`opening`) or shrink back into it, continuing from wherever an
    /// interrupted morph had got to.
    func morph(opening: Bool, completion: @escaping () -> Void) {
        morphID += 1
        let id = morphID
        isMorphing = true

        let fromPath = shape.presentation()?.path ?? shape.path ?? (opening ? closedPath : openPath)
        let toPath = opening ? openPath : closedPath
        let pathAnimation: CABasicAnimation
        if opening {
            let spring = CASpringAnimation(keyPath: "path")
            spring.mass = 1
            spring.stiffness = 340
            spring.damping = 30
            spring.duration = spring.settlingDuration
            pathAnimation = spring
        } else {
            pathAnimation = CABasicAnimation(keyPath: "path")
            pathAnimation.duration = 0.2
            pathAnimation.timingFunction = CAMediaTimingFunction(controlPoints: 0.5, 0, 0.8, 0.4)
        }
        pathAnimation.fromValue = fromPath
        pathAnimation.toValue = toPath

        // The black wash: lifts once the shape has grown a bit; returns quickly when closing.
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = ink.presentation()?.opacity ?? ink.opacity
        fade.toValue = opening ? 0 : 1
        fade.duration = opening ? 0.22 : 0.1
        if opening {
            fade.beginTime = ink.convertTime(CACurrentMediaTime(), from: nil) + 0.1
            fade.fillMode = .backwards
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, self.morphID == id else { return }
            self.isMorphing = false
            completion()
        }
        shape.path = toPath
        shape.add(pathAnimation, forKey: "morph")
        ink.opacity = opening ? 0 : 1
        ink.add(fade, forKey: "fade")
        CATransaction.commit()
    }

    private var openPath: CGPath {
        Self.silhouette(in: bounds, width: bounds.width - 2 * Self.ear, height: bounds.height,
                        ear: Self.ear, radius: Theme.cornerRadius)
    }

    private var closedPath: CGPath {
        let size = notchSize ?? .zero
        return Self.silhouette(in: bounds, width: size.width, height: size.height,
                               ear: min(6, size.height / 3), radius: min(10, size.height / 3))
    }

    /// An outline hanging from the top edge, centred: flared ears at the top corners and
    /// rounded bottom corners. Always built from the same elements, so Core Animation can
    /// interpolate between any two of them.
    static func silhouette(in bounds: CGRect, width: CGFloat, height: CGFloat, ear: CGFloat, radius: CGFloat) -> CGPath {
        let top = bounds.maxY, bottom = top - height
        let left = bounds.midX - width / 2, right = bounds.midX + width / 2
        let r = max(0, min(radius, width / 2, height / 2))
        let e = max(0, min(ear, height - r))
        let path = CGMutablePath()
        path.move(to: CGPoint(x: left - e, y: top))
        path.addQuadCurve(to: CGPoint(x: left, y: top - e), control: CGPoint(x: left, y: top))
        path.addLine(to: CGPoint(x: left, y: bottom + r))
        path.addQuadCurve(to: CGPoint(x: left + r, y: bottom), control: CGPoint(x: left, y: bottom))
        path.addLine(to: CGPoint(x: right - r, y: bottom))
        path.addQuadCurve(to: CGPoint(x: right, y: bottom + r), control: CGPoint(x: right, y: bottom))
        path.addLine(to: CGPoint(x: right, y: top - e))
        path.addQuadCurve(to: CGPoint(x: right + e, y: top), control: CGPoint(x: right, y: top))
        path.closeSubpath()
        return path
    }

    private func withoutAnimation(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }
}
