//
//  Settings.swift
//  Jotting
//
//  Created by Serhiy Mytrovtsiy on 20/11/2026.
//  Using Swift 6.0.
//  Running on macOS 27.2.
//
//  Copyright © 2026 Serhiy Mytrovtsiy. All rights reserved.
//

import AppKit

enum Appearance: String, Codable, CaseIterable {
    case system, light, dark
}

enum InterfaceStyle: String, Codable, CaseIterable {
    case classic, glass
}

struct Theme: Decodable {
    struct Color: Decodable {
        let value: NSColor
        
        init(from decoder: Decoder) throws {
            let token = try decoder.singleValueContainer().decode(String.self)
            switch token {
            case "textBackgroundColor": self.value = .textBackgroundColor
            case "controlBackgroundColor": self.value = .controlBackgroundColor
            case "textColor": self.value = .textColor
            case "labelColor": self.value = .labelColor
            case "secondaryLabelColor": self.value = .secondaryLabelColor
            case "controlAccentColor": self.value = .controlAccentColor
            case "selectedTextBackgroundColor": self.value = .selectedTextBackgroundColor
            default:
                let digits = token.dropFirst()
                guard token.first == "#", digits.count == 6, digits.allSatisfy(\.isHexDigit),
                    let rgb = UInt32(digits, radix: 16)
                else {
                    throw StorageError("Unknown theme color ‘\(token)’. Use a native color name or #RRGGBB.")
                }
                self.value = NSColor(
                    srgbRed: CGFloat(rgb >> 16) / 255, green: CGFloat((rgb >> 8) & 255) / 255,
                    blue: CGFloat(rgb & 255) / 255, alpha: 1)
            }
        }
    }
    
    struct Palette: Decodable {
        let background, surface, text, secondaryText, accent, selection: Color
        let label, caret, tabTrack: Color?
        var labelColor: Color { self.label ?? self.text }
        var caretColor: Color { self.caret ?? self.text }
        var trackColor: NSColor { self.tabTrack?.value ?? self.labelColor.value.withAlphaComponent(0.085) }
    }
    
    let name: String
    let light: Palette
    let dark: Palette
    static var current: Theme!
    
    static func color(_ key: KeyPath<Palette, Color>) -> NSColor {
        Self.color(key.appending(path: \.value))
    }
    
    static func color(_ key: KeyPath<Palette, NSColor>) -> NSColor {
        let light = Self.current.light[keyPath: key]
        let dark = Self.current.dark[keyPath: key]
        if light == dark {
            return light
        }
        return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }
    
    static func identifiers(in directory: URL) -> [String] {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("Themes")
        let files = [bundled, directory].compactMap { $0 }.flatMap { folder in
            (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        }
        return Set(files.filter { $0.pathExtension == "json" }.map { $0.deletingPathExtension().lastPathComponent }).sorted()
    }
    
    static func load(_ id: String, directory: URL) throws -> Theme {
        guard !id.isEmpty, !id.contains("/") else {
            throw StorageError("Invalid theme filename ‘\(id)’.")
        }
        
        let url = Bundle.main.url(forResource: id, withExtension: "json", subdirectory: "Themes")
            ?? directory.appendingPathComponent(id + ".json")
        do {
            return try JSONDecoder().decode(Theme.self, from: Data(contentsOf: url))
        } catch {
            throw StorageError("Could not load \(url.lastPathComponent). Both light and dark palettes are required. " +
                error.localizedDescription)
        }
    }
}

enum LineMarker: String, Codable, CaseIterable {
    case none, dot, number
}

struct Shortcut: Codable, Equatable {
    enum Modifier: String, Codable, CaseIterable {
        case control, option, shift, command
    }
    
    var key: String
    var modifiers: [Modifier]
}

struct FontSettings: Codable {
    enum Weight: String, Codable, CaseIterable {
        case ultraLight, thin, light, regular, medium, semibold, bold, heavy, black
    }
    
    static let sizes = 8...72
    static let lineHeights = 1.0...3.0
    var size = 13
    var family = "monospaced"
    var weight = Weight.regular
    var lineHeight = 1.0
}

struct Configuration: Codable {
    var launchAtLogin = true
    var dockIcon = true
    var menuBar = true
    var globalShortcut: Shortcut? = Shortcut(key: ",", modifiers: [.control])
    var theme = "default"
    var appearance = Appearance.system
    var interfaceStyle = InterfaceStyle.classic
    var font = FontSettings()
    var lineMarker = LineMarker.none
    
