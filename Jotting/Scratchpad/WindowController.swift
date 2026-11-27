//
//  WindowController.swift
//  Jotting
//
//  Created by Serhiy Mytrovtsiy on 20/11/2026.
//  Using Swift 6.0.
//  Running on macOS 27.2.
//
//  Copyright © 2026 Serhiy Mytrovtsiy. All rights reserved.
//

import AppKit

@MainActor
final class WindowController: NSObject, NSWindowDelegate {
    static let defaultSize = NSSize(width: 760, height: 480)
    private let scratchpad = ScratchpadWindow(
        contentRect: NSRect(origin: .zero, size: WindowController.defaultSize),
        styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered,
        defer: false
    )
    private weak var updateTarget: AnyObject?
    private let updateAction: Selector
    private let config: ConfigurationStore
    private var updateBadge: UpdateBadge?
    
    private let content = NSView()
    private var backdrop: NSVisualEffectView?
    private var backdropTint: BackdropTint?
    private var settingsHelp: SettingsHelpButton?
    private let cornerOverlay = BottomTrailingOverlay()
    private var writerTop: NSLayoutConstraint?
    private let tabAccessory = NSTitlebarAccessoryViewController()
    
    private weak var displayed: NSView?
    private(set) weak var visible: EditorView?
    
    var onToggleWriterMode: (() -> Void)? {
        didSet { self.scratchpad.toggleWriterMode = self.onToggleWriterMode }
    }
    
    var onCycle: ((Int) -> Void)?
    var onFocus: (() -> Void)?
    var shouldClose: (() -> Bool)?
    var onClose: (() -> Void)?
    
    var window: NSWindow { self.scratchpad }
    let tabs = TabBar()
    
    init(config: ConfigurationStore, updateTarget: AnyObject, updateAction: Selector) {
        self.config = config
        self.updateTarget = updateTarget
        self.updateAction = updateAction
        super.init()
        
        self.cornerOverlay.attach(to: self.content)
        self.makeWindow(config.value)
    }
    
    func focus() {
        let window = self.window
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        
        let frame = window.frame
        let titlebar = NSRect(x: frame.minX, y: frame.maxY - 26, width: frame.width, height: 26)
        let reachable = NSScreen.screens.contains { screen in
            let visibleTitlebar = screen.visibleFrame.intersection(titlebar)
            return visibleTitlebar.width >= 80 && visibleTitlebar.height >= 12
        }
        
        if frame.width < window.minSize.width || frame.height < window.minSize.height || !reachable {
            window.setContentSize(Self.defaultSize)
            
            window.center()
        }
        
        window.makeKeyAndOrderFront(nil)
    }
    
    func apply(_ configuration: Configuration) {
        self.applyStyle(configuration.interfaceStyle, to: self.window, writerMode: self.writerTop?.isActive == true)
        self.tabs.applyTheme()
    }
    
