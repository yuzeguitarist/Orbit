//
//  HotKeyService.swift
//  Orbit
//
//  Created by Yuze Pan on 1/7/26.
//

import AppKit
import Carbon
import Combine
import Foundation

/// 全局热键监听服务
final class HotKeyService: ObservableObject {
    static let shared = HotKeyService()

    @Published private(set) var shouldShowOrbit = false
    @Published private(set) var mouseLocation: CGPoint = .zero
    @Published private(set) var shouldActivateOnDismiss = false

    private enum TriggerSource {
        case longPress
        case cmdTabShortcut
    }

    enum DismissStyle {
        case immediate
        case animated
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var longPressTimer: DispatchSourceTimer?
    private var isTriggerHeld = false
    private var otherKeyPressed = false
    private var activeTrigger: TriggerSource?
    private var lastInputSource: TISInputSource?
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var shiftToggleIsDown = false
    private var shiftToggleOtherKeyPressed = false

    @Published private(set) var dismissStyle: DismissStyle = .immediate

    private init() {}

    func startListening() {
        guard eventTap == nil else { return }

        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let tapLocations: [CGEventTapLocation] = [.cghidEventTap, .cgSessionEventTap]
        var tap: CFMachPort?
        for location in tapLocations {
            tap = CGEvent.tapCreate(
                tap: location,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: eventMask,
                callback: { (_, type, event, refcon) -> Unmanaged<CGEvent>? in
                    guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                    let service = Unmanaged<HotKeyService>.fromOpaque(refcon).takeUnretainedValue()
                    return service.handleEvent(type: type, event: event)
                },
                userInfo: selfPtr
            )
            if tap != nil {
                break
            }
        }

        guard let tap else {
            print("HotKeyService: Failed to create event tap")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }

        CGEvent.tapEnable(tap: tap, enable: true)

        if globalFlagsMonitor == nil {
            globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
                let flags = CGEventFlags(rawValue: CGEventFlags.RawValue(event.modifierFlags.rawValue))
                _ = self?.handleShiftToggleRequest(keyCode: event.keyCode, flags: flags)
            }
        }

        if localFlagsMonitor == nil {
            localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
                let flags = CGEventFlags(rawValue: CGEventFlags.RawValue(event.modifierFlags.rawValue))
                _ = self?.handleShiftToggleRequest(keyCode: event.keyCode, flags: flags)
                return event
            }
        }

