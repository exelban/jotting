//
//  Shortcut.swift
//  Jotting
//
//  Created by Serhiy Mytrovtsiy on 19/11/2026.
//  Using Swift 6.0.
//  Running on macOS 27.2.
//
//  Copyright © 2026 Serhiy Mytrovtsiy. All rights reserved.
//

import AppKit
import Carbon

extension Shortcut.Modifier {
    var carbon: Int {
        switch self {
        case .control: return controlKey
        case .option: return optionKey
        case .shift: return shiftKey
        case .command: return cmdKey
        }
    }
    
    var symbol: String {
        switch self {
        case .control: return "⌃"
        case .option: return "⌥"
        case .shift: return "⇧"
        case .command: return "⌘"
        }
    }
}

extension Shortcut {
    static let keys: [UInt16: String] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v", 11: "b",
        12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4",
        22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "o",
        32: "u", 33: "[", 34: "i", 35: "p", 36: "return", 37: "l", 38: "j", 39: "'", 40: "k",
        41: ";", 42: "\\", 43: ",", 44: "/", 45: "n", 46: "m", 47: ".", 48: "tab", 49: "space",
        50: "`", 51: "delete", 96: "f5", 97: "f6", 98: "f7", 99: "f3", 100: "f8", 101: "f9",
        103: "f11", 109: "f10", 111: "f12", 118: "f4", 120: "f2", 122: "f1", 123: "left",
        124: "right", 125: "down", 126: "up"
    ]
    
    var display: String {
        let symbols = [
            "space": "Space", "return": "↩", "tab": "⇥", "delete": "⌫", "left": "←", "right": "→", "up": "↑",
            "down": "↓"
        ]
        let prefix = Modifier.allCases.filter { self.modifiers.contains($0) }.map(\.symbol).joined()
        return prefix + (symbols[self.key] ?? self.layoutLabel ?? self.key.uppercased())
    }
    
    private var layoutLabel: String? {
        guard self.key.count == 1, let code = Self.keys.first(where: { $0.value == self.key })?.key,
            let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else {
            return nil
        }
        
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
        let layout = UnsafeRawPointer(CFDataGetBytePtr(data)!).assumingMemoryBound(to: UCKeyboardLayout.self)
        
        var deadKey: UInt32 = 0
        var count = 0
        var characters = [UniChar](repeating: 0, count: 8)
        
        let status = UCKeyTranslate(
            layout, code, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
            UInt32(kUCKeyTranslateNoDeadKeysMask), &deadKey, characters.count, &count, &characters)
        guard status == noErr, count > 0 else {
            return nil
        }
        
        return String(utf16CodeUnits: characters, count: count).uppercased()
    }
    
    var valid: Bool { self.modifiers.contains { $0 != .shift } }
}

final class ShortcutManager {
    private var registration: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private(set) var current: Shortcut?
    var activate: (() -> Void)?
    
    init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let context, let event else {
                    return OSStatus(eventNotHandledErr)
                }
                
                var id = EventHotKeyID()
                let status = GetEventParameter(
                    event, UInt32(kEventParamDirectObject), UInt32(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                guard status == noErr, id.signature == 0x6A6F7474, id.id == 1 else {
                    return OSStatus(eventNotHandledErr)
                }
                Unmanaged<ShortcutManager>.fromOpaque(context).takeUnretainedValue().activate?()
                return noErr
            }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &self.handler)
    }
    
    func set(_ shortcut: Shortcut?) throws {
        guard shortcut != self.current else {
            return
        }
        
        var replacement: EventHotKeyRef?
        if let shortcut {
            guard self.handler != nil, shortcut.valid, let key = Shortcut.keys.first(where: { $0.value == shortcut.key })
            else {
                throw StorageError("Choose a supported key with Control, Option, or Command.")
            }
            
            let modifiers = shortcut.modifiers.reduce(0) { $0 | $1.carbon }
            let status = RegisterEventHotKey(
                UInt32(key.key), UInt32(modifiers), EventHotKeyID(signature: 0x6A6F7474, id: 1),
                GetApplicationEventTarget(), UInt32(kEventHotKeyExclusive), &replacement)
            guard status == noErr else {
                throw StorageError("\(shortcut.display) is unavailable. Choose a different shortcut.")
            }
        }
        
        if let registration {
            UnregisterEventHotKey(registration)
        }
        
        self.registration = replacement
        self.current = shortcut
    }
    
    deinit {
        if let registration {
            UnregisterEventHotKey(registration)
        }
        
        if let handler {
            RemoveEventHandler(handler)
        }
    }
}
