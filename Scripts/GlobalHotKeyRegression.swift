// Run: swift Scripts/GlobalHotKeyRegression.swift /path/to/signed/Orbit.app
// Requires existing Accessibility and event-posting permission; never requests permission.
import AppKit
import ApplicationServices

struct Failure: Error, CustomStringConvertible { let description: String }
func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw Failure(description: message) }
}
func pump(_ seconds: TimeInterval = 0.025) { RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds)) }
func wait(_ message: String, timeout: TimeInterval = 3, _ condition: () -> Bool) throws {
    let deadline = Date(timeIntervalSinceNow: timeout)
    while !condition(), Date() < deadline { pump() }
    try require(condition(), message)
}

let source = CGEventSource(stateID: .privateState)!
var flags: CGEventFlags = []
var pressedKeys: Set<CGKeyCode> = []
var postingTap: CGEventTapLocation = .cghidEventTap
var orbit: NSRunningApplication?
var initialWindowIDs: Set<UInt32> = []
var suite = ""
var passed = 0
var currentCase = "preflight"
let workspace = NSWorkspace.shared
let originalFrontmost = workspace.frontmostApplication
let originalMouse = CGEvent(source: nil)!.location
let originalCalculator = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.calculator").first
var calculator: NSRunningApplication?
let profileDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("OrbitGlobalRegression-\(UUID().uuidString)")

