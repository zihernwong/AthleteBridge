import XCTest

/// Coach-tier gating + paid/recurring club signup events.
/// testA runs with the coach on the free tier (locks visible);
/// testB_unlocked is run separately after the tier is flipped to plus.
/// Requires the seeded "UI Test Club (temporary)" place and
/// "Weekly Open Play (test)" event.
final class MonetizationTests: XCTestCase {

    var app: XCUIApplication!
    let screenshotDir = "/private/tmp/claude-501/-Users-hernwong-Documents-AthleteBridge/2abfbb42-2cc2-4179-97f9-5607441c9721/scratchpad"

    let coachEmail = "coach@gmail.com"
    let password   = "Hercia12"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()

        addUIInterruptionMonitor(withDescription: "Permission dialogs") { alert in
            for label in ["Don't Allow", "Allow Full Access", "Allow", "OK", "Continue"] {
                let btn = alert.buttons[label]
                if btn.exists { btn.tap(); return true }
            }
            return false
        }
    }

    private func dismissSessionsSheet() {
        let laterButton = app.buttons["Later"]
        if laterButton.waitForExistence(timeout: 3) {
            laterButton.tap()
            sleep(1)
        }
    }

    private func ensureLoggedOut() {
        if !app.textFields["Email"].waitForExistence(timeout: 5) {
            dismissSessionsSheet()
            let profileTab = app.tabBars.buttons["Profile"]
            if profileTab.waitForExistence(timeout: 5) {
                profileTab.tap()
                let logoutButton = app.buttons["Logout"]
                if logoutButton.waitForExistence(timeout: 8) { logoutButton.tap() }
            }
        }
        XCTAssertTrue(app.textFields["Email"].waitForExistence(timeout: 10), "Couldn't reach the login screen")
    }

    private func login() {
        let emailField = app.textFields["Email"]
        emailField.tap()
        emailField.typeText(coachEmail)
        let passwordField = app.secureTextFields["Password"]
        if passwordField.waitForExistence(timeout: 3) {
            passwordField.tap()
            passwordField.typeText(password)
        }
        app.buttons["Login"].tap()
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 20), "Login failed")
        sleep(3)
        dismissSessionsSheet()
    }

    private func snap(_ name: String) {
        sleep(1)
        let screenshot = XCUIScreen.main.screenshot()
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: "\(screenshotDir)/\(name).png"))
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        print("📸 Saved: \(name)")
    }

    private func tapLabel(_ label: String, timeout: TimeInterval = 5) -> Bool {
        for _ in 0..<5 {
            if app.buttons["Later"].exists { app.buttons["Later"].tap(); sleep(1) }
            let button = app.buttons[label]
            if button.waitForExistence(timeout: timeout) && button.isHittable {
                button.tap()
                return true
            }
            let text = app.staticTexts[label]
            if text.exists && text.isHittable {
                text.tap()
                return true
            }
            app.swipeUp()
        }
        return false
    }

    /// Switch tabs even if the "Sessions to Log" sheet swallows the first tap.
    private func openTab(_ name: String) {
        for _ in 0..<4 {
            if app.buttons["Later"].exists { app.buttons["Later"].tap(); sleep(1) }
            let tab = app.tabBars.buttons[name]
            guard tab.waitForExistence(timeout: 5) else { continue }
            tab.tap()
            sleep(1)
            if !app.buttons["Later"].exists && tab.isSelected { return }
        }
    }

    private func scrollTo(_ element: XCUIElement, attempts: Int = 6) -> Bool {
        for _ in 0..<attempts {
            if app.buttons["Later"].exists { app.buttons["Later"].tap(); sleep(1) }
            if element.waitForExistence(timeout: 2) && element.isHittable { return true }
            app.swipeUp(velocity: .fast)
        }
        return element.exists
    }

    @MainActor
    func testA_freeTierLocksAndClubEvent() throws {
        sleep(3)
        ensureLoggedOut()
        login()

        // ── Free-tier lock on Earnings Forecaster ───────────────────────
        openTab("Payments")
        sleep(2)
        let forecaster = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Earnings Forecaster'")).firstMatch
        XCTAssertTrue(scrollTo(forecaster), "Forecaster button missing")
        XCTAssertTrue(forecaster.label.contains("Plus / Pro"), "Lock caption missing on free tier")
        snap("40_locked_forecaster")
        forecaster.tap()
        let upgradeAlert = app.alerts["Upgrade Required"]
        XCTAssertTrue(upgradeAlert.waitForExistence(timeout: 5), "Upgrade alert didn't appear")
        upgradeAlert.buttons["Manage Subscription"].tap()
        XCTAssertTrue(app.navigationBars["Subscription"].waitForExistence(timeout: 8), "Paywall sheet didn't open")
        snap("41_paywall_sheet")
        app.buttons["Done"].tap()

        // ── Paid + recurring club event ─────────────────────────────────
        openTab("Home")
        sleep(1)
        XCTAssertTrue(tapLabel("Browse Places"), "Browse Places missing")
        sleep(2)
        XCTAssertTrue(tapLabel("UI Test Club (temporary)"), "Temp club not listed")
        sleep(2)
        let eventRow = app.staticTexts["Weekly Open Play (test)"]
        XCTAssertTrue(scrollTo(eventRow), "Seeded event not shown on club page")
        eventRow.tap()

        XCTAssertTrue(app.staticTexts["$8.00 per player"].waitForExistence(timeout: 8), "Fee line missing")
        XCTAssertTrue(app.staticTexts["Repeats weekly"].exists, "Recurrence line missing")
        snap("42_paid_event_detail")

        // Creator toggles Lin Dan's paid checkmark
        let unpaidHeader = app.staticTexts["Signed Up (1) · 0 paid"]
        XCTAssertTrue(scrollTo(unpaidHeader), "Paid-count header missing")
        let paidToggle = app.images["circle"].firstMatch.exists ? app.images["circle"].firstMatch : app.buttons["circle"].firstMatch
        if paidToggle.exists && paidToggle.isHittable {
            paidToggle.tap()
        } else {
            // Fall back: tap the row's leading toggle by coordinate on the Lin Dan row
            let row = app.staticTexts["Lin Dan"]
            XCTAssertTrue(row.exists, "Signup row missing")
            row.coordinate(withNormalizedOffset: CGVector(dx: -0.35, dy: 0.5)).tap()
        }
        XCTAssertTrue(app.staticTexts["Signed Up (1) · 1 paid"].waitForExistence(timeout: 10), "Paid toggle didn't update")
        snap("43_marked_paid")

        // Roll next week's occurrence
        let nextButton = app.buttons["Schedule Next Week's Event"]
        XCTAssertTrue(scrollTo(nextButton), "Schedule-next-week button missing")
        nextButton.tap()
        sleep(3)
        snap("44_next_week_scheduled")

        // Logout for the tier flip
        let profileTab = app.tabBars.buttons["Profile"]
        if profileTab.waitForExistence(timeout: 5) {
            profileTab.tap()
            let logoutButton = app.buttons["Logout"]
            if logoutButton.waitForExistence(timeout: 8) { logoutButton.tap() }
        }
    }

    @MainActor
    func testB_unlocked() throws {
        sleep(3)
        ensureLoggedOut()
        login()

        openTab("Payments")
        sleep(2)
        let forecaster = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Earnings Forecaster'")).firstMatch
        XCTAssertTrue(scrollTo(forecaster), "Forecaster button missing")
        XCTAssertFalse(forecaster.label.contains("Plus / Pro"), "Plus coach still shows lock caption")
        forecaster.tap()
        // On Plus the sheet opens instead of the upgrade alert
        XCTAssertFalse(app.alerts["Upgrade Required"].waitForExistence(timeout: 3), "Plus coach still locked out")
        snap("45_unlocked_forecaster")
    }
}
