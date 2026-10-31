import XCTest

final class OrbitSettingsTests: XCTestCase {
    private var app: XCUIApplication!
    private var defaultsSuite = ""

    override func setUpWithError() throws {
        continueAfterFailure = false
        defaultsSuite = "OrbitUITests.\(UUID().uuidString)"
        app = XCUIApplication()
        app.launchEnvironment["ORBIT_UI_TEST_DEFAULTS_SUITE"] = defaultsSuite
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
        UserDefaults(suiteName: defaultsSuite)?.removePersistentDomain(forName: defaultsSuite)
    }

    private func attachAccessibilityTree(named name: String) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func logElement(_ element: XCUIElement, named name: String) {
        let exists = element.exists
        NSLog(
            "OrbitSettingsTests %@ exists=%@ hittable=%@ label=%@ value=%@",
            name,
            String(exists),
            exists ? String(element.isHittable) : "n/a",
            exists ? element.label : "n/a",
            exists ? String(describing: element.value) : "n/a"
        )
    }

    private func booleanValue(of element: XCUIElement) -> Bool? {
        if let value = element.value as? NSNumber {
            return value.boolValue
        }
        if let value = element.value as? Bool {
            return value
        }
        if let value = element.value as? String {
            return value == "1" || value.caseInsensitiveCompare("true") == .orderedSame
        }
        return nil
    }

    private func chooseApplication(at directoryPath: String, named applicationName: String) {
        attachAccessibilityTree(named: "AX after application chooser opened")
        let panel = app.windows["Open"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        attachAccessibilityTree(named: "Application chooser before navigation")

        app.typeKey("g", modifierFlags: [.command, .shift])
        let goSheet = app.sheets.firstMatch
        XCTAssertTrue(goSheet.waitForExistence(timeout: 5))
        let location = goSheet.textFields.firstMatch
        XCTAssertTrue(location.waitForExistence(timeout: 5))
        location.click()
        location.typeKey("a", modifierFlags: .command)
        location.typeText("\(directoryPath)/\(applicationName).app")
        location.typeKey(.return, modifierFlags: [])

        let goSheetDismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: goSheet
        )
        XCTAssertEqual(XCTWaiter.wait(for: [goSheetDismissed], timeout: 5), .completed)

        let search = panel.searchFields["Search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.click()
        search.typeText(applicationName)

        let applicationCell = panel.cells
            .containing(NSPredicate(format: "value == %@", applicationName))
            .firstMatch
        XCTAssertTrue(applicationCell.waitForExistence(timeout: 5))
        XCTAssertTrue(applicationCell.isHittable)
        applicationCell.click()

        let chooseButton = panel.buttons["Choose"]
        XCTAssertTrue(chooseButton.waitForExistence(timeout: 5))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: chooseButton)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        chooseButton.click()
    }

    @MainActor
    func testShortcutRecordingPersistsAndEscapeKeepsThePreviousShortcut() {
        let record = app.buttons["settings.trigger.shortcut.record"]
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
        attachAccessibilityTree(named: "AX before recording")
        record.click()
        app.typeKey("k", modifierFlags: [.control, .option])
        let shortcut = app.staticTexts["settings.trigger.shortcut.value"]
        logElement(shortcut, named: "shortcut after recording")
        attachAccessibilityTree(named: "AX after recording")
        XCTAssertEqual(shortcut.value as? String, "⌃⌥K")

        app.terminate()
        app.launch()
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        logElement(shortcut, named: "shortcut after relaunch")
        XCTAssertEqual(shortcut.value as? String, "⌃⌥K")
        record.click()
        app.typeKey(.escape, modifierFlags: [])
        logElement(shortcut, named: "shortcut after escape")
        XCTAssertEqual(shortcut.value as? String, "⌃⌥K")

        app.buttons["settings.trigger.shortcut.clear"].click()
        logElement(shortcut, named: "shortcut after clear")
        XCTAssertEqual(shortcut.value as? String, "Not set")
    }

    @MainActor
    func testBareTypingIsRejectedAndFunctionKeyCanBeRecorded() {
        let record = app.buttons["settings.trigger.shortcut.record"]
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        record.click()
        app.typeKey("a", modifierFlags: [])
        attachAccessibilityTree(named: "AX after rejected typing")
        let invalidShortcutHint = app.staticTexts.matching(
            NSPredicate(format: "value CONTAINS %@", "Use Command, Option or Control")
        ).firstMatch
        XCTAssertTrue(invalidShortcutHint.waitForExistence(timeout: 5))
        app.typeKey(.F6, modifierFlags: [])
        let shortcut = app.staticTexts["settings.trigger.shortcut.value"]
        logElement(shortcut, named: "F6 shortcut")
        attachAccessibilityTree(named: "AX after F6")
        XCTAssertEqual(shortcut.value as? String, "F6")
    }