func key(_ code: CGKeyCode, down: Bool, repeating: Bool = false) {
    if down { pressedKeys.insert(code) } else { pressedKeys.remove(code) }
    let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)!
    event.flags = flags
    event.setIntegerValueField(.keyboardEventAutorepeat, value: repeating ? 1 : 0)
    event.post(tap: postingTap)
    pump()
}
func tap(_ code: CGKeyCode) { key(code, down: true); key(code, down: false) }
func modifier(_ code: CGKeyCode, _ flag: CGEventFlags, down: Bool) {
    if down { flags.insert(flag) } else { flags.remove(flag) }
    let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)!
    event.type = .flagsChanged
    event.flags = flags
    event.post(tap: postingTap)
    pump()
}
func moveMouse(_ point: CGPoint) {
    CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)!.post(tap: .cghidEventTap)
}
func windows() -> [[String: Any]] {
    CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
}
func bounds(_ info: [String: Any]) -> CGRect {
    guard let dictionary = info[kCGWindowBounds as String] as? [String: Any] else { return .zero }
    return CGRect(dictionaryRepresentation: dictionary as CFDictionary) ?? .zero
}
func ringVisible() -> Bool {
    guard let orbit else { return false }
    return windows().contains {
        ($0[kCGWindowOwnerPID as String] as? Int) == Int(orbit.processIdentifier)
            && !initialWindowIDs.contains($0[kCGWindowNumber as String] as? UInt32 ?? 0)
            && bounds($0).width > 100 && bounds($0).height > 100
    }
}
func dockOverlays() -> Set<UInt32> {
    Set(windows().compactMap {
        guard ($0[kCGWindowOwnerName as String] as? String) == "Dock", bounds($0).width > 100,
              bounds($0).height > 100 else { return nil }
        return $0[kCGWindowNumber as String] as? UInt32
    })
}
func frontmost(_ bundleID: String) throws {
    try wait("Expected \(bundleID) frontmost, got \(workspace.frontmostApplication?.bundleIdentifier ?? "none")") {
        workspace.frontmostApplication?.bundleIdentifier == bundleID
    }
}
func open(_ url: URL, configuration: NSWorkspace.OpenConfiguration) throws -> NSRunningApplication {
    var result: NSRunningApplication?
    var failure: Error?
    workspace.openApplication(at: url, configuration: configuration) { result = $0; failure = $1 }
    try wait("Failed to launch \(url.path): \(String(describing: failure))", timeout: 10) { result != nil || failure != nil }
    if let failure { throw failure }
    return result!
}
func activate(_ bundleID: String) throws -> NSRunningApplication {
    let app: NSRunningApplication
    if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
        app = running
        app.activate(options: [.activateAllWindows])
    } else {
        guard let url = workspace.urlForApplication(withBundleIdentifier: bundleID) else {
            throw Failure(description: "Cannot locate \(bundleID)")
        }
        app = try open(url, configuration: NSWorkspace.OpenConfiguration())
    }
    try frontmost(bundleID)
    return app
}
func closeOwnedOrbit() {
    postingTap = .cghidEventTap
    if ringVisible() { tap(53) }
    for code in Array(pressedKeys) { key(code, down: false) }
    for (code, flag) in [(CGKeyCode(55), CGEventFlags.maskCommand), (58, .maskAlternate), (59, .maskControl)] where flags.contains(flag) {
        modifier(code, flag, down: false)
    }
    if let orbit {
        orbit.terminate()
        try? wait("Test Orbit did not quit", timeout: 2) { orbit.isTerminated }
        if !orbit.isTerminated { orbit.forceTerminate() }
    }
    orbit = nil
    initialWindowIDs.removeAll()
    if !suite.isEmpty { UserDefaults.standard.removePersistentDomain(forName: suite) }
    suite = ""
}
func runCase(_ name: String, settings: [String: Any] = [:], _ body: () throws -> Void) throws {
    currentCase = name
    suite = "OrbitGlobalRegression.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    var values: [String: Any] = [
        "orbit.triggerModifier": "disabled", "orbit.cmdTabShortcutEnabled": true,
        "orbit.longPressThreshold": 150, "orbit.ringAnimationSpeed": 2.0, "orbit.lockRingToScreenCenter": true,
        "orbit.customShortcut": ["keyCode": 97, "modifiers": 0, "keyLabel": "F6"]
    ]
    values.merge(settings) { _, replacement in replacement }
    defaults.setPersistentDomain(values, forName: suite)
    defaults.synchronize()
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.createsNewApplicationInstance = true
    configuration.environment = ProcessInfo.processInfo.environment.merging([
        "ORBIT_UI_TEST_DEFAULTS_SUITE": suite, "ORBIT_UI_TEST_ENABLE_GLOBAL_HOTKEYS": "1",
        "LLVM_PROFILE_FILE": profileDirectory.appendingPathComponent("\(suite)-%p.profraw").path
    ]) { _, value in value }
    configuration.arguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    orbit = try open(URL(fileURLWithPath: CommandLine.arguments[1]), configuration: configuration)
    defer { closeOwnedOrbit() }
    try wait("Orbit settings window did not appear") {
        windows().contains { ($0[kCGWindowOwnerPID as String] as? Int) == Int(orbit!.processIdentifier) }
    }
    try wait("The Debug app did not load the isolated shortcut preference") {
        guard let element = findElement(AXUIElementCreateApplication(orbit!.processIdentifier), identifier: "settings.trigger.shortcut.value"),
              let value = attribute(element, kAXValueAttribute) as? String else { return false }
        return value == (settings["orbit.customShortcut"] == nil ? "F6" : "⌃⌥K")
    }
    initialWindowIDs = Set(windows().compactMap {
        ($0[kCGWindowOwnerPID as String] as? Int) == Int(orbit!.processIdentifier)
            ? $0[kCGWindowNumber as String] as? UInt32 : nil
    })
    calculator = try activate("com.apple.calculator")
    _ = try activate("com.apple.finder")
    moveMouse(CGPoint(x: 1, y: 1)) // Keep hover selection outside the centered test ring.
    try body()
    passed += 1
    print("PASS \(name)")
}
func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    AXUIElementCopyAttributeValue(element, name as CFString, &value)
    return value
}
func findElement(_ element: AXUIElement, identifier: String) -> AXUIElement? {
    if attribute(element, kAXIdentifierAttribute) as? String == identifier { return element }
    for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
        if let match = findElement(child, identifier: identifier) { return match }
    }
    return nil
}
func clickCalculatorCard() throws {
    var card: AXUIElement?
    try wait("Calculator card has no accessible identifier") { card = findElement(AXUIElementCreateApplication(orbit!.processIdentifier), identifier: "orbit.app.com.apple.calculator"); return card != nil }
    pump(0.6) // The configured animation completes within 0.4 seconds for 12 cards.
    guard let position = attribute(card!, kAXPositionAttribute), let size = attribute(card!, kAXSizeAttribute) else {
        throw Failure(description: "Calculator card has no frame")
    }
    var point = CGPoint.zero
    var dimensions = CGSize.zero
    AXValueGetValue(position as! AXValue, .cgPoint, &point)
    AXValueGetValue(size as! AXValue, .cgSize, &dimensions)
    point.x += dimensions.width / 2; point.y += dimensions.height / 2
    for type in [CGEventType.leftMouseDown, .leftMouseUp] {
        CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)!.post(tap: .cghidEventTap)
        pump()
    }
}

