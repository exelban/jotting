//
//  Persistence.swift
//  Jotting
//
//  Created by Serhiy Mytrovtsiy on 19/11/2026.
//  Using Swift 6.0.
//  Running on macOS 27.2.
//
//  Copyright © 2026 Serhiy Mytrovtsiy. All rights reserved.
//

import Foundation

func applicationSupportDirectory() throws -> URL {
    let support = try FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
    )
    
    return support.appendingPathComponent("Jotting", isDirectory: true)
}

struct StorageError: LocalizedError {
    let message: String
    init(_ message: String) {
        self.message = message
    }
    
    var errorDescription: String? { self.message }
}

func encodeJSON<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(value)
}

private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
    try encodeJSON(value).write(to: url, options: .atomic)
}

struct WindowSession: Codable {
    let id: UUID
    var tabs: [UUID]
    var selected: UUID
    
    init(id: UUID = UUID(), tabs: [UUID], selected: UUID) {
        self.id = id
        self.tabs = tabs
        self.selected = selected
    }
}

struct Session: Codable {
    var windows: [WindowSession]
    var tabs: [UUID] { self.windows.flatMap(\.tabs) }
    var history: [UUID] = []
    var writerTabs: Set<UUID> = []
    var names: [String: String]?
    var files: [String: URL]?
    
    mutating func remember(_ url: URL, for id: UUID) {
        if self.files == nil {
            self.files = [:]
        }
        
        self.files?[id.uuidString] = url
    }
    
    init() {
        let note = UUID()
        self.windows = [WindowSession(tabs: [note], selected: note)]
    }
    
    private enum CodingKeys: String, CodingKey {
        case windows, tabs, selected, history, names, files, writerTabs
    }
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if values.contains(.windows) {
            self.windows = try values.decode([WindowSession].self, forKey: .windows)
        } else {
            let tabs = try values.decode([UUID].self, forKey: .tabs)
            let selected = try values.decode(UUID.self, forKey: .selected)
            self.windows = [WindowSession(id: selected, tabs: tabs, selected: selected)]
        }
        self.history = try values.decodeIfPresent([UUID].self, forKey: .history) ?? []
        self.writerTabs = try values.decodeIfPresent(Set<UUID>.self, forKey: .writerTabs) ?? []
        self.names = try values.decodeIfPresent([String: String].self, forKey: .names)
        self.files = try values.decodeIfPresent([String: URL].self, forKey: .files)
        guard !self.windows.isEmpty, self.windows.allSatisfy({ $0.tabs.contains($0.selected) }),
            Set(self.windows.map(\.id)).count == self.windows.count, Set(self.tabs).count == self.tabs.count else {
            throw StorageError("Invalid window or tab order.")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(self.windows, forKey: .windows)
        try values.encode(self.tabs, forKey: .tabs)
        try values.encode(self.windows[0].selected, forKey: .selected)
        try values.encode(self.history, forKey: .history)
        if !self.writerTabs.isEmpty {
            try values.encode(self.writerTabs.sorted { $0.uuidString < $1.uuidString }, forKey: .writerTabs)
        }
        try values.encodeIfPresent(self.names, forKey: .names)
        try values.encodeIfPresent(self.files, forKey: .files)
    }
}

final class BufferStore {
    let directory: URL
    
    init(directory: URL) throws {
        self.directory = directory.appendingPathComponent("buffers", isDirectory: true)
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }
    
    func file(_ id: UUID) -> URL {
        self.directory.appendingPathComponent(id.uuidString + ".txt")
    }
    
    func read(_ id: UUID) throws -> String {
        try String(contentsOf: self.file(id), encoding: .utf8)
    }
    
    func write(_ text: String, for id: UUID) throws {
        try text.write(to: self.file(id), atomically: true, encoding: .utf8)
    }
}

final class SessionManager {
    static let noteExtensions = [
        "txt", "md", "markdown", "mdown", "mkd", "log", "json", "yaml", "yml", "toml", "ini", "csv", "tsv"
    ]
    private static let historyLimit = 30
    private let file: URL
    private let settingsFile: URL
    let buffers: BufferStore
    private(set) var isFirstLaunch = false
    private(set) var state: Session
    private var pending: [UUID: () -> String] = [:]
    private var previews: [UUID: String] = [:]
    private var closed: [UUID] = []
    private var reopened: [UUID] = []
    var lastReopened: UUID? { self.reopened.last }
    var lastClosed: UUID? { self.closed.last }
    private var timer: Timer?
    var onError: ((Error) -> Void)?
    
