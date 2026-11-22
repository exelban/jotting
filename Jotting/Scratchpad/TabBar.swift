//
//  TabBar.swift
//  Jotting
//
//  Created by Serhiy Mytrovtsiy on 19/11/2026.
//  Using Swift 6.0.
//  Running on macOS 27.2.
//
//  Copyright © 2026 Serhiy Mytrovtsiy. All rights reserved.
//

import AppKit

private final class TabButton: NSButton, NSTextFieldDelegate {
    private let label = NSTextField(labelWithString: "")
    private let hint = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private let closeIcon = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close Tab")
    private let closeHoverIcon = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close Tab")
    var isCurrent = false {
        didSet {
            guard self.isCurrent != oldValue else {
                return
            }
            self.needsDisplay = true
            self.label.textColor = self.isCurrent ? Theme.color(\.labelColor) : Theme.color(\.secondaryText)
            
            self.label.font = .systemFont(ofSize: 12, weight: self.isCurrent ? .medium : .regular)
            self.setAccessibilitySelected(self.isCurrent)
        }
    }
    
    var reorder: ((NSEvent, CGFloat) -> Void)?
    private var originalName: String?
    private weak var previousResponder: NSResponder?
    private lazy var editingWidth = self.label.widthAnchor.constraint(equalTo: self.widthAnchor, constant: -76)
    var rename: ((String) -> Void)?
    var closeTab: (() -> Void)?
    
    private let titleOnly: Bool
    
    init(shortcut: String, titleOnly: Bool) {
        self.titleOnly = titleOnly
        super.init(frame: .zero)
        self.wantsLayer = true
        self.title = ""
        self.controlSize = .regular
        self.isBordered = false
        
        self.label.font = .systemFont(ofSize: 12)
        self.label.textColor = Theme.color(\.secondaryText)
        self.label.lineBreakMode = .byTruncatingTail
        self.label.alignment = .center
        self.label.focusRingType = .none
        self.label.delegate = self
        self.label.cell?.usesSingleLineMode = true
        self.label.setAccessibilityLabel("Tab name")
        
        self.hint.stringValue = shortcut
        self.hint.isHidden = titleOnly
        self.hint.alignment = .right
        self.hint.textColor = Theme.color(\.secondaryText)
        self.hint.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        
        self.closeButton.contentTintColor = Theme.color(\.secondaryText)
        self.closeButton.image = self.closeIcon
        self.closeButton.symbolConfiguration = .init(pointSize: 9, weight: .medium)
        self.closeButton.imageScaling = .scaleNone
        self.closeButton.imagePosition = .imageOnly
        self.closeButton.controlSize = .small
        self.closeButton.isBordered = false
        self.closeButton.toolTip = "Close Tab"
        self.closeButton.target = self
        self.closeButton.action = #selector(self.closeClicked)
        self.closeButton.isHidden = true
        
        self.layoutControls()
    }
    