do {
    try require(CommandLine.arguments.count == 2, "Usage: swift Scripts/GlobalHotKeyRegression.swift /path/to/signed/Orbit.app")
    try require(AXIsProcessTrusted() && CGPreflightPostEventAccess(), "Existing Accessibility and event-posting permission are required; no permissions were requested.")
    try require(NSRunningApplication.runningApplications(withBundleIdentifier: "com.yuzeguitar.Orbit").isEmpty, "Quit existing Orbit instances before this isolated regression run.")
    try FileManager.default.createDirectory(at: profileDirectory, withIntermediateDirectories: true)
    defer {
        closeOwnedOrbit()
        if originalCalculator == nil { calculator?.terminate() }
        originalFrontmost?.activate(options: [.activateAllWindows])
        moveMouse(originalMouse)
        try? FileManager.default.removeItem(at: profileDirectory)
    }
    for (name, tapLocation) in [("HID F6 and Escape", CGEventTapLocation.cghidEventTap), ("Session F6 and Escape", .cgSessionEventTap)] {
        try runCase(name) {
            postingTap = tapLocation; tap(97)
            try wait("F6 did not show the actual Orbit panel") { ringVisible() }
            tap(53); try wait("Escape did not close Orbit") { !ringVisible() }
            try frontmost("com.apple.finder")
        }
    }
    try runCase("Cmd+Tab MRU in both directions") {
        for target in ["com.apple.calculator", "com.apple.finder"] {
            modifier(55, .maskCommand, down: true); tap(48)
            try wait("Cmd+Tab was not intercepted by Orbit") { ringVisible() }
            modifier(55, .maskCommand, down: false)
            try wait("Cmd+Tab panel did not close") { !ringVisible() }; try frontmost(target)
        }
    }
    try runCase("Cmd+Tab autorepeat and Escape before release") {
        let before = dockOverlays()
        modifier(55, .maskCommand, down: true); key(48, down: true)
        try wait("Cmd+Tab panel did not appear") { ringVisible() }
        for _ in 0..<8 { key(48, down: true, repeating: true) }
        try require(ringVisible(), "Autorepeat closed Orbit")
        try require(dockOverlays().subtracting(before).isEmpty, "Autorepeat opened a native Dock switcher overlay")
        tap(53); key(48, down: false); modifier(55, .maskCommand, down: false)
        try wait("Cancelled panel stayed visible") { !ringVisible() }; pump(0.2); try frontmost("com.apple.finder")
    }
    try runCase("Custom combination commits on modifier release", settings: ["orbit.customShortcut": ["keyCode": 40, "modifiers": NSEvent.ModifierFlags([.control, .option]).rawValue, "keyLabel": "K"]]) {
        modifier(59, .maskControl, down: true); modifier(58, .maskAlternate, down: true); tap(40)
        try wait("Custom combination did not show Orbit") { ringVisible() }
        tap(124); try require(ringVisible(), "Selection closed before modifier release"); try frontmost("com.yuzeguitar.Orbit")
        modifier(58, .maskAlternate, down: false); modifier(59, .maskControl, down: false)
        try wait("Combination panel stayed visible") { !ringVisible() }; try frontmost("com.apple.calculator")
    }
    try runCase("Option hold preserves current app without selection", settings: ["orbit.triggerModifier": "option"]) {
        modifier(58, .maskAlternate, down: true); try wait("Option hold did not show Orbit") { ringVisible() }
        modifier(58, .maskAlternate, down: false); try wait("Option release did not close Orbit") { !ringVisible() }; try frontmost("com.apple.finder")
    }
    try runCase("Double tap and hold", settings: ["orbit.triggerModifier": "option", "orbit.modifierTriggerMode": "doubleTapAndHold"]) {
        modifier(58, .maskAlternate, down: true); pump(0.5); try require(!ringVisible(), "A single hold invoked double-tap mode")
        modifier(58, .maskAlternate, down: false); pump(0.05)
        modifier(58, .maskAlternate, down: true); modifier(58, .maskAlternate, down: false); pump(0.06); modifier(58, .maskAlternate, down: true)
        try wait("Second held press did not show Orbit") { ringVisible() }
        modifier(58, .maskAlternate, down: false); try wait("Double-tap release did not close Orbit") { !ringVisible() }; try frontmost("com.apple.finder")
    }
    try runCase("Card click and keyboard Enter commit") {
        tap(97); try wait("F6 did not show Orbit for card click") { ringVisible() }; try clickCalculatorCard()
        try wait("Card click did not close Orbit") { !ringVisible() }; try frontmost("com.apple.calculator")
        _ = try activate("com.apple.finder"); moveMouse(CGPoint(x: 1, y: 1)); tap(97)
        try wait("F6 did not show Orbit for Enter") { ringVisible() }; tap(124); tap(36)
        try wait("Enter did not close Orbit") { !ringVisible() }; try frontmost("com.apple.calculator")
    }
    print("PASS \(passed) global hotkey regressions; 0 skipped")
} catch {
    fputs("FAIL \(currentCase): \(error)\n", stderr)
    exit(1)
}