    init() {}
    
    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        let interface = try fields.nestedContainer(keyedBy: InterfaceKeys.self, forKey: .interface)
        let application = try fields.nestedContainer(keyedBy: ApplicationKeys.self, forKey: .application)
        self.launchAtLogin = try application.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? true
        self.dockIcon = try application.decodeIfPresent(Bool.self, forKey: .dockIcon) ?? true
        self.menuBar = try application.decodeIfPresent(Bool.self, forKey: .menuBar) ?? true
        
        if application.contains(.globalShortcut) {
            self.globalShortcut = try application.decodeIfPresent(Shortcut.self, forKey: .globalShortcut)
        }
        
        self.theme = try interface.decodeIfPresent(String.self, forKey: .theme) ?? "default"
        self.appearance = try interface.decodeIfPresent(Appearance.self, forKey: .appearance) ?? .system
        self.interfaceStyle = try interface.decodeIfPresent(InterfaceStyle.self, forKey: .interfaceStyle) ?? .classic
        self.font = try fields.decodeIfPresent(FontSettings.self, forKey: .font) ?? FontSettings()
        self.font.size = max(FontSettings.sizes.lowerBound, min(FontSettings.sizes.upperBound, self.font.size))
        self.font.lineHeight = max(
            FontSettings.lineHeights.lowerBound, min(FontSettings.lineHeights.upperBound, self.font.lineHeight))
            
        self.lineMarker = try interface.decodeIfPresent(LineMarker.self, forKey: .lineMarker) ?? .none
    }
    
    func encode(to encoder: Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        var interface = fields.nestedContainer(keyedBy: InterfaceKeys.self, forKey: .interface)
        var application = fields.nestedContainer(keyedBy: ApplicationKeys.self, forKey: .application)
        try application.encode(self.launchAtLogin, forKey: .launchAtLogin)
        try application.encode(self.dockIcon, forKey: .dockIcon)
        try application.encode(self.menuBar, forKey: .menuBar)
        try application.encode(self.globalShortcut, forKey: .globalShortcut)
        try interface.encode(self.theme, forKey: .theme)
        try interface.encode(self.appearance, forKey: .appearance)
        try interface.encode(self.interfaceStyle, forKey: .interfaceStyle)
        try fields.encode(self.font, forKey: .font)
        try interface.encode(self.lineMarker, forKey: .lineMarker)
    }
    
    enum ApplicationKeys: String, CodingKey, CaseIterable {
        case launchAtLogin, dockIcon, menuBar, globalShortcut
    }
    
    enum InterfaceKeys: String, CodingKey, CaseIterable {
        case appearance, theme, interfaceStyle, lineMarker
    }
    
    private enum CodingKeys: String, CodingKey {
        case application, interface, font
    }
}

final class ConfigurationStore {
    static let title = "Jotting settings"
    let themes: URL
    let file: URL
    private(set) var value = Configuration()
    private(set) var warning: String?
    private var invalidData: Data?
    
    init(directory: URL) throws {
        self.themes = directory.appendingPathComponent("Themes", isDirectory: true)
        try FileManager.default.createDirectory(at: self.themes, withIntermediateDirectories: true)
        Theme.current = try Theme.load("default", directory: self.themes)
        self.file = directory.appendingPathComponent("config.json")
        
        let data: Data
        do {
            data = try Data(contentsOf: self.file)
        } catch CocoaError.fileReadNoSuchFile {
            try Self.fillingDefaults(in: Data("{}".utf8)).write(to: self.file, options: .atomic)
            return
        }
        
        do {
            self.value = try JSONDecoder().decode(Configuration.self, from: Self.fillingDefaults(in: data))
        } catch {
            self.invalidData = data
            self.warning =
                "Jotting could not read config.json. Using defaults. Saving settings will preserve the original in a separate file."
        }
    }
    
