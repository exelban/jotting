//
//  AppDelegate.swift
//  Jotting
//
//  Created by Serhiy Mytrovtsiy on 19/11/2026.
//  Using Swift 6.0.
//  Running on macOS 27.2.
//
//  Copyright © 2026 Serhiy Mytrovtsiy. All rights reserved.
//

import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: Controller?
    private var pendingURLs: [URL] = []
    
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let directory = try applicationSupportDirectory()
            let config = try ConfigurationStore(directory: directory)
            let session = try SessionManager(directory: directory, settingsFile: config.file)
            self.controller = Controller(config: config, session: session)
        } catch {
            NSApp.presentError(error)
            NSApp.terminate(nil)
            return
        }
        
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(self.workspaceWillSleep(_:)),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        
        self.controller?.start()
        for url in self.pendingURLs {
            self.controller?.openFile(url)
        }
        self.pendingURLs.removeAll()
    }
    
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let controller = self.controller else {
            self.pendingURLs.append(contentsOf: urls)
            return
        }
        
        for url in urls {
            controller.openFile(url)
        }
    }
    
    @objc private func workspaceWillSleep(_ notification: Notification) {
        self.controller?.flush()
    }
    
    func applicationWillResignActive(_ notification: Notification) {
        self.controller?.flush()
    }
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        do {
            try self.controller?.session.flush()
            return .terminateNow
        } catch {
            sender.presentError(error)
            return .terminateCancel
        }
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        self.controller?.focus()
        return false
    }
}
