//
//  Controller.swift
//  Jotting
//
//  Created by Serhiy Mytrovtsiy on 20/11/2026.
//  Using Swift 6.0.
//  Running on macOS 27.2.
//
//  Copyright © 2026 Serhiy Mytrovtsiy. All rights reserved.
//

import AppKit
import ServiceManagement
import UniformTypeIdentifiers

@MainActor
final class Controller: NSObject, NSMenuDelegate, NSMenuItemValidation {
    let session: SessionManager
    
    private let config: ConfigurationStore
    private let menus = Menus()
    private let shortcut = ShortcutManager()
    private lazy var updater = UpdateController(session: self.session)
    private var windows: [UUID: WindowController] = [:]
    private var editors: [UUID: EditorView] = [:]
    private var active: UUID
    private lazy var noteTypes = SessionManager.noteExtensions.compactMap { UTType(filenameExtension: $0) }
    
    init(config: ConfigurationStore, session: SessionManager) {
        self.config = config
        self.session = session
        self.active = session.state.windows[0].id
        super.init()
    }
    
    private var current: WindowSession {
        self.session.state.windows.first { $0.id == self.active } ?? self.session.state.windows[0]
    }
    
    private var window: NSWindow? { self.windows[self.current.id]?.window }
    private var visible: EditorView? { self.windows[self.current.id]?.visible }
    
    func start() {
        self.menus.install(for: self)
        self.updater.onUpdate = { [weak self] in
            guard let self else {
                return
            }
            
            for controller in self.windows.values {
                controller.setUpdate(self.updater.availableVersion, installing: self.updater.installing)
            }
        }
        self.updater.check(silently: true)
        
        self.session.onError = { NSApp.presentError($0) }
        
        self.shortcut.activate = { [weak self] in
            if NSApp.isActive, let window = self?.window, window.isKeyWindow {
                window.performClose(nil)
            } else {
                self?.focus()
            }
        }
        
        var warnings = [self.config.warning].compactMap { $0 }
        if self.config.warning == nil {
            do {
                try self.applyLaunchAtLogin(self.config.value.launchAtLogin)
            } catch {
                warnings.append(error.localizedDescription)
            }
        }
        
        do {
            try self.shortcut.set(self.config.value.globalShortcut)
        } catch {
            warnings.append(error.localizedDescription)
        }
        
        do {
            let defaults = Configuration()
            if self.session.isFirstLaunch,
                self.config.value.theme != defaults.theme || self.config.value.appearance != defaults.appearance {
                try self.config.save(["theme": defaults.theme, "appearance": defaults.appearance.rawValue], section: "interface")
            }
            Theme.current = try Theme.load(self.config.value.theme, directory: self.config.themes)
        } catch {
            warnings.append(error.localizedDescription)
        }
        self.applyAppearanceAndAccess(self.config.value)
        
        for state in self.session.state.windows.reversed() {
            self.present(state.id)
        }
        
        self.showWelcomeIfNeeded()
        
        for warning in warnings {
            NSApp.presentError(StorageError(warning))
        }
    }
    
    private func showWelcomeIfNeeded() {
        guard self.session.isFirstLaunch || CommandLine.arguments.dropFirst().contains("--simulate-welcome"),
            let editor = self.visible else {
            return
        }
        
        editor.welcome = WelcomeView(configuration: self.config) { [weak self] key, value in
            guard let self else {
                return
            }
            do {
                let palette = key == .theme ? try Theme.load(value, directory: self.config.themes) : nil
                try self.config.save([key.rawValue: value], section: "interface")
                if let palette {
                    Theme.current = palette
                }
                self.applyAppearanceAndAccess(self.config.value)
            } catch {
                NSApp.presentError(error)
            }
        } applyApplication: { [weak self] key, value in
            guard let self else {
                return
            }
            do {
                try self.config.save([key.rawValue: value], section: "application")
                self.applyAppearanceAndAccess(self.config.value)
                if key == .launchAtLogin {
                    try self.applyLaunchAtLogin(value)
                }
            } catch {
                NSApp.presentError(error)
            }
        } finish: { [weak self, weak editor] in
            editor?.welcome = nil
            self?.refresh()
        }
        self.refresh()
    }
    
