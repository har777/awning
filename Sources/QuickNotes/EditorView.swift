import AppKit
import QuickNotesCore

/// The visor's content: header (title, file, status, actions), editor, footer (stats, hints).
final class EditorView: NSView {
    let storage = NSTextStorage()
    let textView: NoteTextView
    let scrollView = NSScrollView()

    let pathButton = LinkButton()
    let statusButton = LinkButton()
    let stampButton = IconButton(symbol: "clock", tooltip: "Insert timestamp (⌘D)")
    let externalButton = IconButton(symbol: "arrow.up.forward.square", tooltip: "Open in default editor (⌘O)")
    let pinButton = IconButton(symbol: "pin", activeSymbol: "pin.fill", tooltip: "Keep open when focus leaves")
    let closeButton = IconButton(symbol: "chevron.up", tooltip: "Hide (esc)")
    let resizeHandle = ResizeHandle()

    private let statsLabel = NSTextField(labelWithString: "")
    private let hintsLabel = NSTextField(labelWithString: "")
    private let numberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()

    init(highlighter: Highlighter) {
        // TextKit 1 with non-contiguous layout: jumping to the end of a large file
        // doesn't require laying out everything before it.
        let layoutManager = NSLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 2
        layoutManager.addTextContainer(container)
        textView = NoteTextView(frame: .zero, textContainer: container)
        storage.delegate = highlighter

        super.init(frame: NSRect(x: 0, y: 0, width: 900, height: 420))
        buildBackground()
        buildEditor(highlighter: highlighter)
        buildChrome()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Build

    private func buildBackground() {
        wantsLayer = true
        layer?.cornerRadius = Theme.cornerRadius
        layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner] // bottom corners only
        layer?.masksToBounds = true

        let blur = NSVisualEffectView(frame: bounds)
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active // the app is rarely "active"; don't let the material go flat
        blur.autoresizingMask = [.width, .height]
        addSubview(blur)

        let tint = FillView(color: Theme.background)
        tint.frame = bounds
        tint.autoresizingMask = [.width, .height]
        addSubview(tint)
    }

