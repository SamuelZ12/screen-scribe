import AppKit
import Carbon
import Combine

/// Actions that can be triggered by keyboard shortcuts
enum ShortcutAction {
    case visionOCR       // Apple Vision offline text extraction
    case defaultPrompt   // AI extraction with the user's default prompt
}

@MainActor
final class ShortcutMonitor: ObservableObject {
    @Published private(set) var registrationErrors: [String] = []
    static let shared = ShortcutMonitor()

    private var textHotKeyRef: EventHotKeyRef?
    private var defaultPromptHotKeyRef: EventHotKeyRef?
    private var textHotKeyID = EventHotKeyID(signature: 0x4C544558, // 'LTEX'
                                            id: 1)
    private var defaultPromptHotKeyID = EventHotKeyID(signature: 0x4C544558,
                                             id: 2)
    private var callback: ((ShortcutAction) -> Void)?
    private var textShortcut: KeyboardShortcut?
    private var defaultPromptShortcut: KeyboardShortcut?
    
    struct KeyboardShortcut: Codable, Sendable {
        var keyCode: Int
        var modifiersRawValue: UInt
        
        var modifiers: NSEvent.ModifierFlags {
            NSEvent.ModifierFlags(rawValue: modifiersRawValue)
        }
        
        var carbonModifiers: UInt32 {
            var carbonMods: UInt32 = 0
            if modifiers.contains(.command) { carbonMods |= UInt32(cmdKey) }
            if modifiers.contains(.shift) { carbonMods |= UInt32(shiftKey) }
            if modifiers.contains(.option) { carbonMods |= UInt32(optionKey) }
            if modifiers.contains(.control) { carbonMods |= UInt32(controlKey) }
            return carbonMods
        }
        
        var description: String {
            var desc = ""
            if modifiers.contains(.command) { desc += "⌘" }
            if modifiers.contains(.shift) { desc += "⇧" }
            if modifiers.contains(.option) { desc += "⌥" }
            if modifiers.contains(.control) { desc += "⌃" }
            
            if let key = keyEquivalentString(for: keyCode) {
                desc += key
            } else {
                desc += keyEquivalentCharacter.uppercased()
            }
            return desc
        }
        
        var keyEquivalentCharacter: String {
            // Convert key code to lowercase string
            switch keyCode {
            case kVK_ANSI_A: return "a"
            case kVK_ANSI_B: return "b"
            case kVK_ANSI_C: return "c"
            case kVK_ANSI_D: return "d"
            case kVK_ANSI_E: return "e"
            case kVK_ANSI_F: return "f"
            case kVK_ANSI_G: return "g"
            case kVK_ANSI_H: return "h"
            case kVK_ANSI_I: return "i"
            case kVK_ANSI_J: return "j"
            case kVK_ANSI_K: return "k"
            case kVK_ANSI_L: return "l"
            case kVK_ANSI_M: return "m"
            case kVK_ANSI_N: return "n"
            case kVK_ANSI_O: return "o"
            case kVK_ANSI_P: return "p"
            case kVK_ANSI_Q: return "q"
            case kVK_ANSI_R: return "r"
            case kVK_ANSI_S: return "s"
            case kVK_ANSI_T: return "t"
            case kVK_ANSI_U: return "u"
            case kVK_ANSI_V: return "v"
            case kVK_ANSI_W: return "w"
            case kVK_ANSI_X: return "x"
            case kVK_ANSI_Y: return "y"
            case kVK_ANSI_Z: return "z"
            case kVK_ANSI_0: return "0"
            case kVK_ANSI_1: return "1"
            case kVK_ANSI_2: return "2"
            case kVK_ANSI_3: return "3"
            case kVK_ANSI_4: return "4"
            case kVK_ANSI_5: return "5"
            case kVK_ANSI_6: return "6"
            case kVK_ANSI_7: return "7"
            case kVK_ANSI_8: return "8"
            case kVK_ANSI_9: return "9"
            case kVK_Return: return "\r"
            case kVK_Tab: return "\t"
            case kVK_Space: return " "
            case kVK_Delete: return "\u{8}"
            case kVK_LeftArrow: return "\u{1C}"
            case kVK_RightArrow: return "\u{1D}"
            case kVK_UpArrow: return "\u{1E}"
            case kVK_DownArrow: return "\u{1F}"
            default: return ""
            }
        }
        