    @MainActor
    func testGestureAndWindowFilterPersist() {
        let gesture = app.popUpButtons["settings.trigger.mode"]
        XCTAssertTrue(gesture.waitForExistence(timeout: 5))
        gesture.click()
        app.menuItems["Double-tap and hold"].click()
        XCTAssertTrue(app.staticTexts["Tap once, then press again and hold within 350 ms."].exists)

        let filter = app.descendants(matching: .any)["settings.apps.only_windows"]
        let switchFilter = app.switches["settings.apps.only_windows"]
        let buttonFilter = app.buttons["settings.apps.only_windows"]
        logElement(filter, named: "window filter any")
        logElement(switchFilter, named: "window filter switch")
        logElement(buttonFilter, named: "window filter button")
        attachAccessibilityTree(named: "AX before window filter")
        XCTAssertTrue(filter.waitForExistence(timeout: 5))
        if switchFilter.exists {
            switchFilter.click()
        } else if buttonFilter.exists {
            buttonFilter.click()
        } else if filter.isHittable {
            filter.click()
        } else {
            app.scrollViews.firstMatch.swipeUp()
            filter.click()
        }
        XCTAssertEqual(booleanValue(of: filter), true)
        logElement(switchFilter, named: "window filter after click")
        attachAccessibilityTree(named: "AX after window filter")
        app.terminate()
        app.launch()
        XCTAssertTrue(switchFilter.waitForExistence(timeout: 5))
        XCTAssertEqual(booleanValue(of: filter), true)
        logElement(switchFilter, named: "window filter after relaunch")
        XCTAssertTrue(app.staticTexts["Tap once, then press again and hold within 350 ms."].exists)
    }

    @MainActor
    func testDisabledTriggerDisablesGestureControls() {
        let modifier = app.popUpButtons["settings.trigger.modifier"]
        XCTAssertTrue(modifier.waitForExistence(timeout: 5))
        modifier.click()
        let disabled = app.menuItems.matching(
            NSPredicate(format: "title == %@ OR label == %@", "Disabled", "Disabled")
        ).firstMatch
        XCTAssertTrue(disabled.waitForExistence(timeout: 5))
        disabled.click()

        let disabledSelection = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Disabled"),
            object: modifier
        )
        XCTAssertEqual(XCTWaiter.wait(for: [disabledSelection], timeout: 5), .completed)

        let gesture = app.descendants(matching: .any)["settings.trigger.mode"]
        XCTAssertTrue(gesture.waitForExistence(timeout: 5))
        XCTAssertFalse(gesture.isEnabled)
        XCTAssertFalse(app.sliders.firstMatch.isEnabled)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Disabled trigger settings"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        attachAccessibilityTree(named: "AX disabled trigger settings")
    }

    @MainActor
    func testApplicationRulesAddRemoveAndPersist() {
        let exclude = app.buttons["settings.apps.exclude"]
        XCTAssertTrue(exclude.waitForExistence(timeout: 5))
        exclude.click()
        chooseApplication(at: "/System/Applications", named: "Calculator")

        let removeCalculator = app.descendants(matching: .any)["settings.apps.remove.com.apple.calculator"]
        XCTAssertTrue(removeCalculator.waitForExistence(timeout: 5))
        let excludedScreenshot = XCTAttachment(screenshot: app.screenshot())
        excludedScreenshot.name = "Excluded application rule"
        excludedScreenshot.lifetime = .keepAlways
        add(excludedScreenshot)

        removeCalculator.click()
        XCTAssertFalse(removeCalculator.waitForExistence(timeout: 2))

        app.buttons["settings.apps.pin"].click()
        chooseApplication(at: "/System/Applications", named: "Calculator")
        XCTAssertTrue(removeCalculator.waitForExistence(timeout: 5))
        let pinnedScreenshot = XCTAttachment(screenshot: app.screenshot())
        pinnedScreenshot.name = "Pinned application rule"
        pinnedScreenshot.lifetime = .keepAlways
        add(pinnedScreenshot)

        app.terminate()
        app.launch()
        XCTAssertTrue(removeCalculator.waitForExistence(timeout: 5))

        removeCalculator.click()
        XCTAssertFalse(removeCalculator.waitForExistence(timeout: 2))
        app.terminate()
        app.launch()
        XCTAssertFalse(removeCalculator.waitForExistence(timeout: 2))
    }
}