    static func fillingDefaults(in data: Data) throws -> Data {
        guard var fields = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let defaults = try JSONSerialization.jsonObject(with: encodeJSON(Configuration())) as? [String: Any]
        else {
            throw StorageError("Settings must be a JSON object.")
        }
        
        if let oldMenuBar = fields.removeValue(forKey: "showMenuBarIcon"), fields["menuBar"] == nil {
            fields["menuBar"] = oldMenuBar
        }
        
        func migrate(_ section: String, keys: [String]) throws {
            var nested = [String: Any]()
            if let existing = fields[section] {
                guard let object = existing as? [String: Any] else {
                    throw StorageError("Settings section '\(section)' must be a JSON object.")
                }
                nested = object
            }
            for key in keys {
                if let oldValue = fields.removeValue(forKey: key), nested[key] == nil {
                    nested[key] = oldValue
                }
            }
            fields[section] = nested
        }
        
        try migrate("interface", keys: Configuration.InterfaceKeys.allCases.map(\.rawValue))
        try migrate("application", keys: Configuration.ApplicationKeys.allCases.map(\.rawValue))
        var completed = merge(fields, defaults)
        if var interface = completed["interface"] as? [String: Any], interface["lineMarker"] is NSNull {
            interface["lineMarker"] = LineMarker.none.rawValue
            completed["interface"] = interface
        }
        
        if let oldSize = completed.removeValue(forKey: "fontSize"),
            (fields["font"] as? [String: Any])?["size"] == nil, var font = completed["font"] as? [String: Any]
        {
            if !(oldSize is NSNull) {
                font["size"] = oldSize
            }
            completed["font"] = font
        }
        
        if var font = completed["font"] as? [String: Any], let height = font["lineHeight"] as? NSNumber,
            CFNumberIsFloatType(height), !(height is NSDecimalNumber), FontSettings.lineHeights.contains(height.doubleValue)
        {
            font["lineHeight"] = NSDecimalNumber(string: String(height.doubleValue))
            completed["font"] = font
        }
        
        completed.removeValue(forKey: "version")
        completed.removeValue(forKey: "detachTabOutsideWindow")
        return try Self.formatSections(completed)
    }
    
    private static func merge(_ fields: [String: Any], _ defaults: [String: Any]) -> [String: Any] {
        fields.merging(defaults) { field, fallback in
            guard let object = field as? [String: Any], let nested = fallback as? [String: Any] else {
                return field
            }
            
            return merge(object, nested)
        }
    }
    
    private static func formatSections(_ completed: [String: Any]) throws -> Data {
        func member(_ key: String, value: Any) throws -> String {
            let data = try JSONSerialization.data(withJSONObject: [key: value], options: [.prettyPrinted, .sortedKeys])
            guard let text = String(data: data, encoding: .utf8) else {
                throw StorageError("Settings must contain UTF-8 text.")
            }
            return text.split(separator: "\n").dropFirst().dropLast().joined(separator: "\n")
        }
        
        let sections = ["application", "interface", "font"]
        let keys = sections + completed.keys.filter { !sections.contains($0) }.sorted()
        let members = try keys.map { key in
            guard key == "application", let application = completed[key] as? [String: Any] else {
                return try member(key, value: completed[key]!)
            }
            
            let keys = application.keys.filter { $0 != "globalShortcut" }.sorted() + ["globalShortcut"]
            let fields = try keys.map { try member($0, value: application[$0]!) }
            let lines = fields.joined(separator: ",\n").split(separator: "\n")
            return "  \"application\" : {\n" + lines.map { "  " + $0 }.joined(separator: "\n") + "\n  }"
        }
        return Data(("{\n" + members.joined(separator: ",\n") + "\n}").utf8)
    }
    
    func configuration(from text: String) throws -> (value: Configuration, text: String) {
        let data = try Self.fillingDefaults(in: Data((text.allSatisfy(\.isWhitespace) ? "{}" : text).utf8))
        
        let updated = try JSONDecoder().decode(Configuration.self, from: data)
        guard let text = String(data: data, encoding: .utf8) else {
            throw StorageError("Settings must contain UTF-8 text.")
        }
        return (updated, text)
    }
    
    func save(_ changes: [String: Any], section: String) throws {
        let data = try Self.fillingDefaults(in: Data(contentsOf: self.file))
        guard var fields = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            var settings = fields[section] as? [String: Any]
        else {
            throw StorageError("Could not read settings section ‘\(section)’.")
        }
        settings.merge(changes) { _, new in new }
        fields[section] = settings
        let updated = try JSONSerialization.data(withJSONObject: fields)
        guard let json = String(data: updated, encoding: .utf8) else {
            throw StorageError("Settings must contain UTF-8 text.")
        }
        
        let (value, text) = try self.configuration(from: json)
        try self.save(value, text: text)
    }
    
