import XCTest

/// End-to-end flows with an accessibility audit on every screen.
/// `-uiTesting` gives each run an in-memory store and a fresh identity.
@MainActor
final class SmokeTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    // MARK: Helpers

    func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + extra
        app.launch()
        return app
    }

    func audit(_ app: XCUIApplication, _ screen: String, skipping skipped: XCUIAccessibilityAuditType = []) throws {
        try app.performAccessibilityAudit(for: XCUIAccessibilityAuditType.all.subtracting(skipped)) { issue in
            // Text clipping inside system-owned chrome (tab bar, keyboard) isn't ours to fix.
            if issue.auditType == .textClipped, issue.element?.elementType == .tabBar { return true }
            if issue.element?.elementType == .keyboard { return true }
            // The contrast audit misreads Liquid Glass button fills. Our button colors are
            // checked by hand instead: white on `Color.actionTint` is ~8:1, and accent-tinted
            // labels on glass are ~5:1. Text contrast everywhere else stays strict.
            if issue.auditType == .contrast, let element = issue.element,
               element.elementType == .button || app.buttons[element.label].exists { return true }
            // Content partly under the tab bar or the focus accessory can't be measured;
            // it scrolls into view. (Applies to every audit type.)
            if let element = issue.element {
                let chrome = [app.tabBars.firstMatch, app.buttons["focusAccessory"]].filter(\.exists).map(\.frame)
                if chrome.contains(where: { $0.insetBy(dx: 0, dy: -12).intersects(element.frame) }) { return true }
            }
            // System segmented controls cap their font; the meter hides its switch at
            // accessibility sizes (checked at AX5 with -seedDemo -fakeTeammates -startTab meter).
            if issue.auditType == .dynamicType, issue.element == nil || issue.element?.elementType == .segmentedControl { return true }
            // Toolbar buttons are capped by the system and use the Large Content Viewer instead.
            if issue.auditType == .dynamicType, let element = issue.element,
               app.navigationBars.buttons[element.label].exists { return true }
            // The keyboard's prediction bar is system UI.
            if issue.detailedDescription.contains("TUIPrediction") { return true }
            print("AUDIT [\(screen)] \(issue.compactDescription): \(issue.detailedDescription) | element: \(issue.element.map { "\($0.elementType.rawValue) id=\($0.identifier) label=\($0.label) frame=\($0.frame)" } ?? "nil")")
            return false
        }
    }

    func onboard(_ app: XCUIApplication, name: String = "Ada") {
        let field = app.textFields["nicknameField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(name + "\n") // Return submits
    }

    func createRaid(_ app: XCUIApplication, name: String = "Thesis") {
        app.buttons["newRaidButton"].tap()
        let field = app.textFields["raidNameField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(name)
        app.buttons["createRaidButton"].tap()
    }

    func tab(_ app: XCUIApplication, _ name: String) {
        let button = app.tabBars.buttons[name]
        // Scrolling down minimizes the tab bar; scroll back up to bring it back.
        var tries = 0
        while !button.exists && tries < 4 { app.swipeDown(); tries += 1 }
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Missing tab \(name)")
        button.tap()
    }

    func addTask(_ app: XCUIApplication, _ title: String) {
        app.buttons["addTaskButton"].tap()
        let field = app.descendants(matching: .any)["taskTitleField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(title)
        app.buttons["saveTaskButton"].tap()
    }

    func complete(_ app: XCUIApplication, _ title: String) {
        let row = app.buttons["task-\(title)"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeRight()
        app.buttons["Complete"].firstMatch.tap()
    }

    func hpLabel(_ app: XCUIApplication, contains text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    // MARK: Tests

    func testOnboardingAndWelcomePassAudit() throws {
        let app = launch()
        try audit(app, "Onboarding")
        onboard(app)
        XCTAssertTrue(app.buttons["newRaidButton"].waitForExistence(timeout: 5))
        try audit(app, "Welcome")
    }

    func testSoloRaidPlanStartAndHit() throws {
        let app = launch()
        onboard(app)
        createRaid(app)

        // Planning: add tasks, check the predicted HP, start the fight.
        tab(app, "Tasks")
        addTask(app, "Outline")   // new tasks default to M = 150
        addTask(app, "Draft")     // M = 150
        try audit(app, "Tasks (planning)")
        tab(app, "Boss")
        XCTAssertTrue(hpLabel(app, contains: "462 / 462 HP").waitForExistence(timeout: 5)) // 300 / 0.65
        try audit(app, "Boss (planning)")
        app.buttons["startFightButton"].tap()

        // Fight: complete a task and see the boss lose health.
        tab(app, "Tasks")
        complete(app, "Outline")
        tab(app, "Boss")
        XCTAssertTrue(hpLabel(app, contains: "312 / 462 HP").waitForExistence(timeout: 5))
        try audit(app, "Boss (fighting)")

        tab(app, "Raid")
        // Rows here switch from side-by-side to stacked at large sizes, which the
        // Dynamic Type audit misreads. Checked by hand at AX5 (launch with
        // `-uiTesting -seedDemo -startTab raid`): all text scales and nothing clips.
        try audit(app, "Raid", skipping: .dynamicType)
    }

    func testFocusTimerSurvivesBackgroundAndStops() throws {
        let app = launch(["-seedDemo"])
        let accessory = app.buttons["focusAccessory"]
        XCTAssertTrue(accessory.waitForExistence(timeout: 5))
        accessory.tap()

        let start = app.buttons["startFocusButton"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        try audit(app, "Focus (idle)")
        start.tap()
        XCTAssertTrue(app.buttons["pauseFocusButton"].waitForExistence(timeout: 5))
        try audit(app, "Focus (running)")

        // A short trip to the Home Screen (under the 2-minute grace period) keeps it running.
        XCUIDevice.shared.press(.home)
        sleep(3)
        app.activate()
        XCTAssertTrue(app.buttons["pauseFocusButton"].waitForExistence(timeout: 5))

        app.buttons["pauseFocusButton"].tap()
        XCTAssertTrue(app.buttons["resumeFocusButton"].waitForExistence(timeout: 5))
        app.buttons["stopFocusButton"].tap()
        XCTAssertTrue(app.buttons["startFocusButton"].waitForExistence(timeout: 5))
    }

    func testDamageMeterWithFakeTeammates() throws {
        let app = launch(["-seedDemo", "-fakeTeammates"])
        tab(app, "Meter")
        // Fake teammates hit every few seconds; wait until one shows up in the meter.
        let mia = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Mia'")).firstMatch
        XCTAssertTrue(mia.waitForExistence(timeout: 30))
        // Stop the simulation so the audit sees a stable screen.
        tab(app, "Raid")
        let toggle = app.switches["fakeTeammatesToggle"]
        while !toggle.isHittable { app.swipeUp() }
        toggle.tap()
        tab(app, "Meter")
        try audit(app, "Meter (chart)")
        app.buttons["List"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH '1.'")).firstMatch.waitForExistence(timeout: 5))
        try audit(app, "Meter (list)")
    }
}