    private func applyAppearanceAndAccess(_ value: Configuration) {
        let policy: NSApplication.ActivationPolicy = value.dockIcon ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }
        
        self.menus.configure(menuBar: value.menuBar, controller: self)
        
        switch value.appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        
        for controller in self.windows.values {
            controller.apply(value)
        }
        for editor in self.editors.values {
            editor.apply(value)
        }
    }
    
    private func applyLaunchAtLogin(_ enabled: Bool) throws {
        let defaults = UserDefaults.standard
        let key = "appliedLaunchAtLogin"
        guard defaults.object(forKey: key) as? Bool != enabled else {
            return
        }
        
        let service = SMAppService.mainApp
        switch (enabled, service.status) {
        case (true, .notRegistered), (true, .notFound):
            try service.register()
        case (false, .enabled), (false, .requiresApproval):
            try service.unregister()
        default:
            break
        }
        
        defaults.set(enabled, forKey: key)
        if enabled, service.status == .requiresApproval {
            throw StorageError("Allow Jotting in System Settings → General → Login Items to launch it at login.")
        }
    }
    
    private func saveSettings(_ textView: NSTextView) throws {
        let (value, text) = try self.config.configuration(from: textView.string)
        let theme = try Theme.load(value.theme, directory: self.config.themes)
        let previous = self.shortcut.current
        try self.shortcut.set(value.globalShortcut)
        do {
            try self.config.save(value, text: text)
        } catch {
            try? self.shortcut.set(previous)
            self.applyAppearanceAndAccess(self.config.value)
            throw error
        }
        
        Theme.current = theme
        self.applyAppearanceAndAccess(value)
        if textView.string != text {
            let selection = textView.selectedRange()
            let origin = textView.visibleRect.origin
            textView.insertText(text, replacementRange: NSRange(location: 0, length: textView.string.utf16.count))
            let start = min(selection.location, text.utf16.count)
            textView.setSelectedRange(NSRange(location: start, length: min(selection.length, text.utf16.count - start)))
            textView.scroll(origin)
        }
        try self.applyLaunchAtLogin(value.launchAtLogin)
    }
    
    @objc func toggleNotes() {
        if NSApp.isActive, self.window?.isKeyWindow == true {
            NSApp.hide(nil)
        } else {
            self.focus()
        }
    }
    
    @objc func focus() {
        self.present(self.current.id)
    }
    
    private func present(_ id: UUID, frame: NSRect? = nil) {
        guard self.session.state.windows.contains(where: { $0.id == id }) else {
            return
        }
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        if self.windows[id] == nil {
            let controller = WindowController(config: self.config, updateTarget: self, updateAction: #selector(self.showUpdate))
            controller.setUpdate(self.updater.availableVersion, installing: self.updater.installing)
            let frameName = "Scratchpad-" + id.uuidString
            if let frame {
                controller.window.setFrame(frame, display: false)
            } else if !controller.window.setFrameUsingName(frameName) {
                if let previous = self.window {
                    controller.window.cascadeTopLeft(from: NSPoint(x: previous.frame.minX, y: previous.frame.maxY))
                } else {
                    controller.window.setFrameUsingName("Scratchpad")
                }
            }
            controller.window.setFrameAutosaveName(frameName)
            self.windows[id] = controller
            self.configureTabs(controller.tabs, in: id)
            controller.onCycle = { [weak self] offset in self?.cycle(by: offset, in: id) }
            controller.onToggleWriterMode = { [weak self] in self?.toggleWriterMode(in: id) }
            controller.onFocus = { [weak self] in
                self?.active = id
                self?.refreshTabsMenu()
            }
            controller.shouldClose = { [weak self] in
                do {
                    try self?.session.closeWindow(id)
                    return true
                } catch {
                    NSApp.presentError(error)
                    return false
                }
            }
            controller.onClose = { [weak self] in
                guard let self else {
                    return
                }
                self.windows.removeValue(forKey: id)
                self.removeClosedEditors()
            }
        }
        self.active = id
        self.refresh()
        self.windows[id]?.focus()
    }
    
    private func toggleWriterMode(in window: UUID) {
        guard let group = self.session.state.windows.first(where: { $0.id == window }),
            self.session.state.files?[group.selected.uuidString] != self.config.file,
            let editor = self.editors[group.selected], editor.welcome == nil else {
            return
        }
        self.change { try self.session.toggleWriterMode(for: group.selected) }
    }
    
    private func configureTabs(_ tabs: TabBar, in id: UUID) {
        tabs.add = { [weak self] in
            self?.change { try self?.session.add(in: id) }
        }
        tabs.select = { [weak self] note in
            self?.change { try self?.session.select(note, in: id) }
        }
        tabs.close = { [weak self] note in
            self?.change { try self?.session.close(note) }
        }
        tabs.move = { [weak self] note, index in
            guard let self else {
                return
            }
            if self.session.state.windows.first(where: { $0.id == id })?.tabs.contains(note) == true {
                self.change { try self.session.move(note, to: index) }
            } else {
                self.transfer(note, to: id, index: index)
            }
        }
        tabs.detach = { [weak self] note, frame in
            self?.transfer(note, to: UUID(), frame: frame)
        }
        tabs.rename = { [weak self] note, name in self?.renameTab(note, to: name) }
    }
    
    private func refreshTabsMenu() {
        self.menus.updateTabs(self.current, session: self.session, controller: self)
    }
    
    private func change(_ operation: () throws -> Void) {
        do {
            try operation()
            self.refresh()
        } catch {
            NSApp.presentError(error)
        }
    }
    
    private func removeClosedEditors() {
        let tabs = Set(self.session.state.tabs)
        self.editors = self.editors.filter { tabs.contains($0.key) }
    }
    
    private func refresh() {
        let state = self.session.state
        for (id, controller) in self.windows {
            guard let group = state.windows.first(where: { $0.id == id }) else {
                controller.window.close()
                continue
            }
            if controller.visible !== self.editors[group.selected] {
                controller.detachEditor()
            }
        }
        self.removeClosedEditors()
        for group in state.windows {
            guard let controller = self.windows[group.id] else {
                continue
            }
            
            let id = group.selected
            let settings = state.files?[id.uuidString] == self.config.file
            do {
                let editor: EditorView
                if let cached = self.editors[id] {
                    editor = cached
                } else {
                    editor = EditorView(text: try self.session.buffers.read(id), configuration: self.config.value, isSettings: settings)
                    editor.didEdit = { [weak self, weak editor] in
                        guard let self, let editor else {
                            return
                        }
                        self.session.changed(id) { editor.textView.string }
                        self.updateTitle(id)
                    }
                    self.editors[id] = editor
                }
                
                let writerMode = state.writerTabs.contains(id) && !settings && editor.welcome == nil
                if editor.writerMode != writerMode {
                    editor.writerMode = writerMode
                    editor.apply(self.config.value)
                }
                controller.show(group, editor: editor, settings: settings, title: self.session.title(for:))
            } catch {
                NSApp.presentError(error)
            }
        }
        self.refreshTabsMenu()
    }
    
    private func updateTitle(_ id: UUID) {
        guard let group = self.session.state.windows.first(where: { $0.tabs.contains(id) }) else {
            return
        }
        
        let title = self.session.title(for: id)
        self.windows[group.id]?.tabs.updateTitle(title, for: id)
        if group.selected == id {
            self.windows[group.id]?.window.title = title
        }
    }
    
    @objc func checkUpdates() {
        self.updater.check()
    }
    
    @objc private func showUpdate() {
        self.updater.showUpdate()
    }
    
    @objc func newWindow() {
        do {
            self.present(try self.session.newWindow())
        } catch {
            NSApp.presentError(error)
        }
    }
    
    @objc func detachTab() {
        self.transfer(self.current.selected, to: UUID())
    }
    
    @objc func moveTab(_ item: NSMenuItem) {
        if let id = item.representedObject as? UUID {
            self.transfer(self.current.selected, to: id)
        }
    }
    
    private func transfer(_ note: UUID, to id: UUID, index: Int? = nil, frame: NSRect? = nil) {
        do {
            let editor = self.editors[note]
            let selection = editor?.textView.selectedRanges
            let origin = editor?.contentView.bounds.origin
            try self.session.transfer(note, to: id, at: index)
            self.present(id, frame: frame)
            if let editor, let selection, let origin {
                editor.textView.selectedRanges = selection
                editor.contentView.scroll(to: origin)
                editor.reflectScrolledClipView(editor.contentView)
            }
        } catch {
            NSApp.presentError(error)
        }
    }
    
    @objc func addTab() {
        self.focus()
        self.change { try self.session.add(in: self.current.id) }
    }
    
    @objc func openNote() {
        self.focus()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = self.noteTypes
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        
        self.openFile(url)
    }
    
    func openFile(_ url: URL) {
        let owner = self.session.state.windows.first { group in
            group.tabs.contains { self.session.state.files?[$0.uuidString] == url }
        }
        self.present(owner?.id ?? self.current.id)
        self.change { try self.session.add(from: url, in: self.current.id) }
    }
    
    @objc func saveNote() {
        guard self.window?.isKeyWindow == true, let editor = self.visible else {
            return
        }
        
        let id = self.current.selected
        do {
            if self.session.state.files?[id.uuidString] == self.config.file {
                try self.saveSettings(editor.textView)
            }
            
            try self.session.flush()
        } catch {
            NSApp.presentError(error)
        }
    }
    
    @objc func saveNoteAs() {
        guard self.window?.isKeyWindow == true, let editor = self.visible else {
            return
        }
        
        let id = self.current.selected
        let panel = NSSavePanel()
        panel.allowedContentTypes = self.noteTypes
        if let file = self.session.state.files?[id.uuidString], file != self.config.file {
            panel.directoryURL = file.deletingLastPathComponent()
            panel.nameFieldStringValue = file.lastPathComponent
        } else {
            panel.nameFieldStringValue = "Untitled.txt"
        }
        
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        
        do {
            try self.session.save(editor.textView.string, for: id, to: url)
            self.updateTitle(id)
        } catch {
            NSApp.presentError(error)
        }
    }
    
    @objc func closeTab() {
        if self.window?.isKeyWindow == true {
            self.change { try self.session.close(self.current.selected) }
        }
    }
    
    private func renameTab(_ id: UUID, to name: String) {
        do {
            try self.session.rename(id, to: name)
        } catch {
            NSApp.presentError(error)
        }
        
        self.updateTitle(id)
    }
    
    private func historyNote(forRedo redo: Bool) -> UUID? {
        guard let window = self.window, window.isKeyWindow, window.attachedSheet == nil else {
            return nil
        }
        if let editor = window.firstResponder as? NSTextView {
            let canEdit = redo ? editor.undoManager?.canRedo : editor.undoManager?.canUndo
            guard editor === self.visible?.textView, canEdit != true, !editor.hasMarkedText() else {
                return nil
            }
        }
        
        if redo {
            return self.session.lastReopened == self.current.selected ? self.session.lastReopened : nil
        }
        return self.session.lastClosed
    }
    
    @objc func undoOrReopen(_ item: NSMenuItem) {
        if self.historyNote(forRedo: false) != nil {
            self.change { try self.session.reopenLastClosed(in: self.current.id) }
        } else {
            NSApp.sendAction(Selector(("undo:")), to: nil, from: item)
        }
    }
    
    @objc func redoOrClose(_ item: NSMenuItem) {
        if let id = self.historyNote(forRedo: true) {
            self.change { try self.session.close(id) }
        } else {
            NSApp.sendAction(Selector(("redo:")), to: nil, from: item)
        }
    }
    
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(self.detachTab) {
            return self.window?.isKeyWindow == true && self.current.tabs.count > 1
        }
        if menuItem.action == #selector(self.clearHistory) {
            return !self.session.state.history.isEmpty
        }
        
        let redo = menuItem.action == #selector(self.redoOrClose)
        guard redo || menuItem.action == #selector(self.undoOrReopen) else {
            return true
        }
        if self.historyNote(forRedo: redo) != nil {
            menuItem.title = redo ? "Close Reopened Note" : "Reopen Closed Note"
            return true
        }
        
        let action = redo ? Selector(("redo:")) : Selector(("undo:"))
        let item = NSMenuItem(title: redo ? "Redo" : "Undo", action: action, keyEquivalent: menuItem.keyEquivalent)
        item.keyEquivalentModifierMask = menuItem.keyEquivalentModifierMask
        let target = NSApp.target(forAction: action, to: nil, from: item)
        let enabled = (target as? NSMenuItemValidation)?.validateMenuItem(item)
            ?? (target as? NSUserInterfaceValidations)?.validateUserInterfaceItem(item)
            ?? (target != nil)
        menuItem.title = item.title
        return enabled
    }
    
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === self.menus.tabsMenu {
            self.refreshTabsMenu()
            return
        }
        
        self.menus.updateHistory(menu, session: self.session, controller: self)
    }
    
    @objc func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear note history?"
        alert.informativeText = "Closed notes will be removed from Jotting. Open tabs and files saved elsewhere will be kept."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Clear History").hasDestructiveAction = true
        if alert.runModal() == .alertSecondButtonReturn {
            do {
                try self.session.clearHistory()
            } catch {
                NSApp.presentError(error)
            }
        }
    }
    
    @objc func openHistory(_ item: NSMenuItem) {
        guard let id = item.representedObject as? UUID else {
            return
        }
        
        let window = self.session.state.windows.first { $0.tabs.contains(id) }?.id ?? self.current.id
        self.present(window)
        self.change { try self.session.select(id, in: window) }
    }
    
    @objc func selectTab(_ item: NSMenuItem) {
        guard let id = item.representedObject as? UUID, self.current.tabs.contains(id) else {
            return
        }
        self.change { try self.session.select(id, in: self.current.id) }
    }
    
    @objc func cycle(_ item: NSMenuItem) {
        self.cycle(by: item.tag, in: self.current.id)
    }
    
    private func cycle(by offset: Int, in window: UUID) {
        guard let state = self.session.state.windows.first(where: { $0.id == window }) else {
            return
        }
        
        let index = state.tabs.firstIndex(of: state.selected)!
        self.change { try self.session.select(state.tabs[(index + offset + state.tabs.count) % state.tabs.count], in: state.id) }
    }
    
    @objc func reorder(_ item: NSMenuItem) {
        let state = self.current
        self.change { try self.session.move(state.selected, to: state.tabs.firstIndex(of: state.selected)! + item.tag) }
    }
    
    @objc func preferences() {
        self.focus()
        if let owner = self.session.state.windows.first(where: { group in
            group.tabs.contains { self.session.state.files?[$0.uuidString] == self.config.file }
        }) {
            self.present(owner.id)
        }
        self.change { try self.session.openSettings(in: self.current.id) }
    }
    
    func flush() {
        do {
            try self.session.flush()
        } catch {
            NSApp.presentError(error)
        }
    }
}
