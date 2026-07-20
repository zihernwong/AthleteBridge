import XCTest

/// Web tournament manager integration: suggestion linking, native bracket,
/// organizer score entry, unlink, and create-from-app.
/// Requires the seeded "UI Test Open (temporary)" app tournament and
/// "UI Test Open Web (temporary)" web tournament (seed_web.py).
final class TournamentWebTests: XCTestCase {

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

    /// Scroll within the detail Form until an element exists (lazy lists).
    private func scrollTo(_ element: XCUIElement, attempts: Int = 6) -> Bool {
        for _ in 0..<attempts {
            if element.waitForExistence(timeout: 2) && element.isHittable { return true }
            app.swipeUp(velocity: .fast)
        }
        return element.exists
    }

    @MainActor
    func testWebIntegrationFlow() throws {
        sleep(3)
        ensureLoggedOut()
        login()

        // Detail screen of the seeded app tournament
        let homeTab = app.tabBars.buttons["Home"]
        if homeTab.waitForExistence(timeout: 5) { homeTab.tap() }
        XCTAssertTrue(tapLabel("Find Upcoming Tournaments"), "Tournaments entry missing")
        XCTAssertTrue(app.navigationBars["Upcoming Tournaments"].waitForExistence(timeout: 8))
        sleep(2)
        let row = app.staticTexts["UI Test Open (temporary)"]
        XCTAssertTrue(row.waitForExistence(timeout: 8), "Seeded app tournament not listed")
        row.tap()
        XCTAssertTrue(app.navigationBars["Tournament"].waitForExistence(timeout: 8))

        // ── Auto-suggested link ─────────────────────────────────────────
        let suggestion = app.staticTexts["UI Test Open Web (temporary)"]
        XCTAssertTrue(scrollTo(suggestion), "Web tournament suggestion missing")
        snap("30_web_suggestion")
        let linkButton = app.buttons["Link"].firstMatch
        XCTAssertTrue(linkButton.waitForExistence(timeout: 5), "Link button missing")
        linkButton.tap()

        let bracketLink = app.buttons["Bracket & Results"]
        XCTAssertTrue(scrollTo(bracketLink), "Live Results section didn't appear after linking")
        XCTAssertTrue(app.staticTexts["Live"].exists, "Status chip missing")
        snap("31_linked_live_results")

        // ── Native bracket ──────────────────────────────────────────────
        bracketLink.tap()
        XCTAssertTrue(app.navigationBars["Bracket & Results"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Alice Test"].waitForExistence(timeout: 8), "Bracket players missing")
        snap("32_native_bracket")

        // ── Score entry (Alice vs Cara) ────────────────────────────────
        let matchCard = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Alice Test' AND label CONTAINS 'Cara Test'")).firstMatch
        XCTAssertTrue(matchCard.waitForExistence(timeout: 5), "Match card missing")
        matchCard.tap()
        XCTAssertTrue(app.navigationBars["Enter Score"].waitForExistence(timeout: 8), "Score sheet didn't open")

        let fields = app.textFields
        XCTAssertTrue(fields.element(boundBy: 0).waitForExistence(timeout: 5))
        for (i, value) in ["21", "15", "21", "18"].enumerated() {
            let f = fields.element(boundBy: i)
            f.tap()
            f.typeText(value)
        }
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Alice Test wins'")).firstMatch.waitForExistence(timeout: 3), "Verdict missing")
        snap("33_score_entry")
        app.buttons["Save"].tap()

        // Sheet closes; result shows in the bracket
        XCTAssertTrue(app.staticTexts["21–15, 21–18"].waitForExistence(timeout: 10), "Saved sets not shown in bracket")
        snap("34_bracket_after_score")

        // ── Unlink, then create-from-app ───────────────────────────────
        app.navigationBars.buttons.firstMatch.tap()   // back to detail
        XCTAssertTrue(app.navigationBars["Tournament"].waitForExistence(timeout: 8))
        let unlink = app.buttons["Unlink Web Tournament"]
        XCTAssertTrue(scrollTo(unlink), "Unlink button missing")
        unlink.tap()

        let createButton = app.buttons["Create on Tournament Manager"]
        XCTAssertTrue(scrollTo(createButton), "Create button missing after unlink")
        createButton.tap()
        XCTAssertTrue(app.staticTexts["Setting Up"].waitForExistence(timeout: 15), "Created web tournament not live in detail")
        snap("35_created_from_app")

        // Logout to leave a clean state
        let profileTab = app.tabBars.buttons["Profile"]
        if profileTab.waitForExistence(timeout: 5) {
            profileTab.tap()
            let logoutButton = app.buttons["Logout"]
            if logoutButton.waitForExistence(timeout: 8) { logoutButton.tap() }
        }
    }
}
