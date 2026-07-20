import XCTest

/// Tournament + auth flows driven with the shared test accounts.
/// Runs alphabetically: forgot-password → client partner flow → coach recommend.
/// Assumes a tournament named "UI Test Open (temporary)" exists with the coach
/// account already in its partner pool.
final class TournamentFlowTests: XCTestCase {

    var app: XCUIApplication!
    let screenshotDir = "/private/tmp/claude-501/-Users-hernwong-Documents-AthleteBridge/2abfbb42-2cc2-4179-97f9-5607441c9721/scratchpad"

    let clientEmail = "client@gmail.com"
    let coachEmail  = "coach@gmail.com"
    let password    = "Hercia12"
    let coachName   = "Coach Coach"
    let clientName  = "Lin Dan"

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

    // MARK: - Helpers

    private func loginIfNeeded(email: String, pass: String) {
        let emailField = app.textFields["Email"]
        guard emailField.waitForExistence(timeout: 5) else { return }

        emailField.tap()
        emailField.typeText(email)

        let passwordField = app.secureTextFields["Password"]
        if passwordField.waitForExistence(timeout: 3) {
            passwordField.tap()
            passwordField.typeText(pass)
        }

        let loginButton = app.buttons["Login"]
        if loginButton.waitForExistence(timeout: 3) {
            loginButton.tap()
        }

        let homeTab = app.tabBars.buttons["Home"]
        XCTAssertTrue(homeTab.waitForExistence(timeout: 20), "Login as \(email) failed")
        sleep(3)

        // Dismiss the in-app "Sessions to Log" reminder sheet if it appears
        dismissSessionsSheet()
    }

    private func logout() {
        let profileTab = app.tabBars.buttons["Profile"]
        guard profileTab.waitForExistence(timeout: 5) else { return }
        profileTab.tap()
        let logoutButton = app.buttons["Logout"]
        if logoutButton.waitForExistence(timeout: 8) {
            logoutButton.tap()
            _ = app.textFields["Email"].waitForExistence(timeout: 10)
        }
    }

    private func dismissSessionsSheet() {
        let laterButton = app.buttons["Later"]
        if laterButton.waitForExistence(timeout: 3) {
            laterButton.tap()
            sleep(1)
        }
    }

    /// A failed earlier test can leave a session behind — always start clean.
    private func ensureLoggedOut() {
        if !app.textFields["Email"].waitForExistence(timeout: 5) {
            dismissSessionsSheet()
            logout()
        }
        XCTAssertTrue(app.textFields["Email"].waitForExistence(timeout: 10), "Couldn't reach the login screen")
    }

    private func snap(_ name: String) {
        sleep(1)
        let screenshot = XCUIScreen.main.screenshot()
        let url = URL(fileURLWithPath: "\(screenshotDir)/\(name).png")
        try? screenshot.pngRepresentation.write(to: url)
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        print("📸 Saved: \(name)")
    }

