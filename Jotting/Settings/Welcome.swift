//
//  Welcome.swift
//  Jotting
//
//  Created by Serhiy Mytrovtsiy on 21/11/2026.
//  Using Swift 6.0.
//  Running on macOS 27.2.
//
//  Copyright © 2026 Serhiy Mytrovtsiy. All rights reserved.
//

import AppKit

final class WelcomeView: NSView {
    private enum Step: Int, CaseIterable {
        case welcome, access, appearance
    }
    
    private static let cardWidth: CGFloat = 394
    
    private let configuration: ConfigurationStore
    private let applyInterface: (Configuration.InterfaceKeys, String) -> Void
    private let applyApplication: (Configuration.ApplicationKeys, Bool) -> Void
    private let finish: () -> Void
    
    private let scroll = NSScrollView()
    private let document = WelcomeDocument()
    private let card = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: WelcomeView.cardWidth, height: 1))
    private let content = NSStackView()
    private let tint = CAGradientLayer()
    private let divider = NSBox()
    
    private var pendingThemeScroll = false
    private var cards: [WelcomeOption] = []
    private var switches: [Configuration.ApplicationKeys: NSSwitch] = [:]
    private var subtitle: NSTextField?
    private var schemeAndStyle: NSStackView?
    private var displayedShortcut: Shortcut?
    private var step = Step.welcome
    
    override var acceptsFirstResponder: Bool { true }
    
    init(configuration: ConfigurationStore, applyInterface: @escaping (Configuration.InterfaceKeys, String) -> Void,
         applyApplication: @escaping (Configuration.ApplicationKeys, Bool) -> Void, finish: @escaping () -> Void) {
        self.configuration = configuration
        self.applyInterface = applyInterface
        self.applyApplication = applyApplication
        self.finish = finish
        super.init(frame: .zero)
        
        self.scroll.drawsBackground = false
        self.scroll.hasVerticalScroller = true
        self.scroll.autohidesScrollers = true
        self.scroll.documentView = self.document
        self.addSubview(self.scroll)
        
        self.card.material = .popover
        self.card.blendingMode = .withinWindow
        self.card.wantsLayer = true
        self.card.layer?.cornerRadius = 18
        self.card.layer?.masksToBounds = true
        self.card.layer?.borderWidth = 1
        self.card.layer?.borderColor = NSColor.separatorColor.cgColor
        
        self.tint.actions = ["bounds": NSNull(), "position": NSNull()]
        self.tint.colors = [NSColor.systemYellow.withAlphaComponent(0.13).cgColor, NSColor.clear.cgColor]
        self.tint.startPoint = CGPoint(x: 0, y: 1)
        self.tint.endPoint = CGPoint(x: 0.5, y: 0.5)
        self.card.layer?.addSublayer(self.tint)
        
        self.divider.boxType = .separator
        self.card.addSubview(self.divider)
        self.document.addSubview(self.card)
        
        self.content.orientation = .vertical
        self.content.alignment = .leading
        self.content.spacing = 14
        self.content.translatesAutoresizingMaskIntoConstraints = false
        self.card.addSubview(self.content)
        NSLayoutConstraint.activate([
            self.content.leadingAnchor.constraint(equalTo: self.card.leadingAnchor, constant: 24),
            self.content.trailingAnchor.constraint(equalTo: self.card.trailingAnchor, constant: -24),
            self.content.topAnchor.constraint(equalTo: self.card.topAnchor, constant: 24)
        ])
        
        self.showStep()
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }
    
    override func layout() {
        super.layout()
        self.scroll.frame = self.bounds
        let size = self.scroll.contentSize
        guard size.width > 48, size.height > 0 else {
            return
        }
        
        let width = min(Self.cardWidth, size.width - 28)
        self.subtitle?.preferredMaxLayoutWidth = max(1, width - 48)
        if let row = self.schemeAndStyle {
            let horizontal = width >= 358
            row.orientation = horizontal ? .horizontal : .vertical
            row.alignment = horizontal ? .top : .leading
        }
        
        self.card.setFrameSize(NSSize(width: width, height: self.card.frame.height))
        let height = ceil(self.content.fittingSize.height) + 36
        self.document.frame.size = NSSize(width: size.width, height: max(size.height, height + 28))
        self.card.frame = NSRect(x: (size.width - width) / 2, y: (self.document.frame.height - height) / 2, width: width, height: height)
        
        if let footer = self.content.arrangedSubviews.last {
            let y = ceil(footer.fittingSize.height) + 24
            self.divider.frame = NSRect(x: 0, y: y, width: width, height: 1)
            self.tint.frame = NSRect(x: 0, y: y, width: width, height: max(0, height - y))
        }
        
        if self.pendingThemeScroll {
            self.pendingThemeScroll = false
            DispatchQueue.main.async { [weak self] in self?.scrollToSelectedTheme() }
        }
    }
    
    private func scrollToSelectedTheme() {
        guard let selected = self.cards.first(where: { $0.key == .theme && $0.state == .on }),
            let row = selected.superview, let scroll = selected.enclosingScrollView else {
            return
        }
        
        scroll.layoutSubtreeIfNeeded()
        let x = min(max(0, selected.frame.midX - scroll.contentSize.width / 2), max(0, row.bounds.width - scroll.contentSize.width))
        scroll.contentView.scroll(to: NSPoint(x: x, y: 0))
        scroll.reflectScrolledClipView(scroll.contentView)
    }
    
    override func resetCursorRects() {
        super.resetCursorRects()
        self.addCursorRect(self.visibleRect, cursor: .arrow)
    }
    
    private func stack(_ views: [NSView], vertical: Bool = false, spacing: CGFloat = 8) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = vertical ? .vertical : .horizontal
        stack.alignment = vertical ? .leading : .centerY
        stack.spacing = spacing
        stack.detachesHiddenViews = false
        return stack
    }
    
    private func label(_ text: String, size: CGFloat = 13, secondary: Bool = false) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: size)
        label.textColor = secondary ? .secondaryLabelColor : .labelColor
        return label
    }
    
    private func addRow(_ view: NSView) {
        self.content.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: self.content.widthAnchor).isActive = true
    }
    
    private func showStep() {
        self.content.arrangedSubviews.forEach { $0.removeFromSuperview() }
        self.switches.removeAll()
        self.cards.removeAll()
        self.schemeAndStyle = nil
        
        switch self.step {
        case .welcome:
            self.addHeader("Welcome to Jotting", description:
                "Your plain-text notes save automatically as you type. When you reopen Jotting, it restores your windows and tabs.")
            self.addShortcuts()
        case .access:
            self.addHeader("Launch and access", description: "Choose when Jotting starts and where its icon appears.")
            self.addSwitch(.menuBar, "Show in menu bar", "Open your scratchpad from the menu bar.")
            self.addSwitch(.launchAtLogin, "Launch at login", "Start Jotting when you sign in to your Mac.")
            self.addSwitch(.dockIcon, "Show in Dock", "Keep Jotting’s icon in the Dock while it’s running.")
        case .appearance:
            self.addHeader("Make it yours", description: "Choose the colors, style, and line markers for your scratchpad.")
            self.addAppearanceOptions()
        }
        
        self.addNavigation()
        self.refresh()
        self.needsLayout = true
        self.scroll.contentView.scroll(to: .zero)
        self.window?.makeFirstResponder(self)
    }
    
    private func addHeader(_ name: String, description: String) {
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 56).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 56).isActive = true
        let progress = self.label("Step \(self.step.rawValue + 1) of \(Step.allCases.count)", size: 11, secondary: true)
        self.addRow(self.stack([icon, NSView(), progress]))
        
        let title = self.label(name)
        let font = NSFont.systemFont(ofSize: 28, weight: .bold)
        title.font = font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 28) } ?? font
        
        let subtitle = self.label(description, size: self.step == .welcome ? 13 : 11, secondary: true)
        self.subtitle = subtitle
        let header = self.stack([title, subtitle], vertical: true, spacing: self.step == .welcome ? 14 : 4)
        self.addRow(header)
        subtitle.widthAnchor.constraint(equalTo: header.widthAnchor).isActive = true
        self.content.setCustomSpacing(24, after: header)
    }
    
    private func addShortcuts() {
        self.displayedShortcut = self.configuration.value.globalShortcut
        var shortcuts = [("New tab", "⌘T"), ("Rename a tab", "Double-click its name")]
        if let shortcut = self.displayedShortcut {
            shortcuts.append(("Show or close scratchpad", shortcut.display))
        }
        
        for (name, shortcut) in shortcuts {
            self.addRow(self.stack([self.label(name), NSView(), self.label(shortcut, secondary: true)]))
        }
    }
    
    private func addAppearanceOptions() {
        let scheme = self.options("Color scheme", .appearance, Appearance.allCases.map(\.rawValue))
        let style = self.options("Interface style", .interfaceStyle, InterfaceStyle.allCases.map(\.rawValue))
        let row = self.stack([scheme, NSView(), style], spacing: 4)
        self.schemeAndStyle = row
        self.addRow(row)
        
        self.addRow(self.options("Line marker", .lineMarker, LineMarker.allCases.map(\.rawValue)))
        self.addRow(self.themeOptions())
        self.addRow(self.label("Change these anytime in Settings (⌘,).", size: 11, secondary: true))
    }
    
    private func addNavigation() {
        if let last = self.content.arrangedSubviews.last {
            self.content.setCustomSpacing(46, after: last)
        }
        
        let back = NSButton(title: self.step == .welcome ? "Skip setup" : "Back", target: self, action: #selector(self.back))
        let next = NSButton(title: self.step == .appearance ? "Start writing" : "Continue", target: self, action: #selector(self.nextStep))
        for button in [back, next] {
            button.controlSize = .large
            if #available(macOS 26, *) {
                button.borderShape = .capsule
            }
        }
        
        next.image = NSImage(systemSymbolName: self.step == .appearance ? "pencil" : "arrow.right", accessibilityDescription: nil)
        next.imagePosition = .imageTrailing
        next.keyEquivalent = "\r"
        self.addRow(self.stack([back, NSView(), next]))
    }
    
    @objc private func back() {
        guard let previous = Step(rawValue: self.step.rawValue - 1) else {
            self.finish()
            return
        }
        
        self.step = previous
        self.showStep()
    }
    
    @objc private func nextStep() {
        guard let next = Step(rawValue: self.step.rawValue + 1) else {
            self.finish()
            return
        }
        
        self.step = next
        self.showStep()
    }
    
    private func addSwitch(_ key: Configuration.ApplicationKeys, _ title: String, _ subtitle: String) {
        let control = NSSwitch()
        control.setAccessibilityLabel(title)
        control.target = self
        control.action = #selector(self.toggle)
        self.switches[key] = control
        
        let detail = self.label(subtitle, size: 11, secondary: true)
        let labels = self.stack([self.label(title), detail], vertical: true, spacing: 2)
        self.addRow(self.stack([labels, NSView(), control]))
    }
    
    @objc private func toggle(_ sender: NSSwitch) {
        guard let key = self.switches.first(where: { $0.value === sender })?.key else {
            return
        }
        
        self.applyApplication(key, sender.state == .on)
        self.refresh()
    }
    
    private func options(_ title: String, _ key: Configuration.InterfaceKeys, _ values: [String]) -> NSStackView {
        let buttons = values.map { self.optionButton(key, value: $0) }
        return self.optionGroup(title, content: self.stack(buttons, spacing: 6))
    }
    
    private func themeOptions() -> NSStackView {
        let directory = self.configuration.themes
        let buttons = Theme.identifiers(in: directory).compactMap { id -> WelcomeOption? in
            guard let theme = try? Theme.load(id, directory: directory) else {
                return nil
            }
            
            return self.optionButton(.theme, value: id, theme: theme)
        }
        
        let row = self.stack(buttons, spacing: 6)
        row.frame.size = row.fittingSize
        
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = true
        scroll.documentView = row
        
        let group = self.optionGroup("Themes", content: scroll)
        let scrollerHeight = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
        NSLayoutConstraint.activate([
            scroll.heightAnchor.constraint(equalToConstant: row.frame.height + scrollerHeight),
            scroll.widthAnchor.constraint(equalTo: group.widthAnchor)
        ])
        return group
    }
    
    private func optionButton(_ key: Configuration.InterfaceKeys, value: String, theme: Theme? = nil) -> WelcomeOption {
        let button = WelcomeOption(key: key, value: value, theme: theme)
        button.target = self
        button.action = #selector(self.choose)
        self.cards.append(button)
        return button
    }
    
    private func optionGroup(_ title: String, content: NSView) -> NSStackView {
        let heading = self.label(title)
        heading.font = .boldSystemFont(ofSize: 13)
        return self.stack([heading, content], vertical: true, spacing: 5)
    }
    
    @objc private func choose(_ sender: WelcomeOption) {
        self.window?.makeFirstResponder(sender)
        self.applyInterface(sender.key, sender.value)
        self.refresh()
    }
    
    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard modifiers.isEmpty, event.keyCode == 123 || event.keyCode == 124,
            let card = self.window?.firstResponder as? WelcomeOption, card.key == .theme,
            let row = card.superview as? NSStackView, let index = row.arrangedSubviews.firstIndex(of: card)
        else {
            super.keyDown(with: event)
            return
        }
        
        let next = index + (event.keyCode == 123 ? -1 : 1)
        if row.arrangedSubviews.indices.contains(next), let button = row.arrangedSubviews[next] as? WelcomeOption {
            self.choose(button)
        }
    }
    
    func refresh() {
        let value = self.configuration.value
        if self.step == .welcome, self.displayedShortcut != value.globalShortcut {
            self.showStep()
            return
        }
        
        self.switches[.menuBar]?.state = value.menuBar ? .on : .off
        self.switches[.launchAtLogin]?.state = value.launchAtLogin ? .on : .off
        self.switches[.dockIcon]?.state = value.dockIcon ? .on : .off
        
        for card in self.cards {
            switch card.key {
            case .appearance: card.state = card.value == value.appearance.rawValue ? .on : .off
            case .interfaceStyle: card.state = card.value == value.interfaceStyle.rawValue ? .on : .off
            case .lineMarker: card.state = card.value == value.lineMarker.rawValue ? .on : .off
            case .theme:
                card.state = card.value == value.theme ? .on : .off
                if card.state == .on {
                    self.pendingThemeScroll = true
                    self.needsLayout = true
                }
            }
            card.needsDisplay = true
        }
    }
}