    private func layoutControls() {
        for view in [self.label, self.hint, self.closeButton] {
            self.addSubview(view)
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        
        self.label.wantsLayer = true
        self.hint.wantsLayer = true
        
        NSLayoutConstraint.activate([
            self.widthAnchor.constraint(greaterThanOrEqualToConstant: 148),
            self.heightAnchor.constraint(equalToConstant: 24),
            self.label.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            self.label.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            self.label.leftAnchor.constraint(greaterThanOrEqualTo: self.closeButton.rightAnchor, constant: 8),
            self.label.rightAnchor.constraint(lessThanOrEqualTo: self.hint.leftAnchor, constant: -8),
            self.closeButton.widthAnchor.constraint(equalToConstant: 20),
            self.closeButton.heightAnchor.constraint(equalToConstant: 20),
            self.closeButton.centerYAnchor.constraint(equalTo: self.centerYAnchor, constant: -0.5),
            self.closeButton.leftAnchor.constraint(equalTo: self.leftAnchor, constant: 8),
            self.hint.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            self.hint.rightAnchor.constraint(equalTo: self.rightAnchor, constant: -10)
        ])
        
        self.hint.setContentHuggingPriority(.required, for: .horizontal)
        self.hint.setContentCompressionResistancePriority(.required, for: .horizontal)
        self.label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }
    
    override func layout() {
        super.layout()
        for field in [self.label, self.hint] {
            field.layer?.setAffineTransform(CGAffineTransform(translationX: 0, y: 0.25))
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !self.titleOnly else {
            return
        }
        
        let shape = NSBezierPath(roundedRect: self.bounds.insetBy(dx: 0, dy: 0.5), xRadius: 12, yRadius: 12)
        if self.isCurrent {
            Theme.color(\.surface).setFill()
            shape.fill()
        } else if !self.closeButton.isHidden {
            Theme.color(\.labelColor).withAlphaComponent(0.06).setFill()
            shape.fill()
        }
    }
    
    func applyTheme() {
        self.label.textColor = self.isCurrent ? Theme.color(\.labelColor) : Theme.color(\.secondaryText)
        self.hint.textColor = Theme.color(\.secondaryText)
        self.closeButton.contentTintColor = Theme.color(\.secondaryText)
        self.needsDisplay = true
    }
    
    func setName(_ name: String) {
        guard self.originalName == nil, self.label.stringValue != name else {
            return
        }
        
        self.label.stringValue = name
        self.toolTip = name
        self.setAccessibilityLabel(name)
        self.closeButton.setAccessibilityLabel("Close " + name)
    }
    
    private func beginRename() {
        guard let window, self.originalName == nil else {
            return
        }
        
        self.previousResponder = window.firstResponder
        self.originalName = self.label.stringValue
        
        self.label.isEditable = true
        self.editingWidth.isActive = true
        self.layoutSubtreeIfNeeded()
        self.label.selectText(nil)
    }
    
    private func finishRename(_ name: String?) {
        guard let originalName else {
            return
        }
        
        self.originalName = nil
        self.label.abortEditing()
        self.label.isEditable = false
        self.label.isSelectable = false
        self.editingWidth.isActive = false
        self.label.stringValue = originalName
        if let name, name != originalName {
            self.rename?(name)
        }
    }
    
    func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
        guard
            command == #selector(NSResponder.insertNewline(_:)) || command == #selector(NSResponder.cancelOperation(_:))
        else {
            return false
        }
        
        self.finishRename(command == #selector(NSResponder.insertNewline(_:)) ? textView.string : nil)
        self.window?.makeFirstResponder(self.previousResponder)
        return true
    }
    
    func controlTextDidEndEditing(_ notification: Notification) {
        self.finishRename(self.label.stringValue)
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else {
            return nil
        }
        
        if self.originalName != nil, hit.isDescendant(of: self.label) || hit === self.label {
            return hit
        }
        
        return hit.isDescendant(of: self.closeButton) || hit === self.closeButton ? self.closeButton : self
    }
    
    func updateHover(at windowPoint: NSPoint?) {
        guard !self.titleOnly else {
            return
        }
        
        let hidden = windowPoint == nil
        if self.closeButton.isHidden != hidden {
            self.closeButton.isHidden = hidden
            self.needsDisplay = true
        }
        
        let overClose = windowPoint.map { self.closeButton.bounds.contains(self.closeButton.convert($0, from: nil)) } ?? false
        let icon = overClose ? self.closeHoverIcon : self.closeIcon
        if self.closeButton.image !== icon {
            self.closeButton.image = icon
            self.closeButton.symbolConfiguration = .init(pointSize: overClose ? 15 : 9, weight: .medium)
        }
    }
    
    @objc private func closeClicked() {
        self.closeTab?()
    }
    
    override func mouseDown(with event: NSEvent) {
        guard let window else {
            return
        }
        
        let start = event.locationInWindow
        let reordering = event.modifierFlags.contains(.option)
        self.highlight(true)
        defer {
            self.highlight(false)
        }
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let point = next.locationInWindow
            if next.type == .leftMouseDragged && hypot(point.x - start.x, point.y - start.y) > 4 {
                if !reordering {
                    window.performDrag(with: event)
                    return
                }
                
                self.highlight(false)
                self.reorder?(next, self.convert(start, from: nil).x)
                return
            }
            
            if next.type == .leftMouseUp {
                if self.bounds.contains(self.convert(point, from: nil)) {
                    if event.clickCount == 2 {
                        self.beginRename()
                    } else {
                        self.performClick(nil)
                    }
                }
                return
            }
        }
    }
    
}

private final class TabRow: NSStackView {
    weak var hovered: TabButton? {
        didSet {
            if oldValue !== self.hovered {
                self.needsDisplay = true
            }
        }
    }
    
    var insertionX: CGFloat? {
        didSet {
            if oldValue != self.insertionX {
                self.needsDisplay = true
            }
        }
    }
    
