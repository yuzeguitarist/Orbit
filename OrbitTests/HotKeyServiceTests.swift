import AppKit
import Testing
@testable import Orbit

@MainActor
struct HotKeyServiceTests {
    private func configuration(
        modifier: TriggerModifier = .option,
        mode: ModifierTriggerMode = .hold,
        cmdTabEnabled: Bool = true,
        customShortcut: TriggerShortcut? = nil
    ) -> HotKeyState.Configuration {
        .init(modifier: modifier, mode: mode, threshold: 0.15,
              cmdTabEnabled: cmdTabEnabled, customShortcut: customShortcut)
    }

    @Test func escapeCancelsBeforeModifierRelease() {
        var state = HotKeyState()
        let config = configuration()
        let show = state.keyDown(48, flags: .command, isRepeat: false, config: config)
        #expect(show.consumed)
        #expect(show.actions.contains(.show(.cmdTab)))
        let cancel = state.keyDown(53, flags: .command, isRepeat: false, config: config)
        #expect(cancel.consumed)
        #expect(cancel.actions.contains(.dismiss(activate: false)))
        #expect(!state.isVisible)
        #expect(!state.flagsChanged([], at: 1, config: config).contains(.dismiss(activate: true)))
        let escapeKeyUpConsumed = state.keyUp(53)
        #expect(escapeKeyUpConsumed)
    }

    @Test func escapeOwnsBothEventsWhileAnAsynchronousCommitIsPending() {
        var state = HotKeyState()
        let config = configuration()
        _ = state.keyDown(48, flags: .command, isRepeat: false, config: config)
        _ = state.flagsChanged([], at: 1, config: config)
        #expect(!state.isVisible)
        let escape = state.keyDown(53, flags: [], isRepeat: false, config: config, presentationIsVisible: true)
        #expect(escape.consumed)
        #expect(escape.actions.contains(.dismiss(activate: false)))
        let keyUpConsumed = state.keyUp(53)
        #expect(keyUpConsumed)
    }

