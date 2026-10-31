import AppKit

enum ModifierTriggerMode: String, CaseIterable, Identifiable {
    case hold
    case doubleTapAndHold

    var id: String { rawValue }

    var localizedName: String {
        NSLocalizedString("triggerMode.\(rawValue)", comment: "")
    }
}

extension OrbitConfig {
    static var modifierTriggerMode: ModifierTriggerMode {
        get {
            ModifierTriggerMode(rawValue: defaults.string(forKey: "orbit.modifierTriggerMode") ?? "") ?? .hold
        }
        set {
            defaults.set(newValue.rawValue, forKey: "orbit.modifierTriggerMode")
        }
    }

    static var customShortcut: TriggerShortcut? {
        get {
            guard let stored = defaults.dictionary(forKey: "orbit.customShortcut"),
                  let keyCode = stored["keyCode"] as? Int,
                  let modifiers = stored["modifiers"] as? UInt,
                  let keyLabel = stored["keyLabel"] as? String,
                  let code = UInt16(exactly: keyCode) else { return nil }
            let shortcut = TriggerShortcut(keyCode: code, modifiers: NSEvent.ModifierFlags(rawValue: modifiers), keyLabel: keyLabel)
            return shortcut.isValidCustomShortcut ? shortcut : nil
        }
        set {
            guard let newValue, newValue.isValidCustomShortcut else {
                defaults.removeObject(forKey: "orbit.customShortcut")
                return
            }
            defaults.set([
                "keyCode": Int(newValue.keyCode),
                "modifiers": newValue.modifiers.rawValue,
                "keyLabel": newValue.keyLabel
            ], forKey: "orbit.customShortcut")
        }
    }
}

extension TriggerShortcut {
    var isValidCustomShortcut: Bool {
        guard keyCode != 53, ![54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(keyCode) else { return false }
        let functionKeys: Set<UInt16> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90]
        return !modifiers.intersection([.command, .control, .option]).isEmpty || functionKeys.contains(keyCode)
    }
}