        print("HotKeyService: Started")
    }

    func stopListening() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let monitor = globalFlagsMonitor {
            NSEvent.removeMonitor(monitor)
            globalFlagsMonitor = nil
        }
        if let monitor = localFlagsMonitor {
            NSEvent.removeMonitor(monitor)
            localFlagsMonitor = nil
        }
        eventTap = nil
        runLoopSource = nil
        cancelTimer()
    }

    func notifyOrbitDismissed() {
        DispatchQueue.main.async {
            self.shouldShowOrbit = false
            self.activeTrigger = nil
            self.dismissStyle = .immediate
            self.lastInputSource = nil
            self.shouldActivateOnDismiss = false
            self.shiftToggleIsDown = false
            self.shiftToggleOtherKeyPressed = false
        }
    }

    static func checkAccessibilityPermission() -> Bool {
        // Avoid touching the imported mutable CFString var directly under Swift 6
        // strict concurrency; AX expects the stable string key below.
        let options = ["AXTrustedCheckOptionPrompt": true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .flagsChanged:
            if handleShiftToggle(event: event) {
                return nil
            }
            handleFlagsChanged(event: event)
            return Unmanaged.passUnretained(event)
        case .keyDown:
            return handleKeyDown(event: event) ? nil : Unmanaged.passUnretained(event)
        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleShiftToggle(event: CGEvent) -> Bool {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        return handleShiftToggleRequest(keyCode: keyCode, flags: event.flags)
    }

    func handleShiftToggleRequest(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        guard keyCode == 56 || keyCode == 60 else { return false } // Left/Right Shift
        guard shouldShowOrbit else { return false }

        let isDown = flags.contains(.maskShift)
        if isDown {
            if !shiftToggleIsDown {
                shiftToggleIsDown = true
                shiftToggleOtherKeyPressed = false
            }
        } else {
            if shiftToggleIsDown && !shiftToggleOtherKeyPressed {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("OrbitToggleMode"),
                        object: nil
                    )
                }
            }
            shiftToggleIsDown = false
            shiftToggleOtherKeyPressed = false
        }
        return true
    }

    private func handleFlagsChanged(event: CGEvent) {
        let flags = event.flags
        let triggerModifier = OrbitConfig.triggerModifier
        let triggerPressed = triggerModifier.isPressed(in: flags)
        let otherModifiers = triggerModifier.otherModifiersPressed(in: flags)

        if triggerPressed {
            if !isTriggerHeld {
                isTriggerHeld = true
                otherKeyPressed = false
                if !otherModifiers {
                    startTimer()
                } else {
                    cancelTimer()
                }
            }
        } else {
            if isTriggerHeld {
                isTriggerHeld = false
                cancelTimer()

                if shouldShowOrbit, activeTrigger == .longPress {
                    dismissOrbit(activateSelected: true, style: .animated)
                }
            }
            otherKeyPressed = false
        }

        handleCmdTabShortcutRelease(flags: flags)
    }

    private func handleKeyDown(event: CGEvent) -> Bool {
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            return false
        }
        if shiftToggleIsDown {
            shiftToggleOtherKeyPressed = true
        }
        if handleCmdTabShortcut(event: event) {
            return true
        }
        if isTriggerHeld && !shouldShowOrbit {
            otherKeyPressed = true
            cancelTimer()
        }
        return false
    }

    private func startTimer() {
        cancelTimer()

        let threshold = OrbitConfig.longPressThreshold / 1000.0

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + threshold)
        timer.setEventHandler { [weak self] in
            self?.onLongPress()
        }
        timer.resume()
        longPressTimer = timer
    }

    private func cancelTimer() {
        longPressTimer?.cancel()
        longPressTimer = nil
    }

    private func onLongPress() {
        guard !otherKeyPressed && isTriggerHeld else { return }

        DispatchQueue.main.async {
            self.showOrbit(source: .longPress)
        }
    }

    private func handleCmdTabShortcut(event: CGEvent) -> Bool {
        guard OrbitConfig.isCmdTabShortcutEnabled else { return false }
        let shortcut = OrbitConfig.cmdTabShortcut
        guard let nsEvent = NSEvent(cgEvent: event) else { return false }

        let modifiers = nsEvent.modifierFlags.intersection(TriggerShortcut.allowedModifierFlags)
        guard nsEvent.keyCode == shortcut.keyCode else { return false }

        if shortcut.keyCode == 48,
           shouldShowOrbit,
           activeTrigger == .cmdTabShortcut,
           modifiers.contains(shortcut.modifiers)
        {
            let direction = modifiers.contains(.shift) ? "previous" : "next"
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: NSNotification.Name("OrbitCycleSelection"),
                    object: nil,
                    userInfo: ["direction": direction]
                )
            }
            return true
        }

        guard modifiers == shortcut.modifiers else { return false }

        cancelTimer()
        isTriggerHeld = false
        otherKeyPressed = true

        DispatchQueue.main.async {
            if self.shouldShowOrbit {
                self.dismissOrbit(activateSelected: false)
            } else {
                self.showOrbit(source: .cmdTabShortcut)
            }
        }
        return true
    }

    private func showOrbit(source: TriggerSource) {
        let location = NSEvent.mouseLocation
        mouseLocation = location
        shouldShowOrbit = true
        activeTrigger = source
        captureInputSource()

        let triggerName: String
        switch source {
        case .longPress:
            triggerName = "longPress"
        case .cmdTabShortcut:
            triggerName = "cmdTab"
        }

        NotificationCenter.default.post(
            name: NSNotification.Name("OrbitShouldShow"),
            object: nil,
            userInfo: ["show": true, "location": location, "trigger": triggerName]
        )
    }

    private func dismissOrbit(activateSelected: Bool, style: DismissStyle = .immediate) {
        DispatchQueue.main.async {
            self.dismissStyle = style
            self.shouldShowOrbit = false
            self.activeTrigger = nil
            self.shouldActivateOnDismiss = activateSelected

            NotificationCenter.default.post(
                name: NSNotification.Name("OrbitShouldShow"),
                object: nil,
                userInfo: [
                    "show": false,
                    "activate": activateSelected,
                    "dismissStyle": style == .animated ? "animated" : "immediate"
                ]
            )
        }
    }

    private func handleCmdTabShortcutRelease(flags: CGEventFlags) {
        guard shouldShowOrbit, activeTrigger == .cmdTabShortcut else { return }
        let shortcut = OrbitConfig.cmdTabShortcut
        guard shortcut.keyCode == 48 else { return }
        guard areRequiredModifiersPressed(shortcut.modifiers, in: flags) else {
            dismissOrbit(activateSelected: true, style: .animated)
            return
        }
    }

    private func areRequiredModifiersPressed(_ modifiers: NSEvent.ModifierFlags, in flags: CGEventFlags) -> Bool {
        if modifiers.contains(.command), !flags.contains(.maskCommand) { return false }
        if modifiers.contains(.option), !flags.contains(.maskAlternate) { return false }
        if modifiers.contains(.control), !flags.contains(.maskControl) { return false }
        if modifiers.contains(.shift), !flags.contains(.maskShift) { return false }
        return true
    }

    private func captureInputSource() {
        guard lastInputSource == nil else { return }
        lastInputSource = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    }

    private func restoreInputSourceIfNeeded() {
        guard let source = lastInputSource else { return }
        TISSelectInputSource(source)
    }

    private func restoreInputSourceIfNeeded(after delay: TimeInterval) {
        guard lastInputSource != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.restoreInputSourceIfNeeded()
        }
    }
}
