import XCTest

final class ScreenshotTests: XCTestCase {

    var app: XCUIApplication!
    let screenshotDir = "/Users/hernwong/Desktop/AthleteBridgeScreenshots"

    // Test account credentials
    let testEmail    = "client@gmail.com"
    let testPassword = "Hercia12"

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

    private func loginIfNeeded() {
        // If login screen is showing, sign in
        let emailField = app.textFields["Email"]
        guard emailField.waitForExistence(timeout: 5) else { return }

        emailField.tap()
        emailField.typeText(testEmail)

        let passwordField = app.secureTextFields["Password"]
        if passwordField.waitForExistence(timeout: 3) {
            passwordField.tap()
            passwordField.typeText(testPassword)
        }

        let loginButton = app.buttons["Login"]
        if loginButton.waitForExistence(timeout: 3) {
            loginButton.tap()
        }

        // Wait for home screen to appear after login
        let homeTab = app.tabBars.buttons["Home"]
        _ = homeTab.waitForExistence(timeout: 15)
        sleep(3)
    }

    private func snap(_ name: String) {
        app.swipeDown(velocity: .slow)
        app.swipeUp(velocity: .slow)
        sleep(2)
        let screenshot = XCUIScreen.main.screenshot()
        let url = URL(fileURLWithPath: "\(screenshotDir)/\(name).png")
        try? screenshot.pngRepresentation.write(to: url)
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        print("📸 Saved: \(name)")
    }

    // MARK: - Test

    @MainActor
    func testTakeAppStoreScreenshots() throws {
        sleep(3)

        // Log in if session is not persisted (e.g. fresh iPad simulator)
        loginIfNeeded()

        // ── Screenshot 1: Home ──────────────────────────────────────────
        let homeTab = app.tabBars.buttons["Home"]
        if homeTab.waitForExistence(timeout: 5) { homeTab.tap() }
        snap("01_home")

        // ── Screenshot 2: Messages ──────────────────────────────────────
        let messagesTab = app.tabBars.buttons["Messages"]
        if messagesTab.waitForExistence(timeout: 3) { messagesTab.tap() }
        snap("02_messages")

        // ── Screenshot 3: Bookings ──────────────────────────────────────
        let bookingsTab = app.tabBars.buttons["Bookings"]
        if bookingsTab.waitForExistence(timeout: 3) { bookingsTab.tap() }
        snap("03_bookings")

        // ── Screenshot 4: Payments ──────────────────────────────────────
        let paymentsTab = app.tabBars.buttons["Payments"]
        if paymentsTab.waitForExistence(timeout: 3) { paymentsTab.tap() }
        snap("04_payments")

        // ── Screenshot 5: Profile ───────────────────────────────────────
        let profileTab = app.tabBars.buttons["Profile"]
        if profileTab.waitForExistence(timeout: 3) { profileTab.tap() }
        snap("05_profile")
    }
}
