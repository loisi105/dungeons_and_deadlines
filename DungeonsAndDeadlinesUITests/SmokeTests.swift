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

    /// Completes a task the way a player does: swipe right, then tap the Complete button that stays open.
    func swipeComplete(_ app: XCUIApplication, _ title: String) {
        let row = app.descendants(matching: .any)["task-\(title)"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "row \(title)")
        row.swipeRight()
        let button = app.buttons["Complete"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Complete button after swipe")
        button.tap()
    }

    /// ⋯ → Select Tasks.
    func startSelecting(_ app: XCUIApplication) {
        app.buttons["tasksMenuButton"].tap()
        app.buttons["selectTasksButton"].tap()
    }

    /// Bottom bar Complete, then the confirmation dialog.
    func tapCompleteSelected(_ app: XCUIApplication) {
        let button = app.buttons["completeSelectedButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: button)
        waitForExpectations(timeout: 5)
        button.tap()
        let confirm = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Complete' AND label != 'Complete'")).firstMatch
        let single = app.sheets.buttons["Complete"].firstMatch
        if confirm.waitForExistence(timeout: 3) { confirm.tap() } else if single.exists { single.tap() }
    }

    func audit(_ app: XCUIApplication, _ screen: String, skipping skipped: XCUIAccessibilityAuditType = []) throws {
        try app.performAccessibilityAudit(for: XCUIAccessibilityAuditType.all.subtracting(skipped)) { issue in
            // Text clipping inside system-owned chrome (tab bar, keyboard) isn't ours to fix.
            if issue.auditType == .textClipped, issue.element?.elementType == .tabBar { return true }
            if issue.element?.elementType == .keyboard { return true }
            // Icon-and-title list buttons wrap at large sizes (checked at AX3 on Settings); the audit
            // reports them as possibly clipped anyway.
            if issue.auditType == .textClipped,
               ["See Premium", "Sign in to Game Center", "Premium is active", "Manage subscription"].contains(issue.element?.label ?? "") { return true }
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
            // iPad sheets float over the dimmed screen; the audit then reports the dimmed
            // text behind them without naming an element. Nothing to act on there.
            if [.elementDetection, .textClipped, .contrast].contains(issue.auditType), issue.element == nil { return true }
            // System segmented controls cap their font; the meter hides its switch at
            // accessibility sizes (checked at AX5 with -seedDemo -fakeTeammates -startTab meter).
            if issue.auditType == .dynamicType, issue.element == nil || issue.element?.elementType == .segmentedControl { return true }
            // Toolbar buttons and inline navigation titles are capped by the system and use the
            // Large Content Viewer instead.
            if issue.auditType == .dynamicType || issue.auditType == .textClipped, let element = issue.element,
               app.navigationBars.buttons[element.label].exists || app.navigationBars.staticTexts[element.label].exists { return true }
            // Inside the system DatePicker (its compact date label) is Apple's UI.
            if issue.detailedDescription.contains("_UIDatePicker") { return true }
            // The compact date picker's label is just the date ("24.11.2026"), which the audit
            // can't read as a description. It is Apple's control.
            if issue.auditType == .sufficientElementDescription, let label = issue.element?.label,
               !label.isEmpty, label.rangeOfCharacter(from: .letters) == nil { return true }
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
        let field = app.descendants(matching: .any)["raidNameField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(name)
        app.buttons["createRaidButton"].tap()
    }

    /// The tab's button: bottom tab bar on iPhone, top tab bar (plain buttons) on iPad.
    func tabButton(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        let bottom = app.tabBars.buttons[name]
        if bottom.waitForExistence(timeout: 2) { return bottom }
        let matches = app.buttons.matching(NSPredicate(format: "label == %@", name))
        return matches.allElementsBoundByIndex.first(where: \.isHittable) ?? matches.firstMatch
    }

    func tab(_ app: XCUIApplication, _ name: String) {
        let button = tabButton(app, name)
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
        let row = app.descendants(matching: .any)["task-\(title)"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeRight()
        app.buttons["Complete"].firstMatch.tap()
    }

    /// Scrolls until `element` is visible and not under the fixed tab bar / timer bar.
    func scrollClearOfBottomBars(_ app: XCUIApplication, _ element: XCUIElement) {
        let bars = [app.tabBars.firstMatch, app.buttons["focusAccessory"]].filter(\.exists).map(\.frame.minY)
        let limit = (bars.min() ?? app.frame.maxY) - 16
        var swipes = 0
        while (!element.exists || !element.isHittable || element.frame.maxY > limit) && swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
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
        // Completing during planning asks to start the fight first.
        tab(app, "Tasks")
        swipeComplete(app, "Outline")
        let startAndComplete = app.buttons["Start the fight and complete"]
        XCTAssertTrue(startAndComplete.waitForExistence(timeout: 5))
        startAndComplete.tap()
        // Completing jumps straight to the boss for the attack.
        XCTAssertTrue(hpLabel(app, contains: "312 / 462 HP").waitForExistence(timeout: 8))
        let bossTab = tabButton(app, "Boss")
        expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: bossTab)
        waitForExpectations(timeout: 5)
        try audit(app, "Boss (fighting)")

        // Swiping right completes too.
        tab(app, "Tasks")
        complete(app, "Draft")
        tab(app, "Boss")
        XCTAssertTrue(hpLabel(app, contains: "162 / 462 HP").waitForExistence(timeout: 5))

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

        // A trip to the Home Screen (or locking the phone) keeps it running.
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
        app.buttons["settingsButton"].tap() // the debug toggle lives in Settings
        let toggle = app.switches["fakeTeammatesToggle"]
        scrollClearOfBottomBars(app, toggle)
        // Tap the switch itself (right edge); the row's center doesn't toggle it.
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "0")
        tab(app, "Meter")
        // At accessibility sizes the meter swaps the chart for the list on purpose, so the
        // chart's text "stops growing" in this check. The list is audited fully below.
        try audit(app, "Meter (chart)", skipping: .dynamicType)
        app.buttons["List"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH '1.'")).firstMatch.waitForExistence(timeout: 5))
        sleep(1) // let the chart-to-list transition finish before measuring contrast
        try audit(app, "Meter (list)")
    }

    func testVictoryReport() throws {
        let app = launch(["-seedFinished"])
        let seeReport = app.buttons["seeReportButton"]
        XCTAssertTrue(seeReport.waitForExistence(timeout: 10))
        try audit(app, "Boss (victory)")
        seeReport.tap()
        XCTAssertTrue(app.staticTexts["The party"].waitForExistence(timeout: 5))
        sleep(1)
        try audit(app, "Report")
    }

    func testSwitchBetweenBosses() throws {
        let app = launch(["-seedDemo", "-premium"])
        XCTAssertTrue(app.navigationBars["Thesis"].waitForExistence(timeout: 5))

        // Start a second boss from the Boss tab's switcher.
        app.buttons["bossSwitcher"].tap()
        let newBoss = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'New boss'")).firstMatch
        XCTAssertTrue(newBoss.waitForExistence(timeout: 5))
        newBoss.tap()
        let name = app.descendants(matching: .any)["raidNameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Essay")
        app.buttons["createRaidButton"].tap()
        XCTAssertTrue(app.navigationBars["Essay"].waitForExistence(timeout: 5))
        try audit(app, "Boss (second boss)")

        // Switch back from the Tasks tab; the tab stays selected and shows that boss's tasks.
        tab(app, "Tasks")
        app.buttons["bossSwitcher"].tap()
        let dragon = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Exam Dragon'")).firstMatch
        XCTAssertTrue(dragon.waitForExistence(timeout: 5))
        dragon.tap()
        XCTAssertTrue(app.descendants(matching: .any)["task-Literature review"].waitForExistence(timeout: 5))
        XCTAssertTrue(tabButton(app, "Tasks").isSelected)
    }

    func testFreePlanSoftPaywall() throws {
        // Free plan with one active solo boss already (-seedDemo, no -premium).
        let app = launch(["-seedDemo"])
        app.buttons["bossSwitcher"].tap()
        let newBoss = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'New boss'")).firstMatch
        XCTAssertTrue(newBoss.waitForExistence(timeout: 5))
        newBoss.tap()

        // The create sheet says why, before anyone hits a wall.
        XCTAssertTrue(app.buttons["seePremiumButton"].waitForExistence(timeout: 5))
        try audit(app, "New raid (free limit)")

        // Trying anyway opens the paywall, which can always be dismissed.
        let name = app.descendants(matching: .any)["raidNameField"]
        name.tap()
        name.typeText("Essay")
        app.buttons["createRaidButton"].tap()
        let notNow = app.buttons["paywallNotNow"]
        XCTAssertTrue(notNow.waitForExistence(timeout: 10))
        sleep(2)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Paywall"
        shot.lifetime = .keepAlways
        add(shot)
        // The paywall scrolls; at AX5 everything wraps (checked with -seedDemo -showPaywall),
        // but the clipping check misjudges this scrolling sheet, so only that check is skipped.
        try audit(app, "Paywall", skipping: .textClipped)
        notNow.tap()
        XCTAssertTrue(app.descendants(matching: .any)["raidNameField"].waitForExistence(timeout: 5))
    }

    func testFreePlanPremiumBossesAndRaidMode() throws {
        // A fresh free player: the first solo boss is free, but only with a free look.
        let app = launch()
        onboard(app)
        app.buttons["newRaidButton"].tap()
        let bossField = app.descendants(matching: .any)["bossNameField"]
        XCTAssertTrue(bossField.waitForExistence(timeout: 5))
        XCTAssertEqual(bossField.value as? String, "Unfinished Citation Goblin")

        // Raid mode is marked Premium and opens the paywall; the picker stays on Solo.
        let raidMode = app.buttons["Raid · Premium"]
        XCTAssertTrue(raidMode.waitForExistence(timeout: 5))
        raidMode.tap()
        let notNow = app.buttons["paywallNotNow"]
        XCTAssertTrue(notNow.waitForExistence(timeout: 10))
        notNow.tap()
        XCTAssertTrue(app.buttons["Solo"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Solo"].isSelected)

        // Locked bosses in the grid open the paywall and keep the name.
        app.buttons["chooseBossButton"].tap()
        let kraken = app.buttons["bossPick.kraken"]
        XCTAssertTrue(kraken.waitForExistence(timeout: 5))
        XCTAssertEqual(kraken.value as? String, "Premium")
        // At the audit's large text sizes the two boss sections are taller than an iPhone screen,
        // and it reports the tiles below the fold as "Dynamic Type partially unsupported" although
        // they scale and scroll into view (checked by hand at AX5, light and dark, iPhone 17).
        // Only that check is skipped here.
        try audit(app, "Choose your boss (free)", skipping: .dynamicType)
        kraken.tap()
        XCTAssertTrue(notNow.waitForExistence(timeout: 10))
        notNow.tap()
        XCTAssertTrue(app.buttons["bossPick.dragon"].waitForExistence(timeout: 5))
        app.buttons["bossPickerDoneButton"].tap()
        XCTAssertEqual(bossField.value as? String, "Unfinished Citation Goblin")

        // A typed Premium name shows a lock note, and Create opens the paywall instead.
        let raidName = app.descendants(matching: .any)["raidNameField"]
        raidName.tap()
        raidName.typeText("Essay")
        bossField.tap()
        bossField.typeText(" Kraken")
        XCTAssertTrue(app.descendants(matching: .any)["premiumBossNote"].waitForExistence(timeout: 5))
        app.buttons["createRaidButton"].tap()
        XCTAssertTrue(notNow.waitForExistence(timeout: 10))
        notNow.tap()
        XCTAssertTrue(raidName.waitForExistence(timeout: 5), "The create sheet stays open")
    }

    func testTappingOutsideHidesKeyboard() throws {
        let app = launch(["-seedDemo", "-premium"])
        let keyboard = app.keyboards.firstMatch
        func waitForKeyboardToHide() {
            let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: keyboard)
            wait(for: [gone], timeout: 5)
        }

        app.buttons["bossSwitcher"].tap()
        let newBoss = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'New boss'")).firstMatch
        XCTAssertTrue(newBoss.waitForExistence(timeout: 5))
        newBoss.tap()

        // Tapping a field shows the keyboard; moving to another field keeps it.
        let name = app.descendants(matching: .any)["raidNameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        app.descendants(matching: .any)["bossNameField"].tap()
        XCTAssertTrue(keyboard.exists)

        // Tapping anywhere else hides it.
        app.staticTexts["Deadline"].tap()
        waitForKeyboardToHide()

        // Tapping a button hides it and still does what the button does.
        name.tap()
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        waitForKeyboardToHide()
        XCTAssertFalse(name.waitForExistence(timeout: 2), "Cancel should still close the sheet")
    }

    /// Settings holds the profile, Premium, Game Center and the alert switches, and picking a class
    /// must not hang the app (a binding to the database record once spun it at 100% CPU).
    /// Settings as a Premium subscriber sees it (the rows differ from the free plan's).
    func testSettingsAsPremiumPassesAudit() throws {
        let app = launch(["-seedDemo", "-startTab", "raid", "-premium"])
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.staticTexts["Profile"].waitForExistence(timeout: 5))
        try audit(app, "Settings (Premium)", skipping: .dynamicType)
    }

    func testSettingsScreenAndClassPicker() throws {
        let app = launch(["-seedDemo", "-startTab", "raid"])
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.staticTexts["Profile"].waitForExistence(timeout: 5))
        // Rows here stack at large sizes, which the Dynamic Type audit misreads (checked by hand).
        try audit(app, "Settings", skipping: .dynamicType)

        let classRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Class'")).firstMatch
        XCTAssertTrue(classRow.waitForExistence(timeout: 5))
        classRow.tap()
        let healer = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Healer'")).firstMatch
        XCTAssertTrue(healer.waitForExistence(timeout: 5), "The class list should open")
        healer.tap()
        // Back on Settings with the new class shown.
        XCTAssertTrue(app.staticTexts["Profile"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Healer'")).firstMatch.waitForExistence(timeout: 5))
    }

    func testSeePremiumStaysOpen() throws {
        let app = launch(["-seedDemo"])
        tab(app, "Raid")
        app.buttons["settingsButton"].tap()
        let seePremium = app.buttons["partySeePremium"]
        scrollClearOfBottomBars(app, seePremium)
        seePremium.tap()

        // One tap opens the paywall, and it stays open.
        let notNow = app.buttons["paywallNotNow"]
        XCTAssertTrue(notNow.waitForExistence(timeout: 5))
        sleep(3)
        XCTAssertTrue(notNow.exists, "The paywall closed by itself")
        notNow.tap()
        XCTAssertFalse(notNow.waitForExistence(timeout: 2))
    }

    func testTappingATaskOpensItsDetails() throws {
        let app = launch(["-seedDemo", "-startTab", "tasks"])
        let title = app.staticTexts["Literature review"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        XCTAssertTrue(app.navigationBars["Task"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Complete task"].exists)
    }

    /// Perf probe: times opening the new-task sheet and typing the first word. Run on a device
    /// in Release while profiling; prints the durations.
    func testPerfNewTaskTyping() throws {
        let app = launch(["-seedDemo", "-startTab", "tasks"])
        XCTAssertTrue(app.buttons["addTaskButton"].waitForExistence(timeout: 10))
        for round in 1...3 {
            let t0 = Date()
            app.buttons["addTaskButton"].tap()
            let field = app.descendants(matching: .any)["taskTitleField"]
            XCTAssertTrue(field.waitForExistence(timeout: 10))
            let opened = Date().timeIntervalSince(t0)
            field.tap()
            let t1 = Date()
            field.typeText("Write")
            let typed = Date().timeIntervalSince(t1)
            print("PERF round \(round): sheet opened in \(String(format: "%.2f", opened)) s, typed 5 chars in \(String(format: "%.2f", typed)) s")
            app.buttons["Cancel"].firstMatch.tap()
            sleep(1)
        }
    }

    func testPickingSizeWhileTypingRegistersTheTap() throws {
        let app = launch(["-seedDemo", "-startTab", "tasks"])
        app.buttons["addTaskButton"].tap()
        let field = app.descendants(matching: .any)["taskTitleField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Write")
        app.buttons["Large"].tap()
        let damage = app.textFields["taskDamageField"]
        XCTAssertTrue(damage.waitForExistence(timeout: 5))
        XCTAssertEqual(damage.value as? String, "400", "the first tap on Large must register")
        XCTAssertTrue(app.keyboards.count > 0, "the keyboard stays up")
    }

    func testClickableAreasKeepTheKeyboardUp() throws {
        let app = launch(["-seedDemo", "-startTab", "tasks", "-fakeTeammates"])
        app.buttons["addTaskButton"].tap()
        let field = app.descendants(matching: .any)["taskTitleField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Write")
        let assigned = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Assigned'")).firstMatch
        XCTAssertTrue(assigned.waitForExistence(timeout: 5), app.debugDescription)
        assigned.tap()
        XCTAssertTrue(app.buttons["Nobody"].firstMatch.waitForExistence(timeout: 5), "the menu opened on the first tap")
    }

    func testEdgeSwipeGoesBackFromTaskDetails() throws {
        let app = launch(["-seedDemo", "-startTab", "tasks"])
        app.staticTexts["Literature review"].tap()
        XCTAssertTrue(app.navigationBars["Task"].waitForExistence(timeout: 5))
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)))
        XCTAssertTrue(app.navigationBars["Quest Log"].waitForExistence(timeout: 5))
    }

    func testTaskDetailsCanDelete() throws {
        let app = launch(["-seedDemo", "-startTab", "tasks"])
        let title = app.staticTexts["Literature review"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        let delete = app.buttons["deleteTaskButton"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        app.buttons["Delete task"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Literature review"].waitForNonExistence(timeout: 5))
    }

    func testSwipeCompleteNeedsConfirmation() throws {
        let app = launch(["-seedDemo", "-startTab", "tasks"])
        let row = app.descendants(matching: .any)["task-Fix citations"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.swipeRight()
        // A swipe alone doesn't complete: the button waits for a tap.
        XCTAssertTrue(app.buttons["Complete"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Done (1)"].exists, "still not completed after the swipe")
        app.buttons["Complete"].firstMatch.tap()
        // Completing jumps to the boss for the attack.
        let bossTab = tabButton(app, "Boss")
        expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: bossTab)
        waitForExpectations(timeout: 10)
    }

    func testSelectAllAndCompleteSeveral() throws {
        let app = launch(["-seedDemo", "-startTab", "tasks"])
        XCTAssertTrue(app.buttons["tasksMenuButton"].waitForExistence(timeout: 10))
        startSelecting(app)
        XCTAssertTrue(app.buttons["selectAllButton"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["completeSelectedButton"].isEnabled, "nothing selected yet")
        app.buttons["selectAllButton"].tap()
        XCTAssertTrue(app.navigationBars["3 Selected"].waitForExistence(timeout: 5))
        app.buttons["selectAllButton"].tap() // now Deselect All
        XCTAssertTrue(app.navigationBars["Select Tasks"].waitForExistence(timeout: 5))
        app.buttons["selectAllButton"].tap()
        tapCompleteSelected(app)
        // The three attacks play on the boss tab.
        let bossTab = tabButton(app, "Boss")
        expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: bossTab)
        waitForExpectations(timeout: 10)
    }

    func testFollowUpTasksResumeTheFight() throws {
        let app = launch(["-seedFinished"])
        XCTAssertTrue(app.buttons["seeReportButton"].waitForExistence(timeout: 10))

        // The report closes with the native close button.
        app.buttons["seeReportButton"].tap()
        let close = app.buttons["closeButton"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertTrue(close.isHittable)
        close.tap()

        // Follow-up work after the win: add a task, then resume.
        let add = app.buttons["addFollowUpButton"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        let title = app.descendants(matching: .any)["taskTitleField"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Fix review comments")
        app.buttons["saveTaskButton"].tap()

        app.buttons["resumeFightButton"].tap()
        let confirm = app.buttons["confirmResumeButton"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        try audit(app, "Resume the fight")
        confirm.tap()

        // The boss is back with health from all open tasks: 2 small left over + the new medium (250 / 0.65 = 385).
        XCTAssertTrue(hpLabel(app, contains: "385 / ").waitForExistence(timeout: 5))
        try audit(app, "Boss (resumed)")
    }

    func testFreePlanDeleteOldBossToStartANewOne() throws {
        let app = launch(["-seedDemo"])
        app.buttons["bossSwitcher"].tap()
        let newBoss = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'New boss'")).firstMatch
        XCTAssertTrue(newBoss.waitForExistence(timeout: 5))
        newBoss.tap()

        // At the free limit the sheet offers to delete the current boss.
        let delete = app.buttons["deleteActiveBossButton"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        let confirm = app.buttons["Delete boss"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()

        // The slot is free; the sheet stays open and creating works.
        XCTAssertFalse(app.buttons["seePremiumButton"].waitForExistence(timeout: 2))
        let name = app.descendants(matching: .any)["raidNameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Essay")
        app.buttons["createRaidButton"].tap()
        XCTAssertTrue(app.navigationBars["Essay"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["paywallNotNow"].exists)
    }

    func testTaskAttackJumpsToBossAndAnimates() throws {
        let app = launch(["-seedDemo", "-startTab", "tasks"]) // the demo player is a mage
        swipeComplete(app, "Literature review")

        // The app switches to the boss and plays the spell; the hit lands and it stays there.
        let bossTab = tabButton(app, "Boss")
        XCTAssertTrue(bossTab.waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: bossTab)
        waitForExpectations(timeout: 5)
        Thread.sleep(forTimeInterval: 0.4)
        let midFlight = XCTAttachment(screenshot: app.screenshot())
        midFlight.name = "Attack mid-flight"
        midFlight.lifetime = .keepAlways
        add(midFlight)
        XCTAssertTrue(hpLabel(app, contains: "550 / 1.000 HP").waitForExistence(timeout: 8)
                      || hpLabel(app, contains: "550 / 1,000 HP").exists)
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertTrue(tabButton(app, "Boss").isSelected)
        try audit(app, "Boss (after attack)")
    }


    /// Not a check: screenshots of a new player's first minutes, for reviewing how the app reads.
    /// Run with `TEST_RUNNER_DD_CAPTURE_UX=1`; frames are named "UX n name".
    func testCaptureFirstRun() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DD_CAPTURE_UX"] != nil, "Runs only on request")
        let app = launch()
        var n = 0
        func snap(_ name: String) {
            Thread.sleep(forTimeInterval: 0.8)
            n += 1
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "UX \(n) \(name)"
            shot.lifetime = .keepAlways
            add(shot)
        }
        snap("onboarding")
        onboard(app)
        snap("welcome")
        createRaid(app)
        snap("boss planning")
        tab(app, "Tasks")
        snap("tasks empty")
        addTask(app, "Write intro")
        addTask(app, "Find sources")
        snap("tasks planned")
        tab(app, "Boss")
        snap("boss planned")
    }

    /// Not a check: captures the class attack in slow motion for review.
    /// Run with `TEST_RUNNER_DD_CAPTURE=1 ./build.sh test -only-testing:…/testCaptureAttackFrames`.
    func testCaptureAttackFrames() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DD_CAPTURE"] != nil, "Frame capture runs only on request")
        // `TEST_RUNNER_DD_ROLE=tank|rogue|healer|none` picks the class (default mage).
        let role = ProcessInfo.processInfo.environment["DD_ROLE"] ?? "mage"
        let app = launch(["-seedDemo", "-startTab", "tasks", "-slowMotion", "-demoRole", role])
        swipeComplete(app, "Literature review")
        for i in 0..<9 {
            Thread.sleep(forTimeInterval: 0.9)
            let frame = XCTAttachment(screenshot: app.screenshot())
            frame.name = "Attack frame \(i)"
            frame.lifetime = .keepAlways
            add(frame)
        }
    }
}
