//
//  Updater.swift
//  Jotting
//
//  Created by Serhiy Mytrovtsiy on 20/11/2026.
//  Using Swift 6.0.
//  Running on macOS 27.2.
//
//  Copyright © 2026 Serhiy Mytrovtsiy. All rights reserved.
//

import AppKit
import Updater

@MainActor
final class UpdateController {
    private let provider = Updater.Github(user: "exelban", repo: "jotting", asset: "Jotting.dmg")
    private let updater: Updater
    private let session: SessionManager
    private var available: (version: String, url: URL?)? {
        didSet { self.onUpdate?() }
    }
    private var interactive = false
    private var checking = false
    var availableVersion: String? { self.available?.version }
    var onUpdate: (() -> Void)?
    private(set) var installing = false {
        didSet { self.onUpdate?() }
    }
    
    init(session: SessionManager) {
        self.session = session
        self.updater = Updater(name: "Jotting", providers: [self.provider])
        self.cleanUpInstallation()
    }
    
    func check(silently: Bool = false) {
        guard !self.installing else {
            return
        }
        
        #if DEBUG
        if CommandLine.arguments.contains("--simulate-update") {
            self.available = ("1.1.0", nil)
            if !silently {
                self.showUpdate()
            }
            return
        }
        #endif
        
        self.interactive = self.interactive || !silently
        guard !self.checking else {
            return
        }
        self.checking = true
        
        self.provider.latest { release, error in
            Task { @MainActor in
                self.finishCheck(release, error: error)
            }
        }
    }
    
    private func finishCheck(_ release: Updater.Release?, error: Error?) {
        self.checking = false
        let interactive = self.interactive
        self.interactive = false
        guard !self.installing else {
            return
        }
        guard let release, let url = URL(string: release.url),
            url.scheme == "https", url.host == "github.com",
            url.path.hasPrefix("/exelban/jotting/releases/download/"), url.lastPathComponent == "Jotting.dmg"
        else {
            if interactive {
                NSApp.presentError(error ?? StorageError("Could not find a published Jotting update."))
            }
            return
        }
        
        let installed = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        if release.tag.isUpdate(for: Updater.Tag(installed)) {
            self.available = (release.tag.raw, url)
            if interactive {
                self.showUpdate()
            }
        } else {
            self.available = nil
            if interactive {
                let alert = NSAlert()
                alert.messageText = "Jotting is up to date"
                alert.informativeText = "Installed version \(installed)."
                alert.runModal()
            }
        }
    }
    
    func showUpdate() {
        guard let available, !self.installing else {
            return
        }
        
        let alert = NSAlert()
        alert.messageText = "Jotting \(available.version) is available"
        alert.informativeText = "Jotting will download the update, save your buffers, and restart."
        alert.addButton(withTitle: "Install and Relaunch")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn, let url = available.url else {
            return
        }
        
        self.installing = true
        self.updater.downloadFile(url) { result in
            Task { @MainActor in
                do {
                    let image = try result.get()
                    let verify = Process()
                    verify.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
                    verify.arguments = ["--verify", "-R=anchor apple generic and certificate leaf[subject.OU] = RP2S87B72W", image.path]
                    try verify.run()
                    verify.waitUntilExit()
                    guard verify.terminationStatus == 0 else {
                        throw StorageError("The downloaded update could not be verified.")
                    }
                    
                    try self.session.flush()
                    self.updater.install(image) { error in
                        Task { @MainActor in
                            self.installing = false
                            NSApp.presentError(error)
                        }
                    }
                } catch {
                    self.installing = false
                    NSApp.presentError(error)
                }
            }
        }
    }
    
    private func cleanUpInstallation() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count == 4, args[0] == "--dmg-path", args[2] == "--mount-path", args[3] == "/tmp/Jotting" else {
            return
        }
        
        let image = URL(fileURLWithPath: args[1]).standardizedFileURL
        guard image.deletingLastPathComponent().path == FileManager.default.temporaryDirectory.standardizedFileURL.path,
            image.lastPathComponent.range(of: #"^Jotting-[0-9A-F-]{36}\.dmg$"#, options: .regularExpression) != nil
        else {
            return
        }
        
        let detach = Process()
        detach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        detach.arguments = ["detach", args[3]]
        detach.terminationHandler = { process in
            if process.terminationStatus == 0 {
                try? FileManager.default.removeItem(at: image)
                rmdir("/tmp/Jotting")
            }
        }
        try? detach.run()
    }
}