    init(directory: URL, settingsFile: URL) throws {
        self.file = directory.appendingPathComponent("session.json")
        self.settingsFile = settingsFile
        self.buffers = try BufferStore(directory: directory)
        do {
            self.state = try JSONDecoder().decode(Session.self, from: Data(contentsOf: self.file))
            var restored = self.state
            let open = Set(restored.tabs)
            let notes = restored.history.lazy.filter { id in
                !open.contains(id) && restored.files?[id.uuidString] != settingsFile
            }
            restored.history = Array(notes.prefix(Self.historyLimit))
            if restored.history != self.state.history {
                try self.commit(restored)
            }
        } catch CocoaError.fileReadNoSuchFile {
            self.isFirstLaunch = true
            self.state = Session()
            try self.buffers.write("", for: self.state.windows[0].selected)
            try writeJSON(self.state, to: self.file)
        }
    }
    
    private func preview(_ text: String) -> String {
        let opening = text.drop(while: \.isWhitespace).prefix(64)
        let words = opening.split(whereSeparator: \.isWhitespace).prefix(6)
        return words.isEmpty ? "Untitled" : words.joined(separator: " ")
    }
    
    func title(for id: UUID) -> String {
        if let name = self.state.names?[id.uuidString] {
            return name
        }
        
        if let url = self.state.files?[id.uuidString] {
            return url == self.settingsFile ? ConfigurationStore.title : url.lastPathComponent
        }
        
        if let title = self.previews[id] {
            return title
        }
        
        guard let text = self.pending[id]?() ?? (try? self.buffers.read(id)) else {
            return "Untitled"
        }
        
        let title = self.preview(text)
        self.previews[id] = title
        return title
    }
    
    func rename(_ id: UUID, to value: String) throws {
        guard self.state.tabs.contains(id) else {
            return
        }
        
        var next = self.state
        var names = next.names ?? [:]
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        names[id.uuidString] = name.isEmpty ? nil : name
        next.names = names.isEmpty ? nil : names
        try self.commit(next)
    }
    
    func toggleWriterMode(for id: UUID) throws {
        var next = self.state
        if next.writerTabs.remove(id) == nil {
            next.writerTabs.insert(id)
        }
        try self.commit(next)
    }
    