    override func layout() {
        super.layout()
        self.needsDisplay = true
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        Theme.color(\.labelColor).withAlphaComponent(0.23).setFill()
        for (left, right) in zip(self.arrangedSubviews, self.arrangedSubviews.dropFirst()) {
            if left === self.hovered || right === self.hovered {
                continue
            }
            
            if (left as? TabButton)?.isCurrent == true || (right as? TabButton)?.isCurrent == true {
                continue
            }
            
            let center = (left.frame.maxX + right.frame.minX) / 2
            NSRect(x: center - 0.5, y: self.bounds.midY - 7, width: 1, height: 14).fill()
        }
        
        if let insertionX {
            Theme.color(\.accent).setFill()
            NSBezierPath(
                roundedRect: NSRect(x: insertionX - 1, y: self.bounds.midY - 10, width: 2, height: 20),
                xRadius: 1, yRadius: 1
            ).fill()
        }
    }
}

private final class TabDragPreview: NSWindow {
    private let snapshot: NSImageView
    private let outline: NSView
    
    init(button: TabButton, bitmap: NSBitmapImageRep) {
        let image = NSImage(size: button.bounds.size)
        image.addRepresentation(bitmap)
        self.snapshot = NSImageView(image: image)
        self.outline = NSView(frame: button.bounds)
        super.init(contentRect: button.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        
        self.isOpaque = false
        self.backgroundColor = .clear
        self.ignoresMouseEvents = true
        self.isExcludedFromWindowsMenu = true
        self.animationBehavior = .none
        self.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.draggingWindow)))
        self.isReleasedWhenClosed = false
        
        self.snapshot.wantsLayer = true
        self.snapshot.layer?.backgroundColor = Theme.color(\.surface).cgColor
        self.snapshot.layer?.cornerRadius = button.bounds.height / 2
        self.snapshot.layer?.masksToBounds = true
        
        self.outline.wantsLayer = true
        self.outline.layer?.cornerRadius = 12
        self.outline.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.55).cgColor
        self.outline.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
        self.outline.addSubview(self.snapshot)
        self.contentView = self.outline
    }
    
    func update(for button: TabButton, at point: NSPoint, offset: CGFloat, detachedFrame: NSRect?) {
        if let frame = detachedFrame {
            self.setFrame(frame, display: false)
            let width = min(button.bounds.width, frame.width - 8)
            self.snapshot.frame = NSRect(
                x: (frame.width - width) / 2, y: frame.height - button.bounds.height - 4, width: width, height: button.bounds.height)
            self.snapshot.alphaValue = 0.55
            self.outline.layer?.borderWidth = 1
        } else {
            let origin = NSPoint(x: point.x - offset, y: point.y - button.bounds.midY)
            self.setFrame(NSRect(origin: origin, size: button.bounds.size), display: false)
            self.snapshot.frame = button.bounds
            self.snapshot.alphaValue = 1
            self.outline.layer?.borderWidth = 0
        }
        if !self.isVisible {
            self.orderFront(nil)
        }
    }
}

final class TabBar: NSView {
    private let scroll = NSScrollView()
    private let addButton = NSButton()
    private let row = TabRow()
    private var tracking: NSTrackingArea?
    var select: ((UUID) -> Void)?
    var move: ((UUID, Int) -> Void)?
    var detach: ((UUID, NSRect) -> Void)?
    var rename: ((UUID, String) -> Void)?
    var close: ((UUID) -> Void)?
    var add: (() -> Void)?
    private var ids: [UUID] = []
    
    init() {
        super.init(frame: .zero)
        self.wantsLayer = true
        
        self.row.distribution = .fillEqually
        self.row.spacing = 0
        self.row.edgeInsets = NSEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)
        
        self.scroll.drawsBackground = false
        self.scroll.horizontalScrollElasticity = .none
        self.scroll.documentView = self.row
        
