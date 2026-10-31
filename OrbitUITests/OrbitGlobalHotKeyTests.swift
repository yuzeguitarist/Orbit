import AppKit
import XCTest

/// These tests send keys from other applications through the real Accessibility event tap.
/// When invoking xcodebuild, opt in with TEST_RUNNER_ORBIT_RUN_GLOBAL_HOTKEY_TESTS=1.
/// Xcode removes TEST_RUNNER_ when forwarding this as ORBIT_RUN_GLOBAL_HOTKEY_TESTS to the runner.
/// Use a signed Debug build of Orbit with its trusted identity.
final class OrbitGlobalHotKeyTests: XCTestCase {
    private var app: XCUIApplication!
    private var defaultsSuite = ""
    private var calculatorStartedByTest = false
    private var originalFrontmostApp: NSRunningApplication?

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard ProcessInfo.processInfo.environment["ORBIT_RUN_GLOBAL_HOTKEY_TESTS"] == "1" else {
            throw XCTSkip("Opt in to real global hotkey tests on a Mac where the signed Orbit app has Accessibility permission.")
        }
        defaultsSuite = "OrbitGlobalUITests.\(UUID().uuidString)"
        originalFrontmostApp = NSWorkspace.shared.frontmostApplication
        app = XCUIApplication()
        app.launchEnvironment["ORBIT_UI_TEST_DEFAULTS_SUITE"] = defaultsSuite
        app.launchEnvironment["ORBIT_UI_TEST_ENABLE_GLOBAL_HOTKEYS"] = "1"
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }

    override func tearDownWithError() throws {
        if let app, app.state != .notRunning, testRun?.hasSucceeded == false {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "Global hotkey failure accessibility tree"
            tree.lifetime = .keepAlways
            add(tree)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Global hotkey failure window"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        app?.terminate()
        if calculatorStartedByTest {
            XCUIApplication(bundleIdentifier: "com.apple.calculator").terminate()
        }
        if !defaultsSuite.isEmpty {
            UserDefaults(suiteName: defaultsSuite)?.removePersistentDomain(forName: defaultsSuite)
        }
        if let originalFrontmostApp, !originalFrontmostApp.isTerminated {
            originalFrontmostApp.activate(options: [])
        }
    }

    @MainActor
    func testFunctionKeyEscapeClickAndEnterFromAnotherApplication() {
        requireRealAccessibilityPermission()
        recordShortcut(.F6, display: "F6")
        let finder = prepareFinderAfterCalculator()

        finder.typeKey(.F6, modifierFlags: [])
        XCTAssertTrue(ring.waitForExistence(timeout: 5), "F6 must reach Orbit through the global event tap.")
        attachRing(named: "F6 invoked from Finder")
        ring.typeKey(.escape, modifierFlags: .command)
        assertRingClosed()
        assertFrontmost("com.apple.finder")

        finder.typeKey(.F6, modifierFlags: [])
        XCTAssertTrue(ring.waitForExistence(timeout: 5))
        let calculatorCard = ring.descendants(matching: .any)["orbit.app.com.apple.calculator"]
        XCTAssertTrue(calculatorCard.waitForExistence(timeout: 5))
        calculatorCard.click()
        assertRingClosed()
        assertFrontmost("com.apple.calculator")

        finder.activate()
        assertFrontmost("com.apple.finder")
        finder.typeKey(.F6, modifierFlags: [])
        XCTAssertTrue(ring.waitForExistence(timeout: 5))
        ring.typeKey(.rightArrow, modifierFlags: [])
        ring.typeKey(.return, modifierFlags: [])
        assertRingClosed()
        assertFrontmost("com.apple.calculator")
    }

    @MainActor
    func testCmdTabAlternatesTheTwoMostRecentApplications() {
        requireRealAccessibilityPermission()
        let finder = prepareFinderAfterCalculator()

        XCUIElement.perform(withKeyModifiers: .command) {
            finder.typeKey(.tab, modifierFlags: .command)
            XCTAssertTrue(ring.waitForExistence(timeout: 5), "Orbit must intercept Cmd+Tab before Command is released.")
        }
        assertRingClosed()
        assertFrontmost("com.apple.calculator")

        let calculator = XCUIApplication(bundleIdentifier: "com.apple.calculator")
        XCUIElement.perform(withKeyModifiers: .command) {
            calculator.typeKey(.tab, modifierFlags: .command)
            XCTAssertTrue(ring.waitForExistence(timeout: 5), "The reverse switch must also use Orbit's panel.")
        }
        assertRingClosed()
        assertFrontmost("com.apple.finder")
    }

    @MainActor
    func testEscapeWhileCommandIsHeldCannotCommitOnRelease() {
        requireRealAccessibilityPermission()
        let finder = prepareFinderAfterCalculator()

        XCUIElement.perform(withKeyModifiers: .command) {
            finder.typeKey(.tab, modifierFlags: .command)
            XCTAssertTrue(ring.waitForExistence(timeout: 5))
            ring.typeKey(.tab, modifierFlags: .command)
            XCTAssertTrue(ring.exists)
            ring.typeKey(.escape, modifierFlags: .command)
            assertRingClosed()
        }

        assertFrontmost("com.apple.finder")
        XCTAssertFalse(ring.exists, "Releasing Command after Escape must not reopen or commit the ring.")
    }

    @MainActor
    func testCustomCombinationCommitsOnlyWhenItsModifierIsReleased() {
        requireRealAccessibilityPermission()
        selectTriggerModifier("Disabled")
        recordShortcut(XCUIKeyboardKey(rawValue: "k"), modifiers: [.control, .option], display: "⌃⌥K")
        let finder = prepareFinderAfterCalculator()

        XCUIElement.perform(withKeyModifiers: [.control, .option]) {
            finder.typeKey("k", modifierFlags: [.control, .option])
            XCTAssertTrue(ring.waitForExistence(timeout: 5))
            ring.typeKey(.rightArrow, modifierFlags: [.control, .option])
            XCTAssertTrue(ring.exists, "Selection must stay open while both trigger modifiers remain held.")
            assertFrontmost("com.yuzeguitar.Orbit")
        }

        assertRingClosed()
        assertFrontmost("com.apple.calculator")
    }

    @MainActor
    func testHoldingOptionShowsTheRingAndReleasingWithoutSelectionStaysInFinder() {
        requireRealAccessibilityPermission()
        let finder = prepareFinderAfterCalculator()

        XCUIElement.perform(withKeyModifiers: .option) {
            XCTAssertTrue(ring.waitForExistence(timeout: 5), "Holding the configured modifier must invoke the actual panel.")
            attachRing(named: "Option held")
        }

        assertRingClosed()
        assertFrontmost("com.apple.finder")
        XCTAssertTrue(finder.exists)
    }

    @MainActor
    func testDoubleTapAndHoldRequiresASecondPress() {
        requireRealAccessibilityPermission()
        let gesture = app.popUpButtons["settings.trigger.mode"]
        gesture.click()
        app.menuItems["Double-tap and hold"].click()
        let finder = prepareFinderAfterCalculator()

        XCUIElement.perform(withKeyModifiers: .option) {
            XCTAssertFalse(ring.waitForExistence(timeout: 0.6), "A single held press must not invoke double-tap mode.")
        }

        finder.typeKey(.option, modifierFlags: [])
        XCUIElement.perform(withKeyModifiers: .option) {
            XCTAssertTrue(ring.waitForExistence(timeout: 5), "The second held press within the double-tap interval must invoke Orbit.")
            attachRing(named: "Double tap and hold")
        }

        assertRingClosed()
        assertFrontmost("com.apple.finder")
    }

    @MainActor
    private var ring: XCUIElement {
        app.windows["orbit.ring"]
    }

    @MainActor
    private func requireRealAccessibilityPermission(file: StaticString = #filePath, line: UInt = #line) {
        let granted = app.staticTexts["Accessibility permission granted"]
        XCTAssertTrue(
            granted.waitForExistence(timeout: 5),
            "The opt-in global regression run requires real Accessibility permission for this signed Orbit build.",
            file: file,
            line: line
        )
    }

    @MainActor
    private func recordShortcut(_ key: XCUIKeyboardKey, modifiers: XCUIElement.KeyModifierFlags = [], display: String) {
        let record = app.buttons["settings.trigger.shortcut.record"]
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        record.click()
        app.windows["Settings"].typeKey(key, modifierFlags: modifiers)
        let value = app.staticTexts["settings.trigger.shortcut.value"]
        XCTAssertTrue(value.waitForExistence(timeout: 5))
        XCTAssertEqual(value.value as? String, display)
    }

    @MainActor
    private func selectTriggerModifier(_ title: String) {
        app.popUpButtons["settings.trigger.modifier"].click()
        app.menuItems[title].click()
    }

    @MainActor
    private func prepareFinderAfterCalculator() -> XCUIApplication {
        calculatorStartedByTest = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.calculator").isEmpty
        let calculator = XCUIApplication(bundleIdentifier: "com.apple.calculator")
        calculator.activate()
        assertFrontmost("com.apple.calculator")
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        assertFrontmost("com.apple.finder")
        return finder
    }

    @MainActor
    private func assertFrontmost(_ bundleID: String, file: StaticString = #filePath, line: UInt = #line) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 5), .completed, "Expected \(bundleID) to remain frontmost.", file: file, line: line)
    }

    @MainActor
    private func assertRingClosed(file: StaticString = #filePath, line: UInt = #line) {
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: ring)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 5), .completed, file: file, line: line)
    }

    @MainActor
    private func attachRing(named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