    func save(_ updated: Configuration, text: String) throws {
        if let invalidData {
            let backup = self.file.deletingLastPathComponent().appendingPathComponent(
                "config.invalid-\(UUID().uuidString).json")
            try invalidData.write(to: backup, options: .withoutOverwriting)
            self.invalidData = nil
        }
        
        try text.write(to: self.file, atomically: true, encoding: .utf8)
        self.value = updated
    }
}

private func addSection(_ title: String, _ rows: [(String, String)], to stack: NSStackView) {
    let heading = NSTextField(labelWithString: title)
    heading.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
    heading.isSelectable = true
    stack.addArrangedSubview(heading)
    
    let grid = NSGridView(views: rows.map { key, value in
        let label = NSTextField(labelWithString: key)
        label.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.isSelectable = true
        let field = NSTextField(wrappingLabelWithString: value)
        field.isSelectable = true
        field.preferredMaxLayoutWidth = 158
        return [label, field]
    })
    grid.columnSpacing = 16
    grid.rowSpacing = 8
    grid.yPlacement = .top
    stack.addArrangedSubview(grid)
}

private func settingsReference(themes: [String], modified: Date?) -> NSViewController {
    let defaults = Configuration()
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 14
    stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
    
    addSection("application", [
        ("launchAtLogin", "true · false"),
        ("dockIcon", "true · false"),
        ("menuBar", "true · false"),
        ("globalShortcut", "key and modifiers · null to disable")
    ], to: stack)
    addSection("interface", [
        ("appearance", Appearance.allCases.map(\.rawValue).joined(separator: " · ")),
        ("theme", themes.joined(separator: " · ")),
        ("interfaceStyle", InterfaceStyle.allCases.map(\.rawValue).joined(separator: " · ")),
        ("lineMarker", LineMarker.allCases.map(\.rawValue).joined(separator: " · "))
    ], to: stack)
    addSection("font", [
        ("size", "\(FontSettings.sizes.lowerBound)–\(FontSettings.sizes.upperBound) pt (default \(defaults.font.size))"),
        ("family", "monospaced (default) · system · installed font family"),
        ("weight", FontSettings.Weight.allCases.map(\.rawValue).joined(separator: " · ")),
        ("lineHeight", "1–3 × natural line height (default \(defaults.font.lineHeight))")
    ], to: stack)
    
    if let modified {
        let label = NSTextField(labelWithString: "Last modified \(modified.formatted(date: .abbreviated, time: .shortened))")
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        label.isSelectable = true
        stack.addArrangedSubview(label)
    }
    
    let controller = NSViewController()
    controller.view = stack
    controller.preferredContentSize = stack.fittingSize
    return controller
}

final class SettingsHelpButton: NSButton {
    private let file: URL
    private var reference: NSPopover?
    
    init(file: URL) {
        self.file = file
        super.init(frame: .zero)
        
        self.bezelStyle = .helpButton
        self.title = ""
        self.toolTip = "Settings reference"
        self.setAccessibilityLabel("Settings reference")
        self.target = self
        self.action = #selector(self.showReference)
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }
    
    override func viewDidHide() {
        super.viewDidHide()
        self.reference?.performClose(nil)
    }
    
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            self.reference?.performClose(nil)
        }
        
        super.viewWillMove(toWindow: newWindow)
    }
    
    @objc private func showReference() {
        if self.reference?.isShown == true {
            self.reference?.performClose(nil)
            return
        }
        
        let attributes = try? FileManager.default.attributesOfItem(atPath: self.file.path)
        let modified = attributes?[.modificationDate] as? Date
        let directory = self.file.deletingLastPathComponent().appendingPathComponent("Themes")
        let reference = NSPopover()
        reference.behavior = .transient
        reference.contentViewController = settingsReference(themes: Theme.identifiers(in: directory), modified: modified)
        self.reference = reference
        reference.show(relativeTo: self.bounds, of: self, preferredEdge: .maxY)
    }
}
