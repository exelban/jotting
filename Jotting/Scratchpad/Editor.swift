//
//  Editor.swift
//  Jotting
//
//  Created by Serhiy Mytrovtsiy on 19/11/2026.
//  Using Swift 6.0.
//  Running on macOS 27.2.
//
//  Copyright © 2026 Serhiy Mytrovtsiy. All rights reserved.
//

import AppKit

private extension FontSettings.Weight {
    var fontWeight: NSFont.Weight {
        switch self {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        }
    }
}

private extension FontSettings {
    var editorFont: NSFont {
        let size = CGFloat(self.size)
        let weight = self.weight.fontWeight
        if self.family == "system" {
            return .systemFont(ofSize: size, weight: weight)
        }
        
        if self.family != "monospaced" {
            let descriptor = NSFontDescriptor(fontAttributes: [
                .family: self.family, .traits: [NSFontDescriptor.TraitKey.weight: weight]
            ])
            if let font = NSFont(descriptor: descriptor, size: size) {
                return font
            }
        }
        return .monospacedSystemFont(ofSize: size, weight: weight)
    }
}

private final class BufferLayoutManager: NSLayoutManager {
    override func fillBackgroundRectArray(_ rects: UnsafePointer<NSRect>, count: Int, forCharacterRange range: NSRange, color: NSColor) {
        guard let view = self.firstTextView, let container = view.textContainer,
            let selectionColor = view.selectedTextAttributes[.backgroundColor] as? NSColor,
            color == selectionColor || color == .unemphasizedSelectedContentBackgroundColor
                || color == .unemphasizedSelectedTextBackgroundColor
        else {
            super.fillBackgroundRectArray(rects, count: count, forCharacterRange: range, color: color)
            return
        }
        
        let origin = view.textContainerOrigin
        let viewport = view.visibleRect
        var highlights: [NSRect] = []
        for rect in UnsafeBufferPointer(start: rects, count: count) {
            let visible = viewport.intersection(rect)
            guard !visible.isEmpty else {
                continue
            }
            
            let rows = NSRect(x: 0, y: visible.minY - origin.y, width: container.size.width, height: visible.height)
            let glyphs = self.glyphRange(forBoundingRect: rows, in: container)
            guard glyphs.length > 0 else {
                continue
            }
            
            self.enumerateLineFragments(forGlyphRange: glyphs) { _, used, _, _, _ in
                let text = used.insetBy(dx: container.lineFragmentPadding, dy: 0)
                let highlight = visible.intersection(text.offsetBy(dx: origin.x, dy: origin.y))
                if !text.isEmpty && !highlight.isEmpty {
                    highlights.append(highlight)
                }
            }
        }
        
        if !highlights.isEmpty {
            super.fillBackgroundRectArray(highlights, count: highlights.count, forCharacterRange: range, color: selectionColor)
        }
    }
}

final class BufferTextView: NSTextView {
    private let history = UndoManager()
    var lineMarker = LineMarker.none
    private var lineStarts: [Int] = []
    private var selectionHead = 0 {
        didSet {
            if self.lineMarker != .none && self.selectionHead != oldValue {
                var gutter = self.visibleRect
                gutter.size.width = self.textContainerOrigin.x
                self.setNeedsDisplay(gutter)
            }
        }
    }
    private var dotSize: CGFloat { min(4, max(2, (self.font?.pointSize ?? 13) / 5)) }
    
    override var undoManager: UndoManager? { self.history }
    
    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let input = (insertString as? NSAttributedString)?.string ?? insertString as? String
        let range = replacementRange.location == NSNotFound ? self.selectedRange() : replacementRange
        if !self.hasMarkedText(), input?.first?.isWhitespace == false, range.length == 0, range.location > 0,
            let text = self.textStorage?.mutableString, range.location <= text.length {
            let previous = NSRange(location: range.location - 1, length: 1)
            if text.rangeOfCharacter(from: .whitespacesAndNewlines, options: [], range: previous).location != NSNotFound {
                self.breakUndoCoalescing()
            }
        }
        