    func setUpdate(_ version: String?, installing: Bool) {
        guard let version else {
            self.updateBadge?.removeFromSuperview()
            self.updateBadge = nil
            return
        }
        
        if self.updateBadge == nil {
            let badge = UpdateBadge(title: "", target: self.updateTarget, action: self.updateAction)
            badge.isBordered = false
            badge.controlSize = .small
            badge.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(paletteColors: [.white]))
            self.cornerOverlay.insertArrangedSubview(badge, at: 0)
            self.updateBadge = badge
        }
        self.updateBadge?.attributedTitle = NSAttributedString(
            string: installing ? "Installing a new version…" : "Update available",
            attributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 11, weight: .medium)])
        self.updateBadge?.isEnabled = !installing
        self.updateBadge?.toolTip = installing ? "Installing Jotting \(version)" : "Jotting \(version) is available"
        self.updateBadge?.invalidateIntrinsicContentSize()
    }
    
    func detachEditor() {
        self.scratchpad.welcomeOverlay = nil
        self.visible?.onScrollerWidth = nil
        if self.displayed !== self.visible {
            self.displayed?.removeFromSuperview()
        }
        self.visible?.removeFromSuperview()
        self.displayed = nil
        self.visible = nil
    }
    
    func show(_ state: WindowSession, editor: EditorView, settings: Bool, title: (UUID) -> String) {
        if settings, self.settingsHelp == nil {
            let help = SettingsHelpButton(file: self.config.file)
            self.cornerOverlay.addArrangedSubview(help)
            self.settingsHelp = help
        } else if !settings {
            self.settingsHelp?.removeFromSuperview()
            self.settingsHelp = nil
        }
        self.setWriterMode(editor.writerMode)
        self.window.title = title(state.selected)
        self.resizeTabBar()
        self.tabs.show(state, title: title)
        let view = editor.welcome ?? editor
        if self.displayed !== view {
            self.detachEditor()
            let layers: [NSView] = [editor] + (editor.welcome.map { [$0] } ?? [])
            for view in layers {
                view.translatesAutoresizingMaskIntoConstraints = false
                self.content.addSubview(view, positioned: .below, relativeTo: self.cornerOverlay)
                NSLayoutConstraint.activate([
                    view.topAnchor.constraint(equalTo: self.content.topAnchor),
                    view.bottomAnchor.constraint(equalTo: self.content.bottomAnchor),
                    view.leadingAnchor.constraint(equalTo: self.content.leadingAnchor),
                    view.trailingAnchor.constraint(equalTo: self.content.trailingAnchor)
                ])
            }
            self.scratchpad.welcomeOverlay = editor.welcome
            self.displayed = view
            self.visible = editor
            editor.onScrollerWidth = self.cornerOverlay.setScrollerWidth
            self.cornerOverlay.setScrollerWidth(editor.scrollerWidth)
            self.window.makeFirstResponder(editor.welcome ?? editor.textView)
        }
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        self.onFocus?()
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        self.shouldClose?() ?? true
    }
    
    func windowWillClose(_ notification: Notification) {
        self.detachEditor()
        self.onClose?()
    }
    
    private func setWriterMode(_ enabled: Bool) {
        guard let writerTop, writerTop.isActive != enabled else {
            return
        }
        writerTop.isActive = enabled
        self.window.appearance = enabled ? NSAppearance(named: .aqua) : nil
        self.setHeaderVisible(!enabled)
        self.cornerOverlay.isHidden = enabled
        self.apply(self.config.value)
    }
    
    private func setHeaderVisible(_ visible: Bool) {
        guard self.window.titlebarAccessoryViewControllers.contains(self.tabAccessory) != visible else {
            return
        }
        for button: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            self.window.standardWindowButton(button)?.isHidden = !visible
        }
        if visible {
            self.window.addTitlebarAccessoryViewController(self.tabAccessory)
            self.resizeTabBar()
        } else if let index = self.window.titlebarAccessoryViewControllers.firstIndex(of: self.tabAccessory) {
            self.window.removeTitlebarAccessoryViewController(at: index)
        }
    }
    
    private func updateWriterHeader(at point: NSPoint?) {
        guard self.writerTop?.isActive == true else {
            return
        }
        
        let height = self.window.frame.height
        let headerHeight = self.tabs.window == nil ? 10 : max(self.tabs.frame.height, height - self.window.contentLayoutRect.maxY)
        let header = NSRect(x: 0, y: height - headerHeight, width: self.window.frame.width, height: headerHeight)
        self.setHeaderVisible(point.map(header.contains) ?? false)
    }
    
    private func applyStyle(_ style: InterfaceStyle, to window: NSWindow, writerMode: Bool) {
        let glass = style == .glass && !writerMode
        let background = writerMode ? EditorView.writerBackground : Theme.color(\.background)
        window.isOpaque = !glass
        window.backgroundColor = glass ? .clear : background
        if glass, self.backdrop == nil, let root = window.contentView {
            let backdrop = NSVisualEffectView(frame: root.bounds)
            backdrop.material = .sidebar
            backdrop.blendingMode = .behindWindow
            backdrop.state = .active
            backdrop.autoresizingMask = [.width, .height]
            root.addSubview(backdrop, positioned: .below, relativeTo: self.content)
            self.backdrop = backdrop
            
            let tint = BackdropTint(frame: root.bounds)
            tint.autoresizingMask = [.width, .height]
            root.addSubview(tint, positioned: .above, relativeTo: backdrop)
            self.backdropTint = tint
        } else if !glass {
            self.backdrop?.removeFromSuperview()
            self.backdropTint?.removeFromSuperview()
            self.backdrop = nil
            self.backdropTint = nil
        }
        self.backdropTint?.needsDisplay = true
    }
    
    private func makeWindow(_ configuration: Configuration) {
        let window = self.scratchpad
        window.cycleTab = { [weak self] in self?.onCycle?($0) }
        
        window.updateWriterHeader = { [weak self] in self?.updateWriterHeader(at: $0) }
        window.acceptsMouseMovedEvents = true
        window.title = "Jotting"
        window.minSize = NSSize(width: 280, height: 160)
        window.tabbingMode = .disallowed
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isReleasedWhenClosed = false
        window.delegate = self
        
        let root = NSView(frame: window.contentLayoutRect)
        window.contentView = root
        root.addTrackingArea(NSTrackingArea(rect: .zero, options: [.inVisibleRect, .mouseEnteredAndExited, .activeAlways],
            owner: window, userInfo: nil))
        self.content.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(self.content)
        let guide = window.contentLayoutGuide as? NSLayoutGuide ?? root.safeAreaLayoutGuide
        let normalTop = self.content.topAnchor.constraint(equalTo: guide.topAnchor)
        normalTop.priority = .defaultHigh
        self.writerTop = self.content.topAnchor.constraint(equalTo: root.topAnchor)
        NSLayoutConstraint.activate([
            normalTop,
            self.content.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            self.content.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            self.content.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        self.apply(configuration)
        
        self.tabAccessory.layoutAttribute = .left
        self.tabs.frame.size = NSSize(width: 48, height: 36)
        self.tabAccessory.view = self.tabs
        window.addTitlebarAccessoryViewController(self.tabAccessory)
        
        window.center()
    }
    
    private func resizeTabBar() {
        let window = self.window
        
        let leading = window.standardWindowButton(.zoomButton).map { $0.convert($0.bounds, to: nil).maxX } ?? 70
        let width = max(50, window.frame.width - leading - 14)
        if self.tabs.frame.width != width {
            self.tabs.frame.size.width = width
        }
    }
    
    func windowDidResize(_ notification: Notification) {
        self.resizeTabBar()
    }
    
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        guard let visible, window.firstResponder === visible.textView else {
            return nil
        }
        
        return visible.textView.undoManager
    }
    
}