        private func keyEquivalentString(for keyCode: Int) -> String? {
            switch keyCode {
            case kVK_ANSI_A: return "A"
            case kVK_ANSI_S: return "S"
            case kVK_ANSI_D: return "D"
            case kVK_ANSI_F: return "F"
            case kVK_ANSI_H: return "H"
            case kVK_ANSI_G: return "G"
            case kVK_ANSI_Z: return "Z"
            case kVK_ANSI_X: return "X"
            case kVK_ANSI_C: return "C"
            case kVK_ANSI_V: return "V"
            case kVK_ANSI_B: return "B"
            case kVK_ANSI_Q: return "Q"
            case kVK_ANSI_W: return "W"
            case kVK_ANSI_E: return "E"
            case kVK_ANSI_R: return "R"
            case kVK_ANSI_Y: return "Y"
            case kVK_ANSI_T: return "T"
            case kVK_ANSI_1: return "1"
            case kVK_ANSI_2: return "2"
            case kVK_ANSI_3: return "3"
            case kVK_ANSI_4: return "4"
            case kVK_ANSI_6: return "6"
            case kVK_ANSI_5: return "5"
            case kVK_ANSI_9: return "9"
            case kVK_ANSI_7: return "7"
            case kVK_ANSI_8: return "8"
            case kVK_ANSI_0: return "0"
            case kVK_Return: return "⏎"
            case kVK_Space: return "Space"
            default: return nil
            }
        }
        
        init(keyCode: Int, modifiers: NSEvent.ModifierFlags) {
            self.keyCode = keyCode
            self.modifiersRawValue = modifiers.rawValue
        }
        
        enum CodingKeys: String, CodingKey {
            case keyCode
            case modifiersRawValue
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            keyCode = try container.decode(Int.self, forKey: .keyCode)
            modifiersRawValue = try container.decode(UInt.self, forKey: .modifiersRawValue)
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(keyCode, forKey: .keyCode)
            try container.encode(modifiersRawValue, forKey: .modifiersRawValue)
        }
    }
    
    private init() {
        installEventHandler()
    }
    
    private func installEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                    eventKind: UInt32(kEventHotKeyPressed))
        
        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        
        InstallEventHandler(GetApplicationEventTarget(),
                          { (nextHandler, theEvent, userData) -> OSStatus in
            let monitor = Unmanaged<ShortcutMonitor>.fromOpaque(userData!).takeUnretainedValue()
            
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(theEvent,
                                         EventParamName(kEventParamDirectObject),
                                         EventParamType(typeEventHotKeyID),
                                         nil,
                                         MemoryLayout<EventHotKeyID>.size,
                                         nil,
                                         &hotKeyID)
            
            guard status == noErr else { return status }
            
            Task { @MainActor in
                switch hotKeyID.id {
                case 1: monitor.callback?(.visionOCR)
                case 2: monitor.callback?(.defaultPrompt)
                default: break
                }
            }
            
            return noErr
        },
        1,
        &eventType,
        selfPtr,
        nil)
    }
    
    func startMonitoring(callback: @escaping (ShortcutAction) -> Void) {
        self.callback = callback
        registerHotKeys()
    }

    func stopMonitoring() {
        if let ref = textHotKeyRef {
            UnregisterEventHotKey(ref)
            textHotKeyRef = nil
        }
        if let ref = defaultPromptHotKeyRef {
            UnregisterEventHotKey(ref)
            defaultPromptHotKeyRef = nil
        }
    }

    private func registerHotKeys() {
        stopMonitoring()
        registrationErrors = []
        for (shortcut, id, label) in [(textShortcut, textHotKeyID, "离线文字"), (defaultPromptShortcut, defaultPromptHotKeyID, "科研识别")] {
            guard let shortcut else { continue }
            guard shortcut.carbonModifiers != 0, !shortcut.keyEquivalentCharacter.isEmpty else {
                registrationErrors.append("\(label)：请使用带修饰键的字母或数字。"); continue
            }
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(shortcut.keyCode), shortcut.carbonModifiers, id,
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr {
                if id.id == 1 { textHotKeyRef = ref } else { defaultPromptHotKeyRef = ref }
            } else {
                registrationErrors.append("\(label)：快捷键注册失败（\(status)），可能已被占用，请更换组合。")
            }
        }
    }

    func setShortcut(_ shortcut: KeyboardShortcut?, for action: ShortcutAction) {
        switch action {
        case .visionOCR:
            textShortcut = shortcut
        case .defaultPrompt:
            defaultPromptShortcut = shortcut
        }
        registerHotKeys()
    }
}