        self.addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New Tab")
        self.addButton.imagePosition = .imageOnly
        self.addButton.symbolConfiguration = .init(pointSize: 11, weight: .medium)
        self.addButton.imageScaling = .scaleNone
        self.addButton.controlSize = .small
        self.addButton.bezelStyle = .circular
        if #available(macOS 26, *) {
            self.addButton.borderShape = .circle
        }
        
        self.addButton.toolTip = "New Tab (⌘T)"
        self.addButton.setAccessibilityLabel("New Tab")
        self.addButton.target = self
        self.addButton.action = #selector(self.newTab)
        
        self.addSubview(self.scroll)
        self.addSubview(self.addButton)
        
        self.row.translatesAutoresizingMaskIntoConstraints = false
        self.row.leadingAnchor.constraint(equalTo: self.scroll.contentView.leadingAnchor).isActive = true
        
        let height = self.row.heightAnchor.constraint(equalTo: self.scroll.contentView.heightAnchor)
        height.priority = .defaultHigh
        height.isActive = true
        
        let width = self.row.widthAnchor.constraint(equalTo: self.scroll.contentView.widthAnchor)
        width.priority = .defaultHigh
        width.isActive = true
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }
    
    override func layout() {
        super.layout()
        let trackWidth = max(0, self.bounds.width - 48)
        self.scroll.frame = NSRect(x: 8, y: self.bounds.midY - 14, width: trackWidth, height: 28)
        self.addButton.frame = NSRect(x: self.scroll.frame.maxX + 4, y: self.bounds.midY - 14, width: 28, height: 28)
        self.needsDisplay = true
    }
    
    override func draw(_ dirtyRect: NSRect) {
        guard self.ids.count > 1 else {
            return
        }
        
        let track = NSBezierPath(roundedRect: self.scroll.frame.insetBy(dx: 0.5, dy: 0.5), xRadius: 14, yRadius: 14)
        Theme.color(\.trackColor).setFill()
        track.fill()
        Theme.color(\.labelColor).withAlphaComponent(0.10).setStroke()
        track.stroke()
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking {
            self.removeTrackingArea(tracking)
        }
        
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil)
        self.addTrackingArea(area)
        self.tracking = area
        self.updateHover(at: self.window?.mouseLocationOutsideOfEventStream)
    }
    
    private func updateHover(at point: NSPoint?) {
        var next: TabButton?
        if let point, self.scroll.bounds.contains(self.scroll.convert(point, from: nil)) {
            let location = self.row.convert(point, from: nil)
            next = self.row.arrangedSubviews.first { $0.frame.contains(location) } as? TabButton
        }
        
        if next !== self.row.hovered {
            self.row.hovered?.updateHover(at: nil)
            self.row.hovered = next
        }
        
        self.row.hovered?.updateHover(at: point)
    }
    
    override func mouseEntered(with event: NSEvent) {
        self.updateHover(at: event.locationInWindow)
    }
    override func mouseMoved(with event: NSEvent) {
        self.updateHover(at: event.locationInWindow)
    }
    override func mouseExited(with event: NSEvent) {
        self.updateHover(at: nil)
    }
    
    private func insertionIndex(at point: NSPoint, for id: UUID) -> Int {
        let trackX = max(self.scroll.frame.minX, min(point.x, self.scroll.frame.maxX))
        let clip = self.scroll.contentView
        if self.row.bounds.width > clip.bounds.width {
            let left = max(0, 16 - (trackX - self.scroll.frame.minX))
            let right = max(0, 16 - (self.scroll.frame.maxX - trackX))
            let offset = max(0, min(clip.bounds.minX + right - left, self.row.bounds.width - clip.bounds.width))
            clip.scroll(to: NSPoint(x: offset, y: clip.bounds.minY))
        }
        
        let x = self.row.convert(NSPoint(x: trackX, y: point.y), from: self).x
        let views = self.row.arrangedSubviews
        if let source = self.ids.firstIndex(of: id) {
            let index = views.firstIndex { $0.frame.maxX > x } ?? views.count - 1
            let frame = views[index].frame
            if index == source {
                self.row.insertionX = nil
            } else {
                self.row.insertionX = index < source ? frame.minX : frame.maxX
            }
            return index
        }
        
        let index = views.firstIndex { $0.frame.midX > x } ?? views.count
        self.row.insertionX = index < views.count ? views[index].frame.minX : views.last?.frame.maxX
        return index
    }
    
    private func dropTarget(at point: NSPoint, windowNumber: Int) -> (bar: TabBar, location: NSPoint)? {
        guard let window = NSApp.window(withWindowNumber: windowNumber),
            let bar = window.titlebarAccessoryViewControllers.compactMap({ $0.view as? TabBar }).first else {
            return nil
        }
        
        let location = bar.convert(window.convertPoint(fromScreen: point), from: nil)
        return bar.bounds.contains(location) ? (bar, location) : nil
    }
    
    private func detachedFrame(at point: NSPoint, windowNumber: Int, from window: NSWindow) -> NSRect? {
        guard let bounds = NSScreen.screens.first(where: { $0.visibleFrame.contains(point) })?.visibleFrame else {
            return nil
        }
        if window.frame.contains(point), windowNumber > 0 {
            guard windowNumber != window.windowNumber else {
                return nil
            }
            
            let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(windowNumber)) as? [[String: Any]]
            guard let level = info?.first?[kCGWindowLayer as String] as? Int, level <= CGWindowLevelForKey(.desktopIconWindow) else {
                return nil
            }
        }
        
        let width = min(WindowController.defaultSize.width, bounds.width)
        let height = min(WindowController.defaultSize.height, bounds.height)
        let x = max(bounds.minX, min(point.x - width / 2, bounds.maxX - width))
        let y = max(bounds.minY, min(point.y + 16, bounds.maxY) - height)
        return NSRect(x: x, y: y, width: width, height: height)
    }
    
    private func reorder(_ button: TabButton, from firstEvent: NSEvent, grabOffset: CGFloat) {
        guard let window, let source = self.row.arrangedSubviews.firstIndex(of: button),
            let bitmap = button.bitmapImageRepForCachingDisplay(in: button.bounds) else {
            return
        }
        
        let id = self.ids[source]
        self.updateHover(at: nil)
        button.cacheDisplay(in: button.bounds, to: bitmap)
        let preview = TabDragPreview(button: button, bitmap: bitmap)
        button.alphaValue = 0.35
        
        var target: TabBar?
        defer {
            preview.orderOut(nil)
            target?.row.insertionX = nil
            button.alphaValue = 1
            self.updateHover(at: window.mouseLocationOutsideOfEventStream)
        }
        
        var event: NSEvent? = firstEvent
        while let current = event {
            if current.type == .keyDown {
                if current.keyCode == 53 {
                    return
                }
            } else {
                let point = (current.window ?? window).convertPoint(toScreen: current.locationInWindow)
                var number = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0)
                if preview.isVisible, number == preview.windowNumber {
                    number = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: number)
                }
                
                let hit = self.dropTarget(at: point, windowNumber: number)
                if hit?.bar !== target {
                    target?.row.insertionX = nil
                    target = hit?.bar
                }
                
                let index = hit.map { $0.bar.insertionIndex(at: $0.location, for: id) }
                let frame = hit == nil ? self.detachedFrame(at: point, windowNumber: number, from: window) : nil
                if current.type == .leftMouseUp {
                    preview.orderOut(nil)
                    self.finishDrag(id, source: source, target: target, index: index, frame: frame)
                    return
                }
                
                preview.update(for: button, at: point, offset: grabOffset, detachedFrame: frame)
            }
            event = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp, .keyDown])
        }
    }
    
    private func finishDrag(_ id: UUID, source: Int, target: TabBar?, index: Int?, frame: NSRect?) {
        if let target, let index {
            if target !== self || index != source {
                target.move?(id, index)
            }
        } else if let frame {
            self.detach?(id, frame)
        }
    }
    
    func applyTheme() {
        self.addButton.contentTintColor = Theme.color(\.labelColor)
        for case let button as TabButton in self.row.arrangedSubviews {
            button.applyTheme()
        }
        self.row.needsDisplay = true
        self.needsDisplay = true
    }
    
    func show(_ session: WindowSession, title: (UUID) -> String) {
        if self.ids != session.tabs {
            self.ids = session.tabs
            self.needsDisplay = true
            for view in self.row.arrangedSubviews {
                view.removeFromSuperview()
            }
            
            for (index, id) in self.ids.enumerated() {
                let shortcut: String
                if index < 8 {
                    shortcut = "⌘\(index + 1)"
                } else {
                    shortcut = index == self.ids.count - 1 ? "⌘9" : ""
                }
                
                let button = TabButton(shortcut: shortcut, titleOnly: self.ids.count == 1)
                button.target = self
                button.action = #selector(self.clicked)
                button.tag = index
                button.reorder = { [weak self, weak button] event, offset in
                    guard let button else {
                        return
                    }
                    
                    self?.reorder(button, from: event, grabOffset: offset)
                }
                
                button.rename = { [weak self] name in self?.rename?(id, name) }
                button.closeTab = { [weak self] in self?.close?(id) }
                self.row.addArrangedSubview(button)
            }
        }
        
        self.layoutSubtreeIfNeeded()
        for (index, view) in self.row.arrangedSubviews.enumerated() {
            let button = view as! TabButton
            button.setName(title(self.ids[index]))
            button.isCurrent = self.ids[index] == session.selected
            if button.isCurrent {
                button.scrollToVisible(button.bounds)
            }
        }
        
        self.row.needsDisplay = true
        self.updateHover(at: self.window?.mouseLocationOutsideOfEventStream)
    }
    
    func updateTitle(_ title: String, for id: UUID) {
        guard let index = self.ids.firstIndex(of: id) else {
            return
        }
        (self.row.arrangedSubviews[index] as? TabButton)?.setName(title)
    }
    
    @objc private func clicked(_ sender: NSButton) {
        self.select?(self.ids[sender.tag])
    }
    
    @objc private func newTab() {
        self.add?()
    }
}
