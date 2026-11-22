import AppKit

/// Small SF Symbol button with a hover state. Tracking is `.activeAlways` because the
/// visor is a non-activating panel: the app is usually not frontmost while it is shown.
final class IconButton: NSButton {
    var onClick: (() -> Void)?
    var isActive = false { didSet { refresh() } }

    private let normalImage: NSImage?
    private let activeImage: NSImage?
    private var hovering = false

    init(symbol: String, activeSymbol: String? = nil, tooltip: String) {
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        normalImage = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)?.withSymbolConfiguration(config)
        activeImage = activeSymbol.flatMap {
            NSImage(systemSymbolName: $0, accessibilityDescription: tooltip)?.withSymbolConfiguration(config)
        } ?? normalImage
        super.init(frame: NSRect(x: 0, y: 0, width: 26, height: 22))
        title = ""
        isBordered = false
        imagePosition = .imageOnly
        toolTip = tooltip
        target = self
        action = #selector(fire)
        wantsLayer = true
        layer?.cornerRadius = 5
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 26),
            heightAnchor.constraint(equalToConstant: 22),
        ])
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func fire() { onClick?() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; refresh() }
    override func mouseExited(with event: NSEvent) { hovering = false; refresh() }

    private func refresh() {
        image = isActive ? activeImage : normalImage
        contentTintColor = isActive ? Theme.accent : (hovering ? Theme.text : Theme.dim)
        layer?.backgroundColor = hovering ? Theme.hover.cgColor : NSColor.clear.cgColor
    }
}

/// Borderless text button (file path, status) with a hover tint.
final class LinkButton: NSButton {
    var onClick: (() -> Void)?
    var isClickable = true
    private var hovering = false
    private var text = ""
    private var color = Theme.dim
    private var leading: (String, NSColor)?

    init() {
        super.init(frame: .zero)
        title = ""
        isBordered = false
        target = self
        action = #selector(fire)
        translatesAutoresizingMaskIntoConstraints = false
        (cell as? NSButtonCell)?.lineBreakMode = .byTruncatingMiddle
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func set(_ text: String, color: NSColor, leading: (String, NSColor)? = nil) {
        self.text = text
        self.color = color
        self.leading = leading
        render()
    }

    @objc private func fire() { if isClickable { onClick?() } }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; render() }
    override func mouseExited(with event: NSEvent) { hovering = false; render() }

    private func render() {
        let font = Theme.mono(11.5)
        let out = NSMutableAttributedString()
        if let (glyph, glyphColor) = leading {
            out.append(NSAttributedString(string: glyph + " ", attributes: [.font: Theme.mono(9), .foregroundColor: glyphColor,
                                                                           .baselineOffset: 1]))
        }
        let shown = (hovering && isClickable) ? Theme.text : color
        out.append(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: shown]))
        attributedTitle = out
    }
}

/// Bottom-edge grab strip for resizing the visor height.
final class ResizeHandle: NSView {
    var onDrag: ((CGFloat) -> Void)?
    var onEnd: (() -> Void)?
    private var hovering = false { didSet { needsDisplay = true } }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .cursorUpdate],
                                       owner: self))
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.resizeUpDown.set() }
    override func mouseEntered(with event: NSEvent) { hovering = true; NSCursor.resizeUpDown.set() }
    override func mouseExited(with event: NSEvent) { hovering = false; NSCursor.arrow.set() }

    override func mouseDown(with event: NSEvent) {
        var last = NSEvent.mouseLocation
        while let e = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let now = NSEvent.mouseLocation
            onDrag?(now.y - last.y)
            last = now
            if e.type == .leftMouseUp { break }
        }
        onEnd?()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard hovering else { return }
        let pill = NSRect(x: bounds.midX - 22, y: 2, width: 44, height: 3)
        NSColor(white: 1, alpha: 0.28).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 1.5, yRadius: 1.5).fill()
    }
}

/// Hairline border that follows the visor's shape (square top, rounded bottom).
final class BorderView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let radius = Theme.cornerRadius - 0.5
        let path = NSBezierPath()
        path.move(to: NSPoint(x: r.minX, y: r.maxY + 1))
        path.line(to: NSPoint(x: r.minX, y: r.minY + radius))
        path.appendArc(withCenter: NSPoint(x: r.minX + radius, y: r.minY + radius), radius: radius,
                       startAngle: 180, endAngle: 270)
        path.line(to: NSPoint(x: r.maxX - radius, y: r.minY))
        path.appendArc(withCenter: NSPoint(x: r.maxX - radius, y: r.minY + radius), radius: radius,
                       startAngle: 270, endAngle: 360)
        path.line(to: NSPoint(x: r.maxX, y: r.maxY + 1))
        Theme.border.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

final class FillView: NSView {
    init(color: NSColor) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = color.cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