    @Test func cmdTabRepeatStaysOwnedByOrbit() {
        var state = HotKeyState()
        let config = configuration()
        _ = state.keyDown(48, flags: .command, isRepeat: false, config: config)
        let repeatEvent = state.keyDown(48, flags: .command, isRepeat: true, config: config)
        #expect(repeatEvent.consumed)
        #expect(repeatEvent.actions.contains(.cycle(previous: false)))
        #expect(state.keyDown(48, flags: [.command, .shift], isRepeat: false, config: config)
            .actions.contains(.cycle(previous: true)))
        #expect(state.flagsChanged([], at: 1, config: config).contains(.dismiss(activate: true)))
        let tabKeyUpConsumed = state.keyUp(48)
        #expect(tabKeyUpConsumed)
    }

    @Test func repeatAfterEscapeCannotReopenOrReachSystemSwitcher() {
        var state = HotKeyState()
        let config = configuration()
        _ = state.keyDown(48, flags: .command, isRepeat: false, config: config)
        _ = state.keyDown(53, flags: .command, isRepeat: false, config: config)
        let repeated = state.keyDown(48, flags: .command, isRepeat: true, config: config)
        #expect(repeated.consumed)
        #expect(!state.isVisible)
        #expect(!repeated.actions.contains(.show(.cmdTab)))
    }

    @Test func cmdTabDisabledLeavesSystemShortcutUntouched() {
        var state = HotKeyState()
        let result = state.keyDown(48, flags: .command, isRepeat: false,
                                   config: configuration(cmdTabEnabled: false))
        #expect(!result.consumed)
        #expect(!state.isVisible)
    }

    @Test func quickModifierReleaseInvalidatesPendingHold() {
        var state = HotKeyState()
        let config = configuration()
        #expect(state.flagsChanged(.option, at: 0, config: config).contains(.scheduleHold(0.15)))
        #expect(state.flagsChanged([], at: 0.05, config: config).contains(.cancelHold))
        #expect(state.holdElapsed(config: config).isEmpty)
        #expect(!state.isVisible)
    }

    @Test func typingOrAnotherModifierCancelsHoldUntilRelease() {
        var state = HotKeyState()
        let config = configuration()
        _ = state.flagsChanged(.option, at: 0, config: config)
        _ = state.keyDown(0, flags: .option, isRepeat: false, config: config)
        #expect(state.holdElapsed(config: config).isEmpty)
        _ = state.flagsChanged([], at: 0.1, config: config)
        _ = state.flagsChanged(.option, at: 0.2, config: config)
        #expect(state.flagsChanged([.option, .shift], at: 0.25, config: config).contains(.cancelHold))
        #expect(state.holdElapsed(config: config).isEmpty)
        _ = state.flagsChanged(.option, at: 0.3, config: config)
        #expect(state.holdElapsed(config: config).isEmpty)
    }

    @Test func longPressCommitsOnceOnReleaseAndEscapePreventsCommit() {
        var state = HotKeyState()
        let config = configuration()
        _ = state.flagsChanged(.option, at: 0, config: config)
        #expect(state.holdElapsed(config: config).contains(.show(.modifier(.option))))
        #expect(state.holdElapsed(config: config).isEmpty)
        #expect(state.flagsChanged([], at: 1, config: config).contains(.dismiss(activate: true)))
        #expect(!state.flagsChanged([], at: 1.1, config: config).contains(.dismiss(activate: true)))

        _ = state.flagsChanged(.option, at: 2, config: config)
        _ = state.holdElapsed(config: config)
        _ = state.keyDown(53, flags: .option, isRepeat: false, config: config)
        #expect(!state.flagsChanged([], at: 3, config: config).contains(.dismiss(activate: true)))
    }

    @Test func doubleTapRequiresSecondPressWithinInterval() {
        var state = HotKeyState()
        let config = configuration(mode: .doubleTapAndHold)
        #expect(!state.flagsChanged(.option, at: 0, config: config).contains(.scheduleHold(0.15)))
        #expect(state.holdElapsed(config: config).isEmpty)
        _ = state.flagsChanged([], at: 0.05, config: config)
        #expect(state.flagsChanged(.option, at: 0.2, config: config).contains(.scheduleHold(0.15)))
        #expect(state.holdElapsed(config: config).contains(.show(.modifier(.option))))

        state.reset()
        _ = state.flagsChanged(.option, at: 0, config: config)
        _ = state.flagsChanged([], at: 0.05, config: config)
        #expect(!state.flagsChanged(.option, at: 0.5, config: config).contains(.scheduleHold(0.15)))
    }

    @Test func interveningTypingInvalidatesDoubleTap() {
        var state = HotKeyState()
        let config = configuration(mode: .doubleTapAndHold)
        _ = state.flagsChanged(.option, at: 0, config: config)
        _ = state.flagsChanged([], at: 0.05, config: config)
        _ = state.keyDown(0, flags: [], isRepeat: false, config: config)
        #expect(!state.flagsChanged(.option, at: 0.2, config: config).contains(.scheduleHold(0.15)))
    }

    @Test func interveningModifierInvalidatesDoubleTap() {
        var state = HotKeyState()
        let config = configuration(mode: .doubleTapAndHold)
        _ = state.flagsChanged(.option, at: 0, config: config)
        _ = state.flagsChanged([], at: 0.05, config: config)
        _ = state.flagsChanged(.command, at: 0.1, config: config)
        _ = state.flagsChanged([], at: 0.15, config: config)
        #expect(!state.flagsChanged(.option, at: 0.2, config: config).contains(.scheduleHold(0.15)))
    }

    @Test func disabledModifierNeverArmsHold() {
        var state = HotKeyState()
        let config = configuration(modifier: .disabled)
        #expect(!state.flagsChanged(.option, at: 0, config: config).contains(.scheduleHold(0.15)))
        #expect(state.holdElapsed(config: config).isEmpty)
    }

    @Test func customCombinationUsesExactModifiersAndCommitsOnRequiredRelease() {
        var state = HotKeyState()
        let shortcut = TriggerShortcut(keyCode: 49, modifiers: [.control, .shift], keyLabel: "Space")
        let config = configuration(customShortcut: shortcut)
        #expect(!state.keyDown(49, flags: [.control, .option, .shift], isRepeat: false, config: config).consumed)
        let result = state.keyDown(49, flags: [.control, .shift], isRepeat: false, config: config)
        #expect(result.actions.contains(.show(.custom(shortcut))))
        #expect(state.usesShiftAsTrigger)
        #expect(!state.flagsChanged([.control, .shift], at: 0, config: config).contains(.dismiss(activate: true)))
        #expect(state.flagsChanged(.control, at: 1, config: config).contains(.dismiss(activate: true)))
    }

    @Test func standaloneFunctionKeyStaysOpenUntilExplicitDismissal() {
        var state = HotKeyState()
        let shortcut = TriggerShortcut(keyCode: 97, modifiers: [], keyLabel: "F6")
        let config = configuration(customShortcut: shortcut)
        _ = state.keyDown(97, flags: [], isRepeat: false, config: config)
        let functionKeyUpConsumed = state.keyUp(97)
        #expect(functionKeyUpConsumed)
        #expect(!state.flagsChanged([], at: 1, config: config).contains(.dismiss(activate: true)))
        #expect(state.isVisible)
        #expect(state.keyDown(97, flags: [], isRepeat: false, config: config).actions.contains(.dismiss(activate: false)))
    }

    @Test func configurationChangeInvalidatesOldTimer() {
        var state = HotKeyState()
        let initial = configuration()
        _ = state.flagsChanged(.option, at: 0, config: initial)
        let changed = configuration(modifier: .control)
        #expect(state.holdElapsed(config: changed).isEmpty)
        #expect(state.flagsChanged(.control, at: 1, config: changed).contains(.scheduleHold(0.15)))
        #expect(state.holdElapsed(config: changed).contains(.show(.modifier(.control))))
    }

    @Test func shortcutValidationKeepsBareTypingAndEscapeAvailable() {
        #expect(!TriggerShortcut(keyCode: 0, modifiers: [], keyLabel: "A").isValidCustomShortcut)
        #expect(!TriggerShortcut(keyCode: 0, modifiers: .shift, keyLabel: "A").isValidCustomShortcut)
        #expect(!TriggerShortcut(keyCode: 53, modifiers: .command, keyLabel: "Esc").isValidCustomShortcut)
        #expect(!TriggerShortcut(keyCode: 55, modifiers: .command, keyLabel: "Command").isValidCustomShortcut)
        #expect(TriggerShortcut(keyCode: 49, modifiers: [.control, .option], keyLabel: "Space").isValidCustomShortcut)
        #expect(TriggerShortcut(keyCode: 97, modifiers: [], keyLabel: "F6").isValidCustomShortcut)
    }
}