private final class WelcomeDocument: NSView {
    override var isFlipped: Bool { true }
}

private final class WelcomeOption: NSButton {
    let key: Configuration.InterfaceKeys
    let value: String
    private let theme: Theme?
    
    init(key: Configuration.InterfaceKeys, value: String, theme: Theme?) {
        self.key = key
        self.value = value
        self.theme = theme
        super.init(frame: .zero)
        self.title = theme?.name ?? value.capitalized
        self.isBordered = false
        self.setAccessibilityLabel(self.title)
        self.setAccessibilityRole(.radioButton)
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }
    
    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize {
        NSSize(width: self.theme == nil ? 56 : 108, height: self.theme == nil ? 60 : 78)
    }
    
    override var focusRingMaskBounds: NSRect {
        let rect = self.bounds.insetBy(dx: 2, dy: 2)
        return NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - 17)
    }
    
    private var previewPath: NSBezierPath {
        NSBezierPath(roundedRect: self.focusRingMaskBounds, xRadius: 8, yRadius: 8)
    }
    
    override func drawFocusRingMask() {
        self.previewPath.fill()
    }
    
    override func draw(_ dirtyRect: NSRect) {
        let path = self.previewPath
        let preview = path.bounds
        let dark = self.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if let theme = self.theme {
            self.drawPalette(dark ? theme.dark : theme.light, in: path)
        } else {
            self.drawPane(in: path, dark: dark)
        }
        
        path.lineWidth = self.state == .on ? 2 : 1
        (self.state == .on ? NSColor.controlAccentColor : .separatorColor).setStroke()
        path.stroke()
        if self.state == .on {
            let check = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(paletteColors: [.white, .controlAccentColor]))
            check?.draw(in: NSRect(x: preview.maxX - 14, y: preview.minY + 2, width: 12, height: 12))
        }
        
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        (self.title as NSString).draw(in: NSRect(x: 0, y: preview.maxY + 3, width: self.bounds.width, height: 16),
            withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph])
    }
    
    private func drawPalette(_ palette: Theme.Palette, in path: NSBezierPath) {
        let preview = path.bounds
        palette.background.value.setFill()
        path.fill()
        
        ("Aa" as NSString).draw(at: NSPoint(x: preview.minX + 9, y: preview.minY + 4),
            withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 19, weight: .medium), .foregroundColor: palette.text.value])
            
        let colors = [palette.surface, palette.secondaryText, palette.text, palette.selection, palette.accent]
        for (index, color) in colors.enumerated() {
            color.value.setFill()
            NSBezierPath(ovalIn: NSRect(x: preview.minX + 9 + CGFloat(index) * 11, y: preview.maxY - 19, width: 13, height: 13)).fill()
        }
    }
    
    private func drawPane(in path: NSBezierPath, dark: Bool) {
        let preview = path.bounds
        NSGradient(starting: .systemIndigo, ending: .systemMint)?.draw(in: path, angle: 35)
        let pane = NSRect(x: preview.midX - 15, y: preview.midY - 10, width: 30, height: 20)
        let panel = NSBezierPath(roundedRect: pane, xRadius: 4, yRadius: 4)
        let charcoal = NSColor(white: 0.13, alpha: 1)
        let darkPane = self.key == .appearance ? self.value == Appearance.dark.rawValue : dark
        let fill: NSColor = darkPane ? charcoal : .white
        let glass = self.key == .interfaceStyle && self.value == InterfaceStyle.glass.rawValue
        fill.withAlphaComponent(glass ? 0.42 : 1).setFill()
        panel.fill()
        
        let ink: NSColor = darkPane ? .white : charcoal
        if self.key == .appearance {
            self.drawWindow(in: panel, ink: ink, charcoal: charcoal)
        } else if self.key == .lineMarker {
            self.drawMarker(in: pane, ink: ink)
        }
    }
    
    private func drawWindow(in panel: NSBezierPath, ink: NSColor, charcoal: NSColor) {
        if self.value == Appearance.system.rawValue {
            NSGraphicsContext.saveGraphicsState()
            panel.addClip()
            charcoal.setFill()
            NSRect(x: panel.bounds.midX, y: panel.bounds.minY, width: panel.bounds.width / 2, height: panel.bounds.height).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        
        ink.setFill()
        for index in 0..<3 {
            let dot = NSRect(x: panel.bounds.minX + 3 + CGFloat(index) * 3, y: panel.bounds.minY + 3, width: 2, height: 2)
            NSBezierPath(ovalIn: dot).fill()
        }
    }
    
    private func drawMarker(in pane: NSRect, ink: NSColor) {
        let symbol: String
        switch LineMarker(rawValue: self.value) {
        case .number: symbol = "list.number"
        case .dot: symbol = "list.bullet"
        default: symbol = "text.alignleft"
        }
        
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(paletteColors: [ink]))
        image?.draw(in: NSRect(x: pane.midX - 9, y: pane.midY - 6, width: 18, height: 12))
    }
}
