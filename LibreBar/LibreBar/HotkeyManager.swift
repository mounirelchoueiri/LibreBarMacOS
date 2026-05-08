import Carbon
import AppKit
import Combine

class HotkeyManager {
    static let shared = HotkeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    var onTrigger: (() -> Void)?

    @UserDefault(key: "hotkey_keycode", defaultValue: -1) var keyCode: Int
    @UserDefault(key: "hotkey_modifiers", defaultValue: 0) var modifiers: Int

    var isSet: Bool { keyCode >= 0 }

    var displayString: String {
        guard isSet else { return "None" }
        var parts: [String] = []
        let mods = modifiers
        if mods & NSEvent.ModifierFlags.control.rawIntValue != 0 { parts.append("⌃") }
        if mods & NSEvent.ModifierFlags.option.rawIntValue != 0 { parts.append("⌥") }
        if mods & NSEvent.ModifierFlags.shift.rawIntValue != 0 { parts.append("⇧") }
        if mods & NSEvent.ModifierFlags.command.rawIntValue != 0 { parts.append("⌘") }
        parts.append(keyName(for: UInt16(keyCode)))
        return parts.joined()
    }

    func register() {
        unregister()
        guard isSet else { return }

        var carbonMods: UInt32 = 0
        let mods = modifiers
        if mods & NSEvent.ModifierFlags.command.rawIntValue != 0 { carbonMods |= UInt32(cmdKey) }
        if mods & NSEvent.ModifierFlags.option.rawIntValue != 0 { carbonMods |= UInt32(optionKey) }
        if mods & NSEvent.ModifierFlags.control.rawIntValue != 0 { carbonMods |= UInt32(controlKey) }
        if mods & NSEvent.ModifierFlags.shift.rawIntValue != 0 { carbonMods |= UInt32(shiftKey) }

        let hotKeyID = EventHotKeyID(signature: OSType(0x4C425F48), id: 1) // "LB_H"

        var handlerRef: EventHandlerRef?
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let status = InstallEventHandler(GetApplicationEventTarget(), { (_, event, _) -> OSStatus in
            HotkeyManager.shared.onTrigger?()
            return noErr
        }, 1, &eventType, nil, &handlerRef)

        guard status == noErr else { return }
        self.eventHandler = handlerRef

        var keyRef: EventHotKeyRef?
        RegisterEventHotKey(UInt32(keyCode), carbonMods, hotKeyID, GetApplicationEventTarget(), 0, &keyRef)
        self.hotKeyRef = keyRef
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }

    func set(keyCode: Int, modifiers: Int) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        register()
    }

    func clear() {
        unregister()
        self.keyCode = -1
        self.modifiers = 0
    }

    private func keyName(for keyCode: UInt16) -> String {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let layoutDataRef = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return "?"
        }
        let layoutData = unsafeBitCast(layoutDataRef, to: CFData.self) as Data
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0

        layoutData.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return }
            UCKeyTranslate(base, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                          UInt32(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, 4, &length, &chars)
        }

        if length > 0 {
            return String(utf16CodeUnits: chars, count: length).uppercased()
        }
        return "?"
    }
}

extension NSEvent.ModifierFlags {
    var rawIntValue: Int { Int(rawValue) }
}

@propertyWrapper
struct UserDefault<T> {
    let key: String
    let defaultValue: T

    var wrappedValue: T {
        get { UserDefaults.standard.object(forKey: key) as? T ?? defaultValue }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