    private func tapLabel(_ label: String, timeout: TimeInterval = 5) -> Bool {
        for _ in 0..<5 {
            // The "Sessions to Log" sheet can re-present when bookings load
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

    private func openTestTournamentDetail() {
        let homeTab = app.tabBars.buttons["Home"]
        if homeTab.waitForExistence(timeout: 5) { homeTab.tap() }
        XCTAssertTrue(tapLabel("Find Upcoming Tournaments"), "Couldn't find the tournaments entry on Home")
        XCTAssertTrue(app.navigationBars["Upcoming Tournaments"].waitForExistence(timeout: 8))
        sleep(2)
        let row = app.staticTexts["UI Test Open (temporary)"]
        XCTAssertTrue(row.waitForExistence(timeout: 8), "Test tournament not in list")
        row.tap()
        XCTAssertTrue(app.navigationBars["Tournament"].waitForExistence(timeout: 8), "Detail screen didn't appear")
        sleep(1)
    }

    // MARK: - Tests (alphabetical order matters)

    @MainActor
    func testA_forgotPassword() throws {
        sleep(3)
        ensureLoggedOut()
        let emailField = app.textFields["Email"]

        emailField.tap()
        emailField.typeText(clientEmail)

        let forgotButton = app.buttons["Forgot your password?"]
        XCTAssertTrue(forgotButton.waitForExistence(timeout: 5), "Forgot password button missing")
        forgotButton.tap()

        let alert = app.alerts["Password Reset Email Sent"]
        XCTAssertTrue(alert.waitForExistence(timeout: 15), "Reset confirmation alert didn't appear")
        snap("20_forgot_password")
        alert.buttons["OK"].tap()
    }

    @MainActor
    func testB_clientPartnerFlow() throws {
        sleep(3)
        ensureLoggedOut()
        loginIfNeeded(email: clientEmail, pass: password)

        let homeTab = app.tabBars.buttons["Home"]
        if homeTab.waitForExistence(timeout: 5) { homeTab.tap() }
        XCTAssertTrue(tapLabel("Find Upcoming Tournaments"), "Couldn't find the tournaments entry on Home")
        XCTAssertTrue(app.navigationBars["Upcoming Tournaments"].waitForExistence(timeout: 8))
        sleep(2)

        // Coach is already in the pool, so the cross-link should count 1 seeker
        XCTAssertTrue(app.staticTexts["1 player looking for a partner"].waitForExistence(timeout: 8), "Seeker count line missing/wrong")
        snap("21_client_upcoming_list")

        app.staticTexts["UI Test Open (temporary)"].tap()
        XCTAssertTrue(app.navigationBars["Tournament"].waitForExistence(timeout: 8))

        // Coach participant must be listed by name on the detail screen
        XCTAssertTrue(app.staticTexts[coachName].waitForExistence(timeout: 8), "Coach seeker not named on detail screen")
        snap("22_client_detail_with_seeker")

        // Join partner search with compatible preferences (or verify an
        // earlier run's membership is still reflected)
        let partnerLinkLabel = app.buttons["Find a Partner"].exists ? "Find a Partner" : "Manage Partner Search"
        XCTAssertTrue(tapLabel(partnerLinkLabel), "Partner search link missing")
        XCTAssertTrue(app.navigationBars["Find a Tournament Partner"].waitForExistence(timeout: 8))
        let joinButton = app.buttons["I'm Looking for a Partner"]
        if joinButton.waitForExistence(timeout: 5) {
            let eventChip = app.buttons["Men's Doubles"].firstMatch
            XCTAssertTrue(eventChip.waitForExistence(timeout: 5))
            eventChip.tap()
            joinButton.tap()
        }
        XCTAssertTrue(app.staticTexts["You are looking for a partner"].waitForExistence(timeout: 15), "Join didn't reflect in UI")

        // The coach must now appear under Partners Looking to Play.
        // The Form is lazy, so scroll until the row materializes.
        var coachRowFound = false
        for _ in 0..<5 {
            if app.staticTexts[coachName].waitForExistence(timeout: 3) {
                coachRowFound = true
                break
            }
            app.swipeUp(velocity: .fast)
        }
        XCTAssertTrue(coachRowFound, "Coach not shown as compatible partner")
        snap("23_client_partner_list_with_coach")

        logout()
    }

    @MainActor
    func testC_coachRecommendFlow() throws {
        sleep(3)
        ensureLoggedOut()
        loginIfNeeded(email: coachEmail, pass: password)
        openTestTournamentDetail()

        // Client who joined in testB should be listed
        XCTAssertTrue(app.staticTexts[clientName].waitForExistence(timeout: 8), "Client seeker not listed for coach")

        XCTAssertTrue(tapLabel("Recommend to My Clients"), "Recommend button missing")
        let confirm = app.alerts["Recommend this tournament?"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 8), "Confirmation alert missing")
        snap("24_coach_recommend_confirm")
        confirm.buttons["Send"].tap()

        let result = app.alerts.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Recommended'")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 15), "Recommend result alert missing")
        snap("25_coach_recommend_result")
        app.alerts.buttons["OK"].tap()

        logout()
    }
}
