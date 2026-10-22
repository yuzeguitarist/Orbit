//
//  TriggerModifier.swift
//  Orbit
//
//  Created by Yuze Pan on 1/7/26.
//

import AppKit

enum TriggerModifier: String, CaseIterable, Identifiable {
    case option
    case command
    case control
    case disabled

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .option:
            return "⌥"
        case .command:
            return "⌘"
        case .control:
            return "⌃"
        case .disabled:
            return "—"
        }
    }

    var localizedName: String {
        switch self {
        case .option:
            return NSLocalizedString("modifier.option", comment: "")
        case .command:
            return NSLocalizedString("modifier.command", comment: "")
        case .control:
            return NSLocalizedString("modifier.control", comment: "")
        case .disabled:
            return NSLocalizedString("modifier.disabled", comment: "")
        }
    }

    var cgFlag: CGEventFlags {
        switch self {
        case .option:
            return .maskAlternate
        case .command:
            return .maskCommand
        case .control:
            return .maskControl
        case .disabled:
            return []
        }
    }

    func isPressed(in flags: CGEventFlags) -> Bool {
        switch self {
        case .disabled:
            return false
        default:
            return flags.contains(cgFlag)
        }
    }

    func otherModifiersPressed(in flags: CGEventFlags) -> Bool {
        if self == .disabled {
            return false
        }
        let isControl = flags.contains(.maskControl)
        let isOption = flags.contains(.maskAlternate)
        let isCommand = flags.contains(.maskCommand)

        switch self {
        case .option:
            return isControl || isCommand
        case .command:
            return isControl || isOption
        case .control:
            return isOption || isCommand
        case .disabled:
            return false
        }
    }
}
