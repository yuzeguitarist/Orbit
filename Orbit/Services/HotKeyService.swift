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

/// 全局热键监听服务。事件和计时器都在主线程处理，避免取消后又触发切换。
final class HotKeyService: ObservableObject {
    static let shared = HotKeyService()

    @Published private(set) var shouldShowOrbit = false
    @Published private(set) var mouseLocation: CGPoint = .zero
    @Published private(set) var shouldActivateOnDismiss = false

    enum DismissStyle {
        case immediate
        case animated
    }

    @Published private(set) var dismissStyle: DismissStyle = .immediate

    private(set) var isRecordingShortcut = false
    private var shortcutRecordingHandler: ((NSEvent) -> Void)?
    private var recordingConsumedKeys: Set<UInt16> = []

    private var state = HotKeyState()
    private var presentationVisible = false
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var longPressTimer: DispatchWorkItem?
    private var timerGeneration = UUID()
    private var lastInputSource: TISInputSource?
    private var shiftToggleIsDown = false
    private var shiftToggleOtherKeyPressed = false

    private init() {}

    func startListening() {
        guard eventTap == nil else { return }
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        var tap: CFMachPort?
        // 会话入口同时接收硬件和远程控制事件，也能处理手势工具发送的快捷键。
        for location in [CGEventTapLocation.cgSessionEventTap, .cghidEventTap] {
            tap = CGEvent.tapCreate(
                tap: location, place: .headInsertEventTap, options: .defaultTap,
                eventsOfInterest: eventMask,
                callback: { (_, type, event, refcon) -> Unmanaged<CGEvent>? in
                    guard let refcon else { return Unmanaged.passUnretained(event) }
                    return Unmanaged<HotKeyService>.fromOpaque(refcon).takeUnretainedValue().handleEvent(type: type, event: event)
                }, userInfo: selfPtr
            )
            if tap != nil { break }
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
        print("HotKeyService: Started")
    }

    func stopListening() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        eventTap = nil
        runLoopSource = nil
        cancelTimer()
        state.reset()
    }

    /// Must be synchronous: a queued modifier release must not commit a cancelled selection.
    func notifyOrbitDismissed() {
        _ = state.cancel()
        cancelTimer()
        presentationVisible = false
        shouldShowOrbit = false
        shouldActivateOnDismiss = false
        dismissStyle = .immediate
        lastInputSource = nil
        shiftToggleIsDown = false
        shiftToggleOtherKeyPressed = false
    }

    func cancelOrbit() {
        perform(state.cancel(presentationIsVisible: presentationVisible))
    }

    func startRecordingShortcut(_ handler: @escaping (NSEvent) -> Void) {
        cancelOrbit()
        state.reset()
        shortcutRecordingHandler = handler
        isRecordingShortcut = true
    }

    func stopRecordingShortcut() {
        isRecordingShortcut = false
        shortcutRecordingHandler = nil
    }

    static func checkAccessibilityPermission() -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["ORBIT_UI_TEST_DEFAULTS_SUITE"] != nil {
            guard ProcessInfo.processInfo.environment["ORBIT_UI_TEST_ENABLE_GLOBAL_HOTKEYS"] == "1" else { return false }
            return AXIsProcessTrusted()
        }
        #endif
        let options = ["AXTrustedCheckOptionPrompt": true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        if type == .keyUp, recordingConsumedKeys.remove(keyCode) != nil { return nil }
        if type == .keyDown, recordingConsumedKeys.contains(keyCode) { return nil }
        if isRecordingShortcut {
            if type == .keyDown {
                recordingConsumedKeys.insert(keyCode)
                if event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
                   let recordingEvent = NSEvent(cgEvent: event) {
                    shortcutRecordingHandler?(recordingEvent)
                }
                return nil
            }
            return Unmanaged.passUnretained(event)
        }
        let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
        switch type {
        case .flagsChanged:
            perform(state.flagsChanged(flags, at: ProcessInfo.processInfo.systemUptime, config: .current))
            if handleShiftToggleRequest(keyCode: keyCode, flags: event.flags) { return nil }
        case .keyDown:
            if shiftToggleIsDown { shiftToggleOtherKeyPressed = true }
            let result = state.keyDown(keyCode, flags: flags,
                                       isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                                       config: .current, presentationIsVisible: presentationVisible)
            perform(result.actions)
            if result.consumed { return nil }
        case .keyUp:
            if state.keyUp(keyCode) { return nil }
        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }

    func handleShiftToggleRequest(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        guard !isRecordingShortcut, keyCode == 56 || keyCode == 60, shouldShowOrbit else { return false }
        // Shift can be part of a custom trigger, in which case it is not a mode toggle.
        if state.usesShiftAsTrigger { return false }
        if flags.contains(.maskShift) {
            if !shiftToggleIsDown {
                shiftToggleIsDown = true
                shiftToggleOtherKeyPressed = false
            }
        } else {
            if shiftToggleIsDown && !shiftToggleOtherKeyPressed {
                NotificationCenter.default.post(name: NSNotification.Name("OrbitToggleMode"), object: nil)
            }
            shiftToggleIsDown = false
            shiftToggleOtherKeyPressed = false
        }
        return true
    }

    private func perform(_ actions: [HotKeyState.Action]) {
        for action in actions {
            switch action {
            case .scheduleHold(let threshold):
                cancelTimer()
                let generation = timerGeneration
                let work = DispatchWorkItem { [weak self] in
                    guard let self, self.timerGeneration == generation, !self.isRecordingShortcut else { return }
                    self.perform(self.state.holdElapsed(config: .current))
                }
                longPressTimer = work
                DispatchQueue.main.asyncAfter(deadline: .now() + threshold, execute: work)
            case .cancelHold:
                cancelTimer()
            case .show(let source):
                captureInputSource()
                mouseLocation = NSEvent.mouseLocation
                presentationVisible = true
                shouldShowOrbit = true
                shouldActivateOnDismiss = false
                shiftToggleIsDown = false
                shiftToggleOtherKeyPressed = false
                NotificationCenter.default.post(
                    name: NSNotification.Name("OrbitShouldShow"), object: nil,
                    userInfo: ["show": true, "location": mouseLocation, "trigger": source.notificationName]
                )
            case .dismiss(let activate):
                shouldShowOrbit = false
                shouldActivateOnDismiss = activate
                dismissStyle = activate ? .animated : .immediate
                NotificationCenter.default.post(
                    name: NSNotification.Name("OrbitShouldShow"), object: nil,
                    userInfo: ["show": false, "activate": activate,
                               "dismissStyle": activate ? "animated" : "immediate"]
                )
            case .cycle(let previous):
                NotificationCenter.default.post(
                    name: NSNotification.Name("OrbitCycleSelection"), object: nil,
                    userInfo: ["direction": previous ? "previous" : "next"]
                )
            }
        }
    }

    private func cancelTimer() {
        timerGeneration = UUID()
        longPressTimer?.cancel()
        longPressTimer = nil
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
