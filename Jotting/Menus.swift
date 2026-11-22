//
//  Menus.swift
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
final class Menus: NSObject {
    private var statusItem: NSStatusItem?
    private var hideScratchpadItem: NSMenuItem!
    private var quitItem: NSMenuItem!
    private(set) var tabsMenu: NSMenu?
    
    private let moveMenu = NSMenu(title: "Move Tab to Window")
    
    func configure(menuBar: Bool, controller: Controller) {
        self.hideScratchpadItem.isHidden = !menuBar
        self.hideScratchpadItem.keyEquivalent = menuBar ? "q" : ""
        self.quitItem.keyEquivalent = menuBar ? "" : "q"
        
        if menuBar, self.statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: 18)
            let icon = NSImage(systemSymbolName: "doc.plaintext", accessibilityDescription: "Jotting")
            icon?.isTemplate = true
            item.button?.image = icon
            item.button?.setAccessibilityLabel("Jotting")
            item.button?.toolTip = "Jotting"
            item.button?.target = controller
            item.button?.action = #selector(controller.toggleNotes)
            item.button?.sendAction(on: .leftMouseDown)
            self.statusItem = item
        } else if !menuBar, let item = self.statusItem {
            NSStatusBar.system.removeStatusItem(item)
            self.statusItem = nil
        }
    }
    
    @objc private func showAbout() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let credits = NSAttributedString(
            string: "jotting.dev",
            attributes: [
                .link: "https://jotting.dev",
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .paragraphStyle: paragraph
            ])
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
    
    func install(for controller: Controller) {
        let bar = NSMenu()
        func menu(_ name: String) -> NSMenu {
            let item = bar.addItem(withTitle: name, action: nil, keyEquivalent: "")
            let menu = NSMenu(title: name)
            item.submenu = menu
            return menu
        }
        
        let app = menu("Jotting")
        self.item(app, "About Jotting", "", #selector(self.showAbout), target: self)
        self.item(app, "Check for Updates…", "", #selector(controller.checkUpdates), target: controller)
        app.addItem(.separator())
        self.item(app, "Settings…", ",", #selector(controller.preferences), target: controller)
        app.addItem(.separator())
        self.item(app, "Hide Jotting", "h", #selector(NSApplication.hide(_:)))
        app.addItem(.separator())
        self.quitItem = self.item(app, "Quit Jotting", "", #selector(NSApplication.terminate(_:)), target: NSApp)
        
        let file = menu("File")
        self.item(file, "New Window", "n", #selector(controller.newWindow), target: controller)
        self.item(file, "New Tab", "t", #selector(controller.addTab), target: controller)
        self.item(file, "Open…", "o", #selector(controller.openNote), target: controller)
        self.item(file, "Save", "s", #selector(controller.saveNote), target: controller)
        self.item(file, "Save As…", "S", #selector(controller.saveNoteAs), [.command, .shift], target: controller)
        self.item(file, "Close Tab", "w", #selector(controller.closeTab), target: controller)
        self.item(file, "Close Window", "W", #selector(NSWindow.performClose(_:)), [.command, .shift])
        
        self.configureEditMenu(menu("Edit"), controller: controller)
        menu("History").delegate = controller
        
        let tab = menu("Tabs")
        self.item(tab, "Next Tab", "\t", #selector(controller.cycle(_:)), .control, target: controller).tag = 1
        self.item(tab, "Previous Tab", "\t", #selector(controller.cycle(_:)), [.control, .shift], target: controller).tag = -1
        self.item(tab, "Move Tab Left", "", #selector(controller.reorder), target: controller).tag = -1
        self.item(tab, "Move Tab Right", "", #selector(controller.reorder), target: controller).tag = 1
        self.item(tab, "Move Tab to New Window", "", #selector(controller.detachTab), target: controller)
        let move = tab.addItem(withTitle: self.moveMenu.title, action: nil, keyEquivalent: "")
        move.submenu = self.moveMenu
        tab.addItem(.separator())
        tab.delegate = controller
        self.tabsMenu = tab
        
        let windows = menu("Window")
        self.item(windows, "Open Scratchpad", "", #selector(controller.focus), target: controller)
        self.hideScratchpadItem = self.item(windows, "Hide Scratchpad", "", #selector(NSApplication.hide(_:)), target: NSApp)
        self.item(windows, "Minimize", "m", #selector(NSWindow.performMiniaturize(_:)))
        NSApp.windowsMenu = windows
        NSApp.mainMenu = bar
    }
    
    @discardableResult
    private func item(
        _ menu: NSMenu, _ name: String, _ key: String, _ action: Selector,
        _ flags: NSEvent.ModifierFlags = .command, target: AnyObject? = nil
    ) -> NSMenuItem {
        let item = menu.addItem(withTitle: name, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = flags
        item.target = target
        return item
    }
    
    private func configureEditMenu(_ edit: NSMenu, controller: Controller) {
        self.item(edit, "Undo", "z", #selector(controller.undoOrReopen), target: controller)
        self.item(edit, "Redo", "Z", #selector(controller.redoOrClose), [.command, .shift], target: controller)
        edit.addItem(.separator())
        self.item(edit, "Cut", "x", #selector(NSText.cut(_:)))
        self.item(edit, "Copy", "c", #selector(NSText.copy(_:)))
        self.item(edit, "Paste", "v", #selector(NSText.paste(_:)))
        self.item(edit, "Paste and Match Style", "V", #selector(NSTextView.pasteAsPlainText(_:)), [.command, .option, .shift])
        self.item(edit, "Select All", "a", #selector(NSText.selectAll(_:)))
        edit.addItem(.separator())
        self.item(edit, "Find…", "f", #selector(NSTextView.performTextFinderAction(_:))).tag =
            NSTextFinder.Action.showFindInterface.rawValue
        self.item(edit, "Find Next", "g", #selector(NSTextView.performTextFinderAction(_:))).tag =
            NSTextFinder.Action.nextMatch.rawValue
        self.item(edit, "Find Previous", "G", #selector(NSTextView.performTextFinderAction(_:)), [.command, .shift]).tag =
            NSTextFinder.Action.previousMatch.rawValue
        self.item(edit, "Use Selection for Find", "e", #selector(NSTextView.performTextFinderAction(_:))).tag =
            NSTextFinder.Action.setSearchString.rawValue
    }
    
    func updateHistory(_ menu: NSMenu, session: SessionManager, controller: Controller) {
        menu.removeAllItems()
        for id in session.state.history {
            let item = menu.addItem(withTitle: session.title(for: id), action: #selector(controller.openHistory), keyEquivalent: "")
            item.target = controller
            item.representedObject = id
        }
        
        if !menu.items.isEmpty {
            menu.addItem(.separator())
        }
        
        let clear = menu.addItem(withTitle: "Clear History…", action: #selector(controller.clearHistory), keyEquivalent: "")
        clear.target = controller
    }
    
    func updateTabs(_ state: WindowSession, session: SessionManager, controller: Controller) {
        guard let menu = self.tabsMenu else {
            return
        }
        
        let destinations = self.moveMenu
        destinations.removeAllItems()
        for (index, group) in session.state.windows.enumerated() where group.id != state.id {
            let title = "Window \(index + 1) — " + session.title(for: group.selected)
            let item = destinations.addItem(withTitle: title, action: #selector(controller.moveTab), keyEquivalent: "")
            item.target = controller
            item.representedObject = group.id
        }
        
        for item in menu.items where item.action == #selector(controller.selectTab) {
            menu.removeItem(item)
        }
        
        for (index, id) in state.tabs.enumerated() {
            var key = ""
            if index < 8 {
                key = String(index + 1)
            } else if index == state.tabs.count - 1 {
                key = "9"
            }
            
            let item = menu.addItem(withTitle: session.title(for: id), action: #selector(controller.selectTab), keyEquivalent: key)
            item.target = controller
            item.representedObject = id
            item.state = id == state.selected ? .on : .off
        }
        
        if state.tabs.count < 9, let id = state.tabs.last {
            let item = menu.addItem(withTitle: "Last Tab", action: #selector(controller.selectTab), keyEquivalent: "9")
            item.target = controller
            item.representedObject = id
            item.isHidden = true
            item.allowsKeyEquivalentWhenHidden = true
        }
    }
}