        super.insertText(insertString, replacementRange: replacementRange)
    }
    
    private var caretLine: NSRange? {
        guard let text = self.textStorage?.mutableString, self.selectionHead <= text.length else {
            return nil
        }
        return text.lineRange(for: NSRange(location: self.selectionHead, length: 0))
    }
    
    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        let previous = self.selectedRange()
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        let selection = self.selectedRange()
        if selection != previous {
            let end = NSMaxRange(selection)
            self.selectionHead = end == NSMaxRange(previous) || end == previous.location ? selection.location : end
        }
    }
    
    func updateMarkers() {
        if self.lineMarker != .number {
            self.lineStarts.removeAll()
        }
        
        var inset: CGFloat = 13
        if let text = self.textStorage?.mutableString, let font {
            switch self.lineMarker {
            case .none:
                break
            case .number:
                if self.lineStarts.isEmpty {
                    self.lineStarts = [0]
                    self.indexLines(in: text, range: NSRange(location: 0, length: text.length), changeInLength: text.length)
                }
                inset = 2 * 18 + ceil((String(self.lineStarts.count) as NSString).size(withAttributes: [.font: font]).width)
            case .dot:
                inset = 2 * 9 + self.dotSize
            }
        }
        
        if self.textContainerInset.width != inset {
            self.textContainerInset.width = inset
        }
    }
    
    private func firstLine(after offset: Int) -> Int {
        var lower = 0
        var upper = self.lineStarts.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if self.lineStarts[middle] <= offset {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }
    
    func indexLines(in text: NSString, range: NSRange, changeInLength delta: Int) {
        let first = self.firstLine(after: max(0, range.location - 1))
        let suffix = self.firstLine(after: NSMaxRange(range) - delta)
        let end = suffix < self.lineStarts.count ? self.lineStarts[suffix] + delta : text.length
        var start = self.lineStarts[first - 1]
        var starts: [Int] = []
        while start < end {
            var contentsEnd = 0
            text.getLineStart(nil, end: &start, contentsEnd: &contentsEnd, for: NSRange(location: start, length: 0))
            guard contentsEnd < start else {
                break
            }
            if start < end || suffix == self.lineStarts.count {
                starts.append(start)
            }
        }
        
        if delta != 0 {
            for index in suffix..<self.lineStarts.count {
                self.lineStarts[index] += delta
            }
        }
        self.lineStarts.replaceSubrange(first..<suffix, with: starts)
    }
    
    func isInMarkerGutter(_ point: NSPoint) -> Bool {
        self.lineMarker != .none && point.x < self.textContainerOrigin.x
    }
    
    private func lineRange(at y: CGFloat) -> NSRange? {
        guard let layout = self.layoutManager, let container = self.textContainer, let text = self.textStorage?.mutableString else {
            return nil
        }
        
        let row = NSRect(x: 0, y: y - self.textContainerOrigin.y, width: container.size.width, height: 1)
        let glyphs = layout.glyphRange(forBoundingRect: row, in: container)
        let index: Int
        if layout.extraLineFragmentTextContainer === container, NSMouseInRect(row.origin, layout.extraLineFragmentRect, true) {
            index = text.length
        } else if glyphs.length > 0 {
            index = layout.characterIndexForGlyph(at: glyphs.location)
        } else {
            return nil
        }
        return text.lineRange(for: NSRange(location: index, length: 0))
    }
    
    @discardableResult
    private func scrollDuringSelection(by distance: CGFloat) -> Bool {
        guard distance != 0, let scroll = self.enclosingScrollView else {
            return false
        }
        
        let clip = scroll.contentView
        let origin = clip.constrainBoundsRect(clip.bounds.offsetBy(dx: 0, dy: distance)).origin
        guard origin != clip.bounds.origin else {
            return false
        }
        
        clip.scroll(to: origin)
        scroll.reflectScrolledClipView(clip)
        return true
    }
    
    private func scrollDuringDrag(_ drag: NSEvent) -> Bool {
        let y = self.convert(drag.locationInWindow, from: nil).y
        let visible = self.visibleRect
        let inset = min(16, visible.height / 2)
        let distance = min(0, y - visible.minY - inset) + max(0, y - visible.maxY + inset)
        return self.scrollDuringSelection(by: distance)
    }
    
    override func mouseDown(with event: NSEvent) {
        let point = self.convert(event.locationInWindow, from: nil)
        let selection = self.selectedRange()
        guard self.isInMarkerGutter(point), let anchor = self.lineRange(at: point.y) else {
            if selection.length > 0 && event.clickCount == 1
                && event.modifierFlags.isDisjoint(with: [.shift, .command, .option, .control]) {
                self.setSelectedRange(NSRange(location: self.characterIndexForInsertion(at: point), length: 0))
            }
            super.mouseDown(with: event)
            return
        }
        
        self.window?.makeFirstResponder(self)
        var selecting = NSIntersectionRange(selection, anchor).length == 0
        self.setSelectedRange(selecting ? anchor : NSRange(location: anchor.location, length: 0))
        self.selectionHead = anchor.location
        guard let window else {
            return
        }
        
        var drag = event
        var deadline = Date.distantFuture
        while true {
            let next = window.nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp, .scrollWheel], until: deadline, inMode: .eventTracking, dequeue: true)
            var scrolling = false
            if let next, next.type == .scrollWheel {
                let unit = next.hasPreciseScrollingDeltas ? 1 : self.enclosingScrollView?.verticalLineScroll ?? 1
                self.scrollDuringSelection(by: -next.scrollingDeltaY * unit)
            } else {
                drag = next ?? drag
                if drag.type == .leftMouseDragged {
                    scrolling = self.scrollDuringDrag(drag)
                }
            }
            
            let visible = self.visibleRect
            let y = min(max(self.convert(drag.locationInWindow, from: nil).y, visible.minY), visible.maxY - 1)
            let edge = y < self.textContainerOrigin.y ? 0 : self.textStorage?.length ?? 0
            let line = self.lineRange(at: y) ?? NSRange(location: edge, length: 0)
            if line != anchor {
                selecting = true
            }
            if selecting {
                self.setSelectedRange(NSUnionRange(anchor, line))
                self.selectionHead = line.location
            }
            if drag.type == .leftMouseUp {
                return
            }
            
            deadline = scrolling ? Date(timeIntervalSinceNow: 0.05) : .distantFuture
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        super.draw(dirtyRect)
        NSGraphicsContext.restoreGraphicsState()
        guard self.lineMarker != .none, let font, let layout = self.layoutManager, let container = self.textContainer,
            let text = self.textStorage?.mutableString
        else {
            return
        }
        
        let origin = self.textContainerOrigin
        let visible = NSRect(x: 0, y: dirtyRect.minY - origin.y, width: container.size.width, height: dirtyRect.height)
        let glyphs = layout.glyphRange(forBoundingRect: visible, in: container)
        let activeLine = self.caretLine?.location
        func drawMarker(at index: Int, in fragment: NSRect) {
            let gutter = NSRect(x: 0, y: origin.y + fragment.minY, width: origin.x, height: fragment.height)
            let isActive = index == activeLine
            if isActive {
                Theme.color(\.labelColor).withAlphaComponent(0.12).setFill()
                gutter.fill()
            }
            
            switch self.lineMarker {
            case .none:
                return
            case .number:
                let number = self.firstLine(after: index)
                guard number > 0, self.lineStarts[number - 1] == index else {
                    return
                }
                
                let label = String(number) as NSString
                let color: NSColor = isActive ? Theme.color(\.labelColor) : Theme.color(\.secondaryText)
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                let size = label.size(withAttributes: attributes)
                label.draw(
                    at: NSPoint(x: gutter.midX - size.width / 2, y: gutter.midY - size.height / 2),
                    withAttributes: attributes)
            case .dot:
                guard text.lineRange(for: NSRange(location: index, length: 0)).location == index else {
                    return
                }
                
                let dot = NSRect(
                    x: gutter.midX - self.dotSize / 2, y: gutter.midY - self.dotSize / 2, width: self.dotSize, height: self.dotSize)
                (isActive ? Theme.color(\.secondaryText) : Theme.color(\.secondaryText).withAlphaComponent(0.3)).setFill()
                NSBezierPath(ovalIn: dot).fill()
            }
        }
        
        layout.enumerateLineFragments(forGlyphRange: glyphs) { fragment, _, _, range, _ in
            drawMarker(at: layout.characterIndexForGlyph(at: range.location), in: fragment)
        }
        
        if layout.extraLineFragmentTextContainer === container, visible.intersects(layout.extraLineFragmentRect) {
            drawMarker(at: text.length, in: layout.extraLineFragmentRect)
        }
    }
}

