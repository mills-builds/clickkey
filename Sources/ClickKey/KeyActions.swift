import AppKit
import CoreGraphics

// MARK: - Modifiers

struct KeyModifiers: OptionSet, Codable, Hashable {
    let rawValue: Int

    static let control = KeyModifiers(rawValue: 1 << 0)
    static let option = KeyModifiers(rawValue: 1 << 1)
    static let shift = KeyModifiers(rawValue: 1 << 2)
    static let command = KeyModifiers(rawValue: 1 << 3)

    init(rawValue: Int) { self.rawValue = rawValue }

    init(_ flags: NSEvent.ModifierFlags) {
        var m: KeyModifiers = []
        if flags.contains(.control) { m.insert(.control) }
        if flags.contains(.option) { m.insert(.option) }
        if flags.contains(.shift) { m.insert(.shift) }
        if flags.contains(.command) { m.insert(.command) }
        self = m
    }

    var cgFlags: CGEventFlags {
        var f: CGEventFlags = []
        if contains(.control) { f.insert(.maskControl) }
        if contains(.option) { f.insert(.maskAlternate) }
        if contains(.shift) { f.insert(.maskShift) }
        if contains(.command) { f.insert(.maskCommand) }
        return f
    }

    /// Apple's canonical order: ⌃⌥⇧⌘
    var symbols: String {
        var s = ""
        if contains(.control) { s += "⌃" }
        if contains(.option) { s += "⌥" }
        if contains(.shift) { s += "⇧" }
        if contains(.command) { s += "⌘" }
        return s
    }
}

// MARK: - Media keys

/// NX_KEYTYPE_* codes from IOKit/hidsystem/ev_keymap.h
enum MediaKey: Int, Codable, CaseIterable, Identifiable {
    case playPause = 16
    case next = 17
    case previous = 18
    case volumeUp = 0
    case volumeDown = 1
    case mute = 7

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .playPause: return "Play/Pause"
        case .next: return "Next Track"
        case .previous: return "Previous Track"
        case .volumeUp: return "Volume Up"
        case .volumeDown: return "Volume Down"
        case .mute: return "Mute"
        }
    }

    var systemImage: String {
        switch self {
        case .playPause: return "playpause.fill"
        case .next: return "forward.fill"
        case .previous: return "backward.fill"
        case .volumeUp: return "speaker.wave.3.fill"
        case .volumeDown: return "speaker.wave.1.fill"
        case .mute: return "speaker.slash.fill"
        }
    }
}

// MARK: - Actions

enum KeyAction: Codable, Hashable {
    case key(code: UInt16, modifiers: KeyModifiers)
    case media(MediaKey)

    static let defaultAction = KeyAction.key(code: KeyCode.returnKey, modifiers: [])

    var displayName: String {
        switch self {
        case let .key(code, modifiers): return modifiers.symbols + KeyCode.name(for: code)
        case let .media(key): return key.title
        }
    }

    func perform() {
        switch self {
        case let .key(code, modifiers): KeyPoster.postKey(code: code, flags: modifiers.cgFlags)
        case let .media(key): KeyPoster.postMedia(key)
        }
    }
}

struct ActionPreset: Identifiable {
    let title: String
    let action: KeyAction
    var id: String { title }

    static let keys: [ActionPreset] = [
        ActionPreset(title: "Return", action: .defaultAction),
        ActionPreset(title: "Escape", action: .key(code: KeyCode.escape, modifiers: [])),
        ActionPreset(title: "Tab", action: .key(code: KeyCode.tab, modifiers: [])),
        ActionPreset(title: "Space", action: .key(code: KeyCode.space, modifiers: [])),
        ActionPreset(title: "Delete", action: .key(code: KeyCode.delete, modifiers: [])),
        ActionPreset(title: "Copy  ⌘C", action: .key(code: 8, modifiers: .command)),
        ActionPreset(title: "Paste  ⌘V", action: .key(code: 9, modifiers: .command)),
        ActionPreset(title: "Undo  ⌘Z", action: .key(code: 6, modifiers: .command)),
        ActionPreset(title: "Redo  ⇧⌘Z", action: .key(code: 6, modifiers: [.command, .shift])),
    ]
}

// MARK: - Key codes

enum KeyCode {
    static let returnKey: UInt16 = 36
    static let tab: UInt16 = 48
    static let space: UInt16 = 49
    static let delete: UInt16 = 51
    static let escape: UInt16 = 53

    /// Names for ANSI-layout virtual key codes (kVK_*).
    private static let names: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
        27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
        36: "Return", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
        44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space", 50: "`", 51: "Delete",
        53: "Escape", 76: "Enter", 117: "Forward Delete",
        115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
    ]

    static func name(for code: UInt16) -> String {
        names[code] ?? "Key \(code)"
    }
}

// MARK: - Posting

enum KeyPoster {
    static func postKey(code: UInt16, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: isDown) else { continue }
            if !flags.isEmpty { event.flags = flags }
            event.post(tap: .cghidEventTap)
        }
    }

    /// Media keys are NX_SYSDEFINED events, subtype 8 (NX_SUBTYPE_AUX_CONTROL_BUTTONS).
    static func postMedia(_ key: MediaKey) {
        for state in [0xa, 0xb] { // 0xa = key down, 0xb = key up
            let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: (key.rawValue << 16) | (state << 8),
                data2: -1
            )
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
