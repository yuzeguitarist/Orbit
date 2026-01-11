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
    case shift

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .option:
            return "⌥"
        case .command:
            return "⌘"
        case .control:
            return "⌃"
        case .shift:
            return "⇧"
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
        case .shift:
            return NSLocalizedString("modifier.shift", comment: "")
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
        case .shift:
            return .maskShift
        }
    }

    func isPressed(in flags: CGEventFlags) -> Bool {
        flags.contains(cgFlag)
    }

    func otherModifiersPressed(in flags: CGEventFlags) -> Bool {
        let isShift = flags.contains(.maskShift)
        let isControl = flags.contains(.maskControl)
        let isOption = flags.contains(.maskAlternate)
        let isCommand = flags.contains(.maskCommand)

        switch self {
        case .option:
            return isShift || isControl || isCommand
        case .command:
            return isShift || isControl || isOption
        case .control:
            return isShift || isOption || isCommand
        case .shift:
            return isControl || isOption || isCommand
        }
    }
}