private final class BackdropTint: NSView {
    override func draw(_ dirtyRect: NSRect) {
        Theme.color(\.background).withAlphaComponent(0.78).setFill()
        dirtyRect.fill(using: .sourceOver)
    }
    
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        self.needsDisplay = true
    }
}

private final class BottomTrailingOverlay: NSStackView {
    private let edgeInset: CGFloat = 16
    private var trailingConstraint: NSLayoutConstraint?
    
    func attach(to content: NSView) {
        self.orientation = .horizontal
        self.alignment = .centerY
        self.spacing = 8
        self.detachesHiddenViews = true
        self.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(self)
        let trailing = self.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -self.edgeInset)
        self.trailingConstraint = trailing
        NSLayoutConstraint.activate([
            trailing,
            self.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -self.edgeInset)
        ])
    }
    
    func setScrollerWidth(_ width: CGFloat) {
        let inset = -self.edgeInset - width
        if self.trailingConstraint?.constant != inset {
            self.trailingConstraint?.constant = inset
        }
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}

private final class UpdateBadge: NSButton {
    private let iconSize: CGFloat = 13
    private let spacing: CGFloat = 7
    private let horizontalInset: CGFloat = 12
    private let verticalInset: CGFloat = 2
    
    override var intrinsicContentSize: NSSize {
        let label = self.attributedTitle.size()
        return NSSize(
            width: ceil(label.width) + self.iconSize + self.spacing + 2 * self.horizontalInset,
            height: ceil(max(label.height, self.iconSize)) + 2 * self.verticalInset)
    }
    