    func changed(_ id: UUID, text: @escaping () -> String) {
        self.previews.removeValue(forKey: id)
        self.pending[id] = text
        self.reopened.removeAll()
        
        self.timer?.invalidate()
        self.timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            guard let self else {
                return
            }
            
            do {
                try self.flush()
            } catch {
                self.onError?(error)
            }
        }
    }
    
    func flush() throws {
        self.timer?.invalidate()
        self.timer = nil
        for (id, text) in self.pending {
            try self.buffers.write(text(), for: id)
            self.pending.removeValue(forKey: id)
        }
    }
    
    private func commit(_ next: Session) throws {
        var next = next
        let removed = Set(self.state.tabs + self.state.history)
            .subtracting(next.tabs + next.history)
        next.writerTabs.subtract(removed)
        for id in removed {
            next.names?.removeValue(forKey: id.uuidString)
            next.files?.removeValue(forKey: id.uuidString)
        }
        
        try writeJSON(next, to: self.file)
        self.state = next
        self.closed.removeAll { removed.contains($0) || next.tabs.contains($0) }
        for id in removed {
            self.previews.removeValue(forKey: id)
            do {
                try FileManager.default.removeItem(at: self.buffers.file(id))
            } catch {
                self.onError?(error)
            }
        }
    }
    
    private func recordClosed(_ id: UUID, in state: inout Session) throws {
        guard state.files?[id.uuidString] != self.settingsFile, try !self.buffers.read(id).allSatisfy(\.isWhitespace) else {
            return
        }
        
        state.history.insert(id, at: 0)
        state.history = Array(state.history.prefix(Self.historyLimit))
    }
    
    private func validateNote(_ url: URL) throws {
        guard url.isFileURL, Self.noteExtensions.contains(url.pathExtension.lowercased()) else {
            throw StorageError("Supported file extensions: " + Self.noteExtensions.joined(separator: ", ") + ".")
        }
    }
    
    func add(from url: URL? = nil, in window: UUID) throws {
        guard let url else {
            try self.add(text: "", file: nil, in: window)
            return
        }
        
        try self.validateNote(url)
        if let id = self.state.tabs.first(where: { self.state.files?[$0.uuidString] == url }) {
            try self.select(id, in: window)
            return
        }
        
        try self.add(text: String(contentsOf: url, encoding: .utf8), file: url, in: window)
    }
    
    func openSettings(in window: UUID) throws {
        if let id = self.state.tabs.first(where: { self.state.files?[$0.uuidString] == self.settingsFile }) {
            try self.select(id, in: window)
            return
        }
        
        let data = try Data(contentsOf: self.settingsFile)
        let contents = (try? ConfigurationStore.fillingDefaults(in: data)) ?? data
        // Preserve readable portions of a damaged settings file so it can be repaired.
        // swiftlint:disable:next optional_data_string_conversion
        let text = String(decoding: contents, as: UTF8.self)
        try self.add(text: text, file: self.settingsFile, in: window)
    }
    
    func newWindow() throws -> UUID {
        let window = UUID()
        try self.add(text: "", file: nil, in: window)
        return window
    }
    
    private func add(text: String, file: URL?, in window: UUID) throws {
        var next = self.state
        let id = UUID()
        if let file {
            next.remember(file, for: id)
        }
        if let index = next.windows.firstIndex(where: { $0.id == window }) {
            next.windows[index].tabs.append(id)
            next.windows[index].selected = id
        } else {
            next.windows.append(WindowSession(id: window, tabs: [id], selected: id))
        }
        try self.buffers.write(text, for: id)
        do {
            try self.commit(next)
        } catch {
            try? FileManager.default.removeItem(at: self.buffers.file(id))
            throw error
        }
    }
    
    func save(_ text: String, for id: UUID, to url: URL) throws {
        try self.validateNote(url)
        try text.write(to: url, atomically: true, encoding: .utf8)
        let file = self.state.files?[id.uuidString]
        guard file != url, file != self.settingsFile else {
            return
        }
        
        var next = self.state
        next.remember(url, for: id)
        try self.commit(next)
    }
    
    func close(_ old: UUID) throws {
        guard let source = self.state.windows.firstIndex(where: { $0.tabs.contains(old) }) else {
            return
        }
        try self.flush()
        var next = self.state
        try self.recordClosed(old, in: &next)
        self.remove(old, from: source, in: &next)
        if next.windows.isEmpty {
            let id = UUID()
            try self.buffers.write("", for: id)
            next.windows = [WindowSession(id: self.state.windows[source].id, tabs: [id], selected: id)]
            do {
                try self.commit(next)
            } catch {
                try? FileManager.default.removeItem(at: self.buffers.file(id))
                throw error
            }
        } else {
            try self.commit(next)
        }
        self.reopened.removeAll { $0 == old }
        if next.history.contains(old) {
            self.closed.append(old)
        }
    }
    
    func clearHistory() throws {
        var next = self.state
        next.history = []
        try self.commit(next)
        self.reopened.removeAll()
    }
    
    func reopenLastClosed(in window: UUID) throws {
        guard let id = self.lastClosed else {
            return
        }
        try self.select(id, in: window)
        self.reopened.append(id)
    }
    
    func select(_ id: UUID, in window: UUID) throws {
        var next = self.state
        guard let index = next.windows.firstIndex(where: { $0.tabs.contains(id) })
            ?? next.windows.firstIndex(where: { $0.id == window }) else {
            return
        }
        if !next.windows[index].tabs.contains(id) {
            guard let position = next.history.firstIndex(of: id) else {
                return
            }
            _ = try self.buffers.read(id)
            next.history.remove(at: position)
            next.windows[index].tabs.append(id)
        }
        guard next.windows[index].selected != id else {
            return
        }
        next.windows[index].selected = id
        try self.commit(next)
    }
    
    func move(_ id: UUID, to index: Int) throws {
        var next = self.state
        guard let source = next.windows.firstIndex(where: { $0.tabs.contains(id) }),
            let old = next.windows[source].tabs.firstIndex(of: id), old != index,
            next.windows[source].tabs.indices.contains(index) else {
            return
        }
        next.windows[source].tabs.remove(at: old)
        next.windows[source].tabs.insert(id, at: index)
        try self.commit(next)
    }
    
    func transfer(_ id: UUID, to window: UUID, at position: Int? = nil) throws {
        var next = self.state
        guard let source = next.windows.firstIndex(where: { $0.tabs.contains(id) }), next.windows[source].id != window else {
            return
        }
        self.remove(id, from: source, in: &next)
        if let index = next.windows.firstIndex(where: { $0.id == window }) {
            let count = next.windows[index].tabs.count
            next.windows[index].tabs.insert(id, at: min(max(0, position ?? count), count))
            next.windows[index].selected = id
        } else {
            next.windows.append(WindowSession(id: window, tabs: [id], selected: id))
        }
        try self.commit(next)
    }
    
    private func remove(_ id: UUID, from index: Int, in session: inout Session) {
        var window = session.windows[index]
        guard let position = window.tabs.firstIndex(of: id) else {
            return
        }
        window.tabs.remove(at: position)
        if window.tabs.isEmpty {
            session.windows.remove(at: index)
        } else {
            if window.selected == id {
                window.selected = window.tabs[min(position, window.tabs.count - 1)]
            }
            session.windows[index] = window
        }
    }
    
    func closeWindow(_ window: UUID) throws {
        try self.flush()
        guard self.state.windows.count > 1, let index = self.state.windows.firstIndex(where: { $0.id == window }) else {
            return
        }
        
        var next = self.state
        let group = next.windows.remove(at: index)
        let tabs = group.tabs.filter { $0 != group.selected } + [group.selected]
        for id in tabs {
            try self.recordClosed(id, in: &next)
        }
        try self.commit(next)
        self.reopened.removeAll { tabs.contains($0) }
        self.closed.append(contentsOf: tabs.filter { next.history.contains($0) })
    }
}
