import AppKit

/// Input decisions are independent of event taps so release/cancel ordering can be tested.
struct HotKeyState {
    struct Configuration: Equatable {
        var modifier: TriggerModifier
        var mode: ModifierTriggerMode
        var threshold: TimeInterval
        var cmdTabEnabled: Bool
        var customShortcut: TriggerShortcut?

        static var current: Configuration {
            Configuration(modifier: OrbitConfig.triggerModifier, mode: OrbitConfig.modifierTriggerMode,
                          threshold: OrbitConfig.longPressThreshold / 1000,
                          cmdTabEnabled: OrbitConfig.isCmdTabShortcutEnabled, customShortcut: OrbitConfig.customShortcut)
        }
    }

    enum Source: Equatable {
        case modifier(TriggerModifier)
        case cmdTab
        case custom(TriggerShortcut)

        var notificationName: String {
            switch self {
            case .modifier: return "longPress"
            case .cmdTab: return "cmdTab"
            case .custom: return "customShortcut"
            }
        }
    }

    enum Action: Equatable {
        case show(Source)
        case dismiss(activate: Bool)
        case cycle(previous: Bool)
        case scheduleHold(TimeInterval)
        case cancelHold
    }

    private(set) var isVisible = false
    private var activeSource: Source?
    private var configuration: Configuration?
    private var modifierHeld = false
    private var interrupted = false
    private var pressStartedAt: TimeInterval?
    private var firstTapReleasedAt: TimeInterval?
    private var holdIsArmed = false
    private var consumedKeys: Set<UInt16> = []

    var usesShiftAsTrigger: Bool {
        if case .custom(let shortcut) = activeSource {
            return shortcut.modifiers.contains(.shift)
        }
        return false
    }

    mutating func reset() {
        self = HotKeyState()
    }

    mutating func cancel(presentationIsVisible: Bool = false) -> [Action] {
        let wasVisible = isVisible || presentationIsVisible
        isVisible = false
        activeSource = nil
        interrupted = true
        holdIsArmed = false
        firstTapReleasedAt = nil
        return [.cancelHold] + (wasVisible ? [.dismiss(activate: false)] : [])
    }

    mutating func flagsChanged(_ flags: NSEvent.ModifierFlags, at time: TimeInterval, config: Configuration) -> [Action] {
        var actions = updateConfiguration(config)
        if isVisible, let source = activeSource {
            let required: NSEvent.ModifierFlags
            switch source {
            case .modifier(let modifier): required = NSEvent.ModifierFlags(rawValue: UInt(modifier.cgFlag.rawValue))
            case .cmdTab: required = .command
            case .custom(let shortcut): required = shortcut.modifiers
            }
            if !required.isEmpty, !flags.contains(required) {
                isVisible = false
                activeSource = nil
                actions.append(.dismiss(activate: true))
            }
        }

        let triggerFlags = NSEvent.ModifierFlags(rawValue: UInt(config.modifier.cgFlag.rawValue))
        let pressed = config.modifier != .disabled && flags.contains(triggerFlags)
        let others = !flags.intersection(TriggerShortcut.allowedModifierFlags).subtracting(triggerFlags).isEmpty
        if !pressed, others { firstTapReleasedAt = nil }
        if pressed, !modifierHeld {
            modifierHeld = true
            interrupted = others || isVisible
            pressStartedAt = time
            let secondTap = firstTapReleasedAt.map { time - $0 <= 0.35 } ?? false
            firstTapReleasedAt = nil
            if !interrupted, config.mode == .hold || secondTap {
                holdIsArmed = true
                actions.append(.scheduleHold(config.threshold))
            }
        } else if pressed, others, !isVisible {
            interrupted = true
            holdIsArmed = false
            firstTapReleasedAt = nil
            actions.append(.cancelHold)
        } else if !pressed, modifierHeld {
            modifierHeld = false
            holdIsArmed = false
            actions.append(.cancelHold)
            if config.mode == .doubleTapAndHold, !interrupted,
               let start = pressStartedAt, time - start <= 0.35 {
                firstTapReleasedAt = time
            }
            pressStartedAt = nil
            interrupted = false
        }
        return actions
    }

    mutating func keyDown(_ code: UInt16, flags: NSEvent.ModifierFlags, isRepeat: Bool, config: Configuration,
                          presentationIsVisible: Bool = false) -> (consumed: Bool, actions: [Action]) {
        var actions = updateConfiguration(config)
        if code == 53, isVisible || presentationIsVisible {
            consumedKeys.insert(code)
            return (true, actions + cancel(presentationIsVisible: presentationIsVisible))
        }
        let modifiers = flags.intersection(TriggerShortcut.allowedModifierFlags)
        if let shortcut = config.customShortcut, code == shortcut.keyCode, modifiers == shortcut.modifiers {
            consumedKeys.insert(code)
            if !isRepeat {
                if isVisible {
                    if case .custom = activeSource { actions += cancel() }
                    else { activeSource = .custom(shortcut) }
                } else {
                    actions += show(.custom(shortcut))
                }
            }
            return (true, actions)
        }
        if config.cmdTabEnabled, code == 48,
           modifiers == .command || modifiers == [.command, .shift] {
            consumedKeys.insert(code)
            if isVisible {
                activeSource = .cmdTab
                actions.append(.cycle(previous: modifiers.contains(.shift)))
            } else if !isRepeat {
                actions += show(.cmdTab)
                if modifiers.contains(.shift) { actions.append(.cycle(previous: true)) }
            }
            return (true, actions)
        }
        if isRepeat, consumedKeys.contains(code) { return (true, actions) }
        firstTapReleasedAt = nil
        if modifierHeld, !isVisible {
            interrupted = true
            holdIsArmed = false
            actions.append(.cancelHold)
        }
        return (false, actions)
    }

    mutating func keyUp(_ code: UInt16) -> Bool {
        consumedKeys.remove(code) != nil
    }

    mutating func holdElapsed(config: Configuration) -> [Action] {
        guard configuration == config, holdIsArmed, modifierHeld, !interrupted, !isVisible else { return [] }
        holdIsArmed = false
        interrupted = true
        return show(.modifier(config.modifier))
    }

    private mutating func show(_ source: Source) -> [Action] {
        isVisible = true
        activeSource = source
        holdIsArmed = false
        interrupted = true
        firstTapReleasedAt = nil
        return [.cancelHold, .show(source)]
    }

    private mutating func updateConfiguration(_ config: Configuration) -> [Action] {
        guard configuration != config else { return [] }
        configuration = config
        modifierHeld = false
        interrupted = false
        holdIsArmed = false
        pressStartedAt = nil
        firstTapReleasedAt = nil
        return [.cancelHold]
    }
}