    private func buildEditor(highlighter: Highlighter) {
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 16, height: 12)
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFontPanel = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false // the highlighter adds links
        textView.smartInsertDeleteEnabled = false
        textView.insertionPointColor = Theme.accent
        textView.selectedTextAttributes = [.backgroundColor: Theme.selection]
        textView.linkTextAttributes = [
            .foregroundColor: Theme.accent,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand,
        ]
        textView.baseAttributes = highlighter.baseAttributes

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.scrollerKnobStyle = .light
        scrollView.documentView = textView
        addSubview(scrollView)
    }

    private func buildChrome() {
        let prompt = label("›_", Theme.accent, Theme.mono(13, .bold))
        let title = label("quicknotes", Theme.text, Theme.mono(12.5, .semibold))
        pathButton.toolTip = "Reveal in Finder"
        // The path truncates first; the status line should stay readable.
        statusButton.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        let left = NSStackView(views: [prompt, title, pathButton])
        left.orientation = .horizontal
        left.spacing = 8
        left.setCustomSpacing(12, after: title)
        left.translatesAutoresizingMaskIntoConstraints = false
        left.setHuggingPriority(.defaultLow, for: .horizontal)

        let right = NSStackView(views: [statusButton, stampButton, externalButton, pinButton, closeButton])
        right.orientation = .horizontal
        right.spacing = 2
        right.setCustomSpacing(12, after: statusButton)
        right.translatesAutoresizingMaskIntoConstraints = false

        let topRule = FillView(color: Theme.hairline)
        let bottomRule = FillView(color: Theme.hairline)
        [topRule, bottomRule, statsLabel, hintsLabel, resizeHandle].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        statsLabel.font = Theme.mono(11)
        statsLabel.textColor = Theme.faint
        hintsLabel.font = Theme.mono(11)
        hintsLabel.textColor = Theme.faint
        hintsLabel.alignment = .right
        hintsLabel.lineBreakMode = .byTruncatingHead
        hintsLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        [left, right, topRule, bottomRule, statsLabel, hintsLabel].forEach(addSubview)
        addSubview(resizeHandle)

        let border = BorderView()
        border.frame = bounds
        border.autoresizingMask = [.width, .height]
        addSubview(border)

        let headerHeight: CGFloat = 38
        let footerHeight: CGFloat = 28
        NSLayoutConstraint.activate([
            left.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            left.centerYAnchor.constraint(equalTo: topAnchor, constant: headerHeight / 2),
            right.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            right.centerYAnchor.constraint(equalTo: left.centerYAnchor),
            left.trailingAnchor.constraint(lessThanOrEqualTo: right.leadingAnchor, constant: -16),

            topRule.topAnchor.constraint(equalTo: topAnchor, constant: headerHeight),
            topRule.leadingAnchor.constraint(equalTo: leadingAnchor),
            topRule.trailingAnchor.constraint(equalTo: trailingAnchor),
            topRule.heightAnchor.constraint(equalToConstant: 1),

            scrollView.topAnchor.constraint(equalTo: topRule.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomRule.topAnchor),

            bottomRule.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -footerHeight),
            bottomRule.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomRule.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomRule.heightAnchor.constraint(equalToConstant: 1),

            statsLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            statsLabel.centerYAnchor.constraint(equalTo: bottomAnchor, constant: -footerHeight / 2),
            hintsLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            hintsLabel.centerYAnchor.constraint(equalTo: statsLabel.centerYAnchor),
            hintsLabel.leadingAnchor.constraint(greaterThanOrEqualTo: statsLabel.trailingAnchor, constant: 24),

            resizeHandle.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.cornerRadius),
            resizeHandle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Theme.cornerRadius),
            resizeHandle.bottomAnchor.constraint(equalTo: bottomAnchor),
            resizeHandle.heightAnchor.constraint(equalToConstant: 7),
        ])
    }

    private func label(_ text: String, _ color: NSColor, _ font: NSFont) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = font
        l.textColor = color
        l.setContentCompressionResistancePriority(.required, for: .horizontal)
        return l
    }

    // MARK: - Updates

    func setPath(_ path: String) {
        pathButton.set(path, color: Theme.dim)
    }

    func setStatus(_ status: NoteStatus) {
        statusButton.isClickable = false
        statusButton.toolTip = nil
        switch status {
        case .saved:
            statusButton.set("saved", color: Theme.faint, leading: ("●", Theme.accent))
        case .edited:
            statusButton.set("editing", color: Theme.faint, leading: ("●", Theme.amber))
        case .missing:
            statusButton.set("file missing · next edit recreates it", color: Theme.amber, leading: ("●", Theme.amber))
        case .readOnly(let message), .error(let message):
            statusButton.set(message, color: Theme.red, leading: ("●", Theme.red))
            statusButton.toolTip = message
        case .conflict(let backup):
            statusButton.set("changed on disk · their copy backed up", color: Theme.amber, leading: ("●", Theme.amber))
            statusButton.toolTip = "Your version was kept. The other version is at\n\(backup.path)\nClick to reveal."
            statusButton.isClickable = true
        }
    }

    func setStats(_ stats: TextOps.Stats) {
        let words = numberFormatter.string(from: NSNumber(value: stats.words)) ?? "\(stats.words)"
        let lines = numberFormatter.string(from: NSNumber(value: stats.lines)) ?? "\(stats.lines)"
        statsLabel.stringValue = "\(words) \(stats.words == 1 ? "word" : "words") · \(lines) \(stats.lines == 1 ? "line" : "lines")"
    }

    func setHints(hotKey: String) {
        hintsLabel.stringValue = "⌘D stamp   ⌘L task   ⌘F find   ⌘⏎ save+hide   \(hotKey) toggle"
    }
}