    override func draw(_ dirtyRect: NSRect) {
        let accent = NSColor.controlAccentColor
        if self.isHighlighted {
            (accent.shadow(withLevel: 0.2) ?? accent).setFill()
        } else if self.isEnabled, (self.window as? ScratchpadWindow)?.hoveredBadge === self {
            (accent.highlight(withLevel: 0.12) ?? accent).setFill()
        } else {
            accent.setFill()
        }
        NSBezierPath(roundedRect: self.bounds, xRadius: 7, yRadius: 7).fill()
        
        let icon = NSRect(
            x: self.horizontalInset, y: (self.bounds.height - self.iconSize) / 2,
            width: self.iconSize, height: self.iconSize)
        self.image?.draw(in: icon, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        let label = self.attributedTitle
        label.draw(at: NSPoint(x: icon.maxX + self.spacing, y: (self.bounds.height - label.size().height) / 2))
    }
}

private final class ScratchpadWindow: NSWindow {
    weak var welcomeOverlay: NSView?
    var updateWriterHeader: ((NSPoint?) -> Void)?
    var toggleWriterMode: (() -> Void)?
    var cycleTab: ((Int) -> Void)?
    private var hoveredGutter = false
    var hoveredBadge: UpdateBadge? { self.hoveredButton as? UpdateBadge }
    private weak var hoveredButton: NSButton? {
        didSet {
            if self.hoveredButton !== oldValue {
                (oldValue as? UpdateBadge)?.needsDisplay = true
                self.hoveredBadge?.needsDisplay = true
            }
        }
    }
    
    override func resignKey() {
        super.resignKey()
        self.updateWriterHeader?(nil)
        self.hoveredButton = nil
        self.hoveredGutter = false
    }
    
    override func sendEvent(_ event: NSEvent) {
        super.sendEvent(event)
        
        switch event.type {
        case .mouseMoved, .mouseEntered, .mouseExited, .cursorUpdate:
            self.updateWriterHeader?(event.locationInWindow)
            self.updateCursor(at: event.locationInWindow)
        default: break
        }
    }
    
    private func updateCursor(at location: NSPoint) {
        guard let contentView else {
            return
        }
        
        let point = contentView.superview?.convert(location, from: nil)
        let hit = point.flatMap { contentView.hitTest($0) }
        if let hit, let button = sequence(first: hit, next: { $0.superview })
            .first(where: { $0 is SettingsHelpButton || $0 is UpdateBadge }) as? NSButton {
            self.hoveredButton = button
            self.hoveredGutter = false
            (button.isEnabled ? NSCursor.pointingHand : NSCursor.arrow).set()
            return
        }
        if let welcomeOverlay, welcomeOverlay.visibleRect.contains(welcomeOverlay.convert(location, from: nil)) {
            self.hoveredGutter = false
            self.hoveredButton = nil
            NSCursor.arrow.set()
            return
        }
        guard self.isKeyWindow else {
            return
        }
        
        let wasOverGutter = self.hoveredGutter
        if let editor = hit as? BufferTextView {
            self.hoveredGutter = editor.isInMarkerGutter(editor.convert(location, from: nil))
        } else {
            self.hoveredGutter = false
        }
        
        if self.hoveredGutter {
            NSCursor.arrow.set()
            self.hoveredButton = nil
        } else if wasOverGutter, hit is NSTextView, NSCursor.current == .arrow {
            NSCursor.iBeam.set()
        } else if self.hoveredButton != nil {
            self.hoveredButton = nil
            if NSCursor.current == .pointingHand {
                (hit is NSTextView ? NSCursor.iBeam : NSCursor.arrow).set()
            }
        }
    }
    
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.shift, .control, .option, .command])
        if flags == [.control, .option, .command], event.characters(byApplyingModifiers: [])?.lowercased() == "w" {
            if !event.isARepeat {
                self.toggleWriterMode?()
            }
            return true
        }
        if event.keyCode == 48 && (flags == .control || flags == [.control, .shift]) {
            self.cycleTab?(flags.contains(.shift) ? -1 : 1)
            return true
        }
        
        if super.performKeyEquivalent(with: event) {
            return true
        }
        
        guard flags.contains(.command) else {
            return false
        }
        
        return NSApp.mainMenu?.performKeyEquivalent(with: event) == true
    }
}