final class EditorView: NSScrollView, NSTextViewDelegate, NSTextStorageDelegate {
    static let writerBackground = NSColor(srgbRed: 0.975, green: 0.972, blue: 0.965, alpha: 1)
    private static let writerCaret = NSColor(srgbRed: 0, green: 0.76, blue: 0.94, alpha: 1)
    var writerMode = false
    let textView = BufferTextView()
    var welcome: WelcomeView? {
        didSet {
            self.textView.isSelectable = self.welcome == nil
            self.textView.isEditable = self.welcome == nil
            self.textView.setAccessibilityElement(self.welcome == nil)
        }
    }
    
    var didEdit: (() -> Void)?
    var onScrollerWidth: ((CGFloat) -> Void)?
    
    var scrollerWidth: CGFloat {
        let clip = self.contentView
        guard clip.documentRect.height > clip.bounds.height, let scroller = self.verticalScroller else {
            return 0
        }
        
        return NSScroller.scrollerWidth(for: scroller.controlSize, scrollerStyle: self.scrollerStyle)
    }
    
    init(text: String, configuration: Configuration, isSettings: Bool) {
        super.init(frame: .zero)
        self.borderType = .noBorder
        self.hasVerticalScroller = true
        self.verticalScrollElasticity = .none
        self.contentView.automaticallyAdjustsContentInsets = false
        self.autohidesScrollers = true
        self.drawsBackground = false
        
        self.textView.textContainer?.replaceLayoutManager(BufferLayoutManager())
        self.textView.isRichText = false
        self.textView.importsGraphics = false
        self.textView.allowsUndo = true
        self.textView.usesFindBar = true
        self.textView.isIncrementalSearchingEnabled = true
        
        self.textView.isAutomaticSpellingCorrectionEnabled = false
        self.textView.isContinuousSpellCheckingEnabled = false
        self.textView.isGrammarCheckingEnabled = false
        self.textView.isAutomaticQuoteSubstitutionEnabled = false
        self.textView.isAutomaticDashSubstitutionEnabled = false
        self.textView.isAutomaticTextReplacementEnabled = false
        self.textView.isAutomaticLinkDetectionEnabled = false
        self.textView.isAutomaticDataDetectionEnabled = false
        self.textView.isAutomaticTextCompletionEnabled = false
        self.textView.inlinePredictionType = .no
        self.textView.smartInsertDeleteEnabled = false
        
        self.textView.isHorizontallyResizable = false
        self.textView.isVerticallyResizable = true
        self.textView.autoresizingMask = [.width]
        self.textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        self.textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        self.textView.textContainer?.widthTracksTextView = true
        self.textView.textContainerInset = NSSize(width: 13, height: 14)
        
        self.textView.string = text
        self.textView.delegate = self
        self.textView.textStorage?.delegate = self
        self.textView.setAccessibilityLabel(isSettings ? ConfigurationStore.title : "Scratch buffer")
        
        self.documentView = self.textView
        self.apply(configuration)
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }
    
    func apply(_ configuration: Configuration) {
        self.textView.appearance = self.writerMode ? NSAppearance(named: .aqua) : nil
        self.textView.backgroundColor = self.writerMode ? Self.writerBackground : Theme.color(\.background)
        self.textView.drawsBackground = self.writerMode || configuration.interfaceStyle == .classic
        self.textView.textColor = self.writerMode ? NSColor(white: 0.1, alpha: 1) : Theme.color(\.text)
        self.textView.insertionPointColor = self.writerMode ? Self.writerCaret : Theme.color(\.caretColor)
        let selection = self.writerMode ? NSColor.selectedTextBackgroundColor : Theme.color(\.selection)
        self.textView.selectedTextAttributes[.backgroundColor] = selection
        self.textView.font = self.writerMode ? .monospacedSystemFont(ofSize: 24, weight: .regular) : configuration.font.editorFont
        let lineHeight = self.writerMode ? 1.5 : CGFloat(configuration.font.lineHeight)
        if self.textView.defaultParagraphStyle?.lineHeightMultiple != lineHeight {
            let style = NSMutableParagraphStyle()
            style.lineHeightMultiple = lineHeight
            self.textView.defaultParagraphStyle = style
            if let storage = self.textView.textStorage {
                storage.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: storage.length))
            }
            
            self.textView.typingAttributes[.paragraphStyle] = style
        }
        
        self.welcome?.refresh()
        self.textView.lineMarker = self.writerMode ? .none : configuration.lineMarker
        self.textView.updateMarkers()
        self.textView.textContainerInset.height = self.writerMode ? 48 : 14
        self.tile()
        self.textView.needsDisplay = true
    }
    
    override func tile() {
        super.tile()
        guard let textView = self.documentView as? NSTextView else {
            return
        }
        
        if self.writerMode, let font = textView.font, let container = textView.textContainer {
            let width = ("0" as NSString).size(withAttributes: [.font: font]).width * 65
            let inset = max(13, floor((self.contentView.bounds.width - width) / 2) - container.lineFragmentPadding)
            if textView.textContainerInset.width != inset {
                textView.textContainerInset.width = inset
            }
        }
        
        let height = self.contentView.bounds.height
        if textView.minSize.height != height {
            textView.minSize = NSSize(width: 0, height: height)
        }
        
        if textView.frame.height < height {
            textView.setFrameSize(NSSize(width: self.contentView.bounds.width, height: height))
        }
    }
    
    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        self.onScrollerWidth?(self.scrollerWidth)
    }
    
    func textDidChange(_ notification: Notification) {
        if self.textView.lineMarker == .number {
            self.textView.updateMarkers()
        }
        self.textView.setNeedsDisplay(self.textView.visibleRect)
        
        self.didEdit?()
    }
    
    func textStorage(
        _ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        if self.textView.lineMarker == .number, editedMask.contains(.editedCharacters) {
            self.textView.indexLines(in: textStorage.mutableString, range: editedRange, changeInLength: delta)
        }
    }
}
