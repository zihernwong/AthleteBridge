import XCTest
import FirebaseFirestore
@testable import AthleteBridge

// Pure logic: no Firebase traffic. Tests that fail document a bug in the app code.

// MARK: - Signup event payments

final class SignupEventPaymentTests: XCTestCase {

    private func event(link: String?, fee: Double?, title: String = "Tuesday Badminton") -> SignupEvent {
        SignupEvent(id: "e1", title: title, description: "", eventDate: Date().addingTimeInterval(86_400),
                    location: "Gym", placeId: "p1", placeName: "Egret", maxSignups: 12, signupCount: 0,
                    createdBy: "org", signups: [], feeUSD: fee, paymentLink: link)
    }

    func testVenmoHandleIsReadFromHandlesAndProfileLinks() {
        XCTAssertEqual(SignupEvent.venmoHandle(from: "@coachkim"), "coachkim")
        XCTAssertEqual(SignupEvent.venmoHandle(from: "venmo.com/coachkim"), "coachkim")
        XCTAssertEqual(SignupEvent.venmoHandle(from: "https://venmo.com/u/coachkim"), "coachkim")
        XCTAssertEqual(SignupEvent.venmoHandle(from: "https://account.venmo.com/u/coachkim?txn=pay"), "coachkim")
        XCTAssertNil(SignupEvent.venmoHandle(from: "https://venmo.com/"))
        XCTAssertNil(SignupEvent.venmoHandle(from: "https://buy.stripe.com/abc123"))
    }

    func testABareAtSignIsNotAVenmoHandle() {
        XCTAssertNil(SignupEvent.venmoHandle(from: "@"), "an organizer typing just '@' would send payers to venmo.com/")
        XCTAssertNil(event(link: "@", fee: 8).resolvedPaymentURL)
        XCTAssertNil(event(link: "@", fee: nil).resolvedPaymentURL)
    }

    func testVenmoQRCodeLinksAreNotTreatedAsAHandleNamedCode() {
        // The link Venmo's "Share my QR code" produces
        XCTAssertNil(SignupEvent.venmoHandle(from: "https://venmo.com/code?user_id=1234567890"),
                     "payers would be sent to the Venmo user 'code'")
    }

    func testVenmoHandleWithFeePrefillsAmountAndNote() throws {
        let url = try XCTUnwrap(event(link: "@coachkim", fee: 12).resolvedPaymentURL)
        let comps = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(comps.host, "venmo.com")
        XCTAssertEqual(comps.path, "/coachkim")
        let items = Dictionary(uniqueKeysWithValues: (comps.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["txn"], "pay")
        XCTAssertEqual(items["amount"], "12.00")
        XCTAssertEqual(items["note"], "Tuesday Badminton")
    }

    func testVenmoHandleWithoutAFeeOpensTheVenmoProfile() {
        let url = event(link: "@coachkim", fee: nil).resolvedPaymentURL
        XCTAssertEqual(url?.host, "venmo.com", "a free event's '@handle' link resolves to \(url?.absoluteString ?? "nil")")
        XCTAssertTrue(url?.absoluteString.hasSuffix("coachkim") ?? false)
    }

    func testOtherPaymentLinksOpenUnchanged() {
        XCTAssertEqual(event(link: "https://buy.stripe.com/abc123", fee: 15).resolvedPaymentURL?.absoluteString, "https://buy.stripe.com/abc123")
        XCTAssertEqual(event(link: "paypal.me/egretclub", fee: 15).resolvedPaymentURL?.absoluteString, "https://paypal.me/egretclub")
        XCTAssertNil(event(link: "   ", fee: 15).resolvedPaymentURL)
    }

    func testShareCaptionListsFeeSpotsAndLink() {
        var e = event(link: nil, fee: 8)
        e.opensHoursBefore = nil
        let caption = e.shareCaption
        XCTAssertTrue(caption.contains("$8.00 per player"))
        XCTAssertTrue(caption.contains("12 of 12 spots left"))
        XCTAssertTrue(caption.contains("https://athletesbridge.com/signup/?event=e1"))
        XCTAssertFalse(caption.contains("Sign-ups open"), "already open, so no opening line")
    }
}

// MARK: - Signup event opening time, capacity, waitlist

final class SignupEventStateTests: XCTestCase {

    private func event(date: Date, max: Int = 4, count: Int = 0) -> SignupEvent {
        SignupEvent(id: "e1", title: "Drop-in", description: "", eventDate: date, location: "", placeId: "p1",
                    placeName: "", maxSignups: max, signupCount: count, createdBy: "org", signups: [])
    }

    func testOpeningTimeComesFromTheExactTimeOrHoursBefore() {
        let start = Date().addingTimeInterval(48 * 3600)
        var e = event(date: start)
        XCTAssertNil(e.opensAt)
        XCTAssertTrue(e.isSignupOpen)

        e.opensHoursBefore = 24
        XCTAssertEqual(e.opensAt, start.addingTimeInterval(-24 * 3600))
        XCTAssertFalse(e.isSignupOpen)

        let exact = Date().addingTimeInterval(-60)
        e.customOpensAt = exact
        XCTAssertEqual(e.opensAt, exact, "an exact opening time wins over hours-before")
        XCTAssertTrue(e.isSignupOpen)
    }

    func testCapacityNeverGoesNegative() {
        XCTAssertEqual(event(date: Date(), max: 4, count: 6).spotsRemaining, 0)
        XCTAssertTrue(event(date: Date(), max: 4, count: 4).isFull)
        XCTAssertFalse(event(date: Date(), max: 4, count: 3).isFull)
    }

    func testWaitlistPositionIsFirstComeFirstServed() {
        var e = event(date: Date())
        let t0 = Date()
        e.waitlist = [
            SignupEventSignup(id: "b", name: "B", email: "", userId: "u2", signedUpAt: t0.addingTimeInterval(60), paid: false),
            SignupEventSignup(id: "a", name: "A", email: "", userId: "u1", signedUpAt: t0, paid: false)
        ]
        XCTAssertEqual(e.waitlistPosition(userId: "u1"), 1)
        XCTAssertEqual(e.waitlistPosition(userId: "u2"), 2)
        XCTAssertNil(e.waitlistPosition(userId: "u3"))
        XCTAssertTrue(e.isWaitlisted(userId: "u2"))
    }

    func testWaiverIsRequiredOnlyWhenItHasText() {
        var e = event(date: Date())
        e.waiverText = "  \n "
        XCTAssertFalse(e.requiresWaiver)
        e.waiverText = SignupEvent.defaultWaiver(placeName: "Egret")
        XCTAssertTrue(e.requiresWaiver)
        XCTAssertTrue(e.waiverText!.contains("Egret, its organizers"))
    }
}

// MARK: - Coach model and tiers

final class CoachTierTests: XCTestCase {

    func testLifetimeTierWinsOverALowerSubscription() {
        XCTAssertEqual(CoachTier.effectiveTier(from: ["subscriptionTier": "free", "lifetimeTier": "pro"]), .pro)
        XCTAssertEqual(CoachTier.effectiveTier(from: ["subscriptionTier": "pro", "lifetimeTier": "plus"]), .pro)
        XCTAssertEqual(CoachTier.effectiveTier(from: [:]), .free)
        XCTAssertEqual(CoachTier.effectiveTier(from: ["subscriptionTier": "gold"]), .free)
    }

    func testFreeCoachesAreLockedOutOfPremiumFeatures() {
        for feature in ["paymentSummary", "earningsForecaster", "metricHistory", "recommendToClients"] {
            XCTAssertFalse(CoachTier.free.hasAccess(to: feature), feature)
            XCTAssertTrue(CoachTier.plus.hasAccess(to: feature), feature)
        }
        XCTAssertTrue(CoachTier.free.hasAccess(to: "messaging"))
    }

    func testCoachRateRangeIsNormalized() {
        let coach = Coach(name: " Kim ", specialties: [], experienceYears: -2, availability: [], hourlyRate: -5, rateRange: [80, -10])
        XCTAssertEqual(coach.name, "Kim")
        XCTAssertEqual(coach.experienceYears, 0)
        XCTAssertEqual(coach.hourlyRate, 0)
        XCTAssertEqual(coach.rateRange, [0, 80])
        XCTAssertEqual(coach.minimumRate, 0)
        XCTAssertEqual(coach.maximumRate, 80)
    }
}

// MARK: - Stringing order timeline

final class StringerOrderTimelineTests: XCTestCase {

    private func order(_ status: String) -> StringerOrder {
        StringerOrder(id: "o", stringerId: "s", racketName: "Astrox 88D", hasOwnString: true, selectedString: nil,
                      stringCost: nil, laborCost: "$15", orderTotal: "$15.00", tension: 26, timelinePreference: "ASAP",
                      createdBy: "buyer", createdAt: Date(timeIntervalSince1970: 1_000), status: status, buyerName: "Pat")
    }

    func testStagesUpToTheCurrentStatusAreReached() {
        let o = order("stringing")
        XCTAssertTrue(o.isStageReached("placed"))
        XCTAssertTrue(o.isStageReached("accepted"))
        XCTAssertTrue(o.isStageReached("stringing"))
        XCTAssertFalse(o.isStageReached("ready_for_pickup"))
        XCTAssertTrue(order("completed").isStageReached("picked_up"), "legacy 'completed' orders show every stage")
        XCTAssertFalse(order("declined").isStageReached("placed"))
        XCTAssertEqual(o.stageTimestamp("placed"), Date(timeIntervalSince1970: 1_000), "placed falls back to createdAt")
    }
}

// MARK: - Tournament partner matching

@MainActor
final class PartnerCompatibilityTests: XCTestCase {

    private func player(_ gender: String, _ events: [String], _ skills: [String] = []) -> TournamentParticipantInfo {
        TournamentParticipantInfo(gender: gender, events: events, skillLevels: skills)
    }

    private func compatible(_ a: TournamentParticipantInfo, _ b: TournamentParticipantInfo) -> Bool {
        FirestoreManager.partnersCompatible(gender: a.gender, events: Set(a.events), skillLevels: Set(a.skillLevels), with: b)
    }

    func testGenderRulesPerEvent() {
        XCTAssertTrue(compatible(player("Male", ["Men's Doubles"]), player("Male", ["Men's Doubles"])))
        XCTAssertFalse(compatible(player("Male", ["Men's Doubles"]), player("Female", ["Men's Doubles"])))
        XCTAssertTrue(compatible(player("Female", ["Women's Doubles"]), player("Female", ["Women's Doubles"])))
        XCTAssertTrue(compatible(player("Male", ["Mixed Doubles"]), player("Female", ["Mixed Doubles"])))
        XCTAssertFalse(compatible(player("Male", ["Mixed Doubles"]), player("Male", ["Mixed Doubles"])))
    }

    func testEventsAndSkillLevelsMustOverlap() {
        XCTAssertFalse(compatible(player("Male", ["Men's Doubles"]), player("Male", ["Mixed Doubles"])))
        XCTAssertFalse(compatible(player("Male", ["Men's Doubles"], ["A"]), player("Male", ["Men's Doubles"], ["C"])))
        XCTAssertTrue(compatible(player("Male", ["Men's Doubles"], ["A", "B"]), player("Male", ["Men's Doubles"], ["B"])))
        XCTAssertTrue(compatible(player("Male", ["Men's Doubles"]), player("Male", ["Men's Doubles"], ["C"])), "no skill filter = any level")
    }

    func testMatchingIsSymmetric() {
        let pairs: [(TournamentParticipantInfo, TournamentParticipantInfo)] = [
            (player("Male", ["Mixed Doubles", "Men's Doubles"], ["B"]), player("Female", ["Mixed Doubles"], ["B"])),
            (player("Female", ["Women's Doubles"], ["A"]), player("Male", ["Women's Doubles", "Mixed Doubles"], ["A"]))
        ]
        for (a, b) in pairs { XCTAssertEqual(compatible(a, b), compatible(b, a)) }
    }
}

// MARK: - No-show records

@MainActor
final class NoShowRecordTests: XCTestCase {

    func testRecordIdsUseClubYearAndNormalizedKeys() {
        let date = Date(timeIntervalSince1970: 1_781_000_000) // mid 2026
        let ids = FirestoreManager.noShowRecordIds(event: ["placeId": "p1", "eventDate": Timestamp(date: date), "timeZone": "America/Chicago"],
                                                   userId: "uid/1", email: "  Pat@Example.COM ")
        XCTAssertEqual(ids, ["p1__2026__u_uid_1", "p1__2026__e_pat@example.com"])
    }

    func testTheYearIsTheClubsLocalYear() {
        // 2026-01-01 03:00 UTC is still New Year's Eve 2025 in Minneapolis
        let date = ISO8601DateFormatter().date(from: "2026-01-01T03:00:00Z")!
        let ids = FirestoreManager.noShowRecordIds(event: ["placeId": "p1", "eventDate": Timestamp(date: date), "timeZone": "America/Chicago"],
                                                   userId: "u1", email: nil)
        XCTAssertEqual(ids, ["p1__2025__u_u1"])
        XCTAssertEqual(FirestoreManager.noShowRecordIds(event: [:], userId: nil, email: nil), [])
    }
}

// MARK: - Push notification taps (iOS routing)

final class NotificationTapRoutingTests: XCTestCase {

    private func route(_ info: [AnyHashable: Any]) -> DeepLinkDestination? {
        NotificationManager.destination(for: info)?.destination
    }

    func testChatBookingStringingAndClubPushesOpenTheirScreens() {
        XCTAssertEqual(route(["chatId": "a_b", "bookingId": "b1"]), .chat(chatId: "a_b"), "chat wins")
        XCTAssertEqual(route(["bookingId": "b1", "type": "booking_confirmed"]), .booking(bookingId: "b1"))
        XCTAssertEqual(NotificationManager.destination(for: ["bookingId": "b1", "type": "booking_confirmed"])?.bookingType, "booking_confirmed")
        XCTAssertEqual(route(["bookingId": "b1"]), .booking(bookingId: "b1"), "booking pushes without a type still open the booking")
        XCTAssertEqual(route(["bookingId": "b1", "type": "payment_reminder"]), .payments)
        XCTAssertEqual(route(["bookingId": "b1", "type": "session_reminder"]), .booking(bookingId: "b1"))
        XCTAssertEqual(route(["stringerOrderId": "o1", "type": "stringer_order"]), .stringing(orderId: "o1"))
        XCTAssertEqual(route(["type": "club_join_request", "placeId": "p1"]), .clubJoinRequest(placeId: "p1"))
        XCTAssertEqual(route(["type": "club_approved", "placeId": "p1"]), .clubMembers(placeId: "p1"))
        XCTAssertEqual(route(["type": "club_announcement", "placeId": "p1", "announcementId": "a1"]),
                       .clubAnnouncement(placeId: "p1", announcementId: "a1"))
        XCTAssertNil(route(["title": "hello"]))
    }

    func testWaitlistPromotionOpensTheEvent() {
        // FirestoreManager.promoteFromWaitlist sends this to the player who got the spot
        XCTAssertEqual(route(["type": "event_waitlist_promoted", "placeId": "p1", "eventId": "e1"]),
                       .signupEvent(placeId: "p1", eventId: "e1"),
                       "tapping 'You're in!' should open the event's club, not just the app")
    }

    func testTournamentPushesOpenTournaments() {
        // Sent by notifyCompatiblePartnerSeekers and recommendTournamentToClients
        XCTAssertEqual(route(["type": "tournament_partner", "tournamentId": "t1"]), .tournaments)
        XCTAssertEqual(route(["type": "tournament_recommendation", "tournamentId": "t1"]), .tournaments)
    }
}

// MARK: - Coach payment links (Payments tab and booking detail)

@MainActor
final class CoachPaymentLinkTests: XCTestCase {

    /// The same helper is copy-pasted in the Payments tab and the coach payment sheet that booking
    /// detail opens; check both.
    private var linkers: [(String, (String, String) -> URL?)] {
        let payments = PaymentsView()
        let sheet = CoachPaymentMethodsSheet(coachName: "Casey", payments: [:])
        return [("PaymentsView", { payments.paymentDeepLink(for: $0, value: $1) }),
                ("CoachPaymentMethodsSheet", { sheet.paymentDeepLink(for: $0, value: $1) })]
    }

    private func check(_ platform: String, _ handle: String, _ expected: String?, _ why: String = "", line: UInt = #line) {
        for (screen, link) in linkers {
            XCTAssertEqual(link(platform, handle)?.absoluteString, expected, "\(screen): \(platform) '\(handle)' \(why)", line: line)
        }
    }

    func testPlainHandlesBuildProfileLinks() {
        check("venmo", "@coachkim", "https://venmo.com/u/coachkim")
        check("Venmo", "  coachkim ", "https://venmo.com/u/coachkim")
        check("paypal", "CoachKim", "https://paypal.me/CoachKim")
        check("cashapp", "$coachkim", "https://cash.app/$coachkim")
        check("zelle", "555-123-4567", nil)
        check("venmo", "   ", nil)
    }

    func testPastedVenmoProfileLinksAreNotDoubled() {
        check("venmo", "https://venmo.com/u/coachkim", "https://venmo.com/u/coachkim")
        check("venmo", "venmo.com/coachkim", "https://venmo.com/u/coachkim")
    }

    func testPastedPayPalMeLinksAreNotDoubled() {
        check("paypal", "paypal.me/coachkim", "https://paypal.me/coachkim")
        check("paypal", "https://www.paypal.com/paypalme/coachkim", "https://paypal.me/coachkim")
    }

    func testPayPalEmailsDoNotBecomePayPalMeLinks() {
        // Coaches commonly save the email they receive PayPal at; paypal.me/<email> is a dead page.
        for (screen, link) in linkers {
            let url = link("paypal", "coach.kim@example.com")?.absoluteString ?? ""
            XCTAssertFalse(url.hasPrefix("https://paypal.me/"), "\(screen) builds \(url)")
        }
    }

    func testCashAppHandlesWithoutTheDollarSign() {
        check("cashapp", "coachkim", "https://cash.app/$coachkim", "(cash.app/<name> without '$' is not a payment page)")
    }
}

// MARK: - Session logs and metric charts

@MainActor
final class SessionLogParsingTests: XCTestCase {

    func testMetricValuesParseTimesAndPlainNumbers() {
        XCTAssertEqual(MetricTrendChart.parseValue("8:00"), 480)
        XCTAssertEqual(MetricTrendChart.parseValue("1:02:30"), 3750)
        XCTAssertEqual(MetricTrendChart.parseValue(" 8.5 "), 8.5)
        XCTAssertEqual(MetricTrendChart.parseValue("$25"), 25)
        XCTAssertEqual(MetricTrendChart.parseValue("12 reps"), 12)
        XCTAssertNil(MetricTrendChart.parseValue("great footwork"))
        XCTAssertNil(MetricTrendChart.parseValue("1:xx"))
    }

    func testThousandsSeparatorsAreNotDecimals() {
        XCTAssertEqual(MetricTrendChart.parseValue("1,500 m"), 1500, "a 1,500 m run is charted as 1.5")
    }

    func testSetsAndRepsAreNotReadAsOneNumber() {
        XCTAssertNil(MetricTrendChart.parseValue("3x10"), "charted as 310")
        XCTAssertNil(MetricTrendChart.parseValue("2 sets of 15"), "charted as 215")
    }

    func testBulletOnlyFieldsCountAsEmpty() {
        XCTAssertEqual(SessionLogEditorView.cleanBulletText("•\n  • \n"), "")
        XCTAssertEqual(SessionLogEditorView.cleanBulletText("• Split step\n•\n• Net kills"), "• Split step\n• Net kills")
    }
}

// MARK: - Weekly booking series (BookingEditorView "Repeat weekly")

@MainActor
final class WeeklyBookingSeriesTests: XCTestCase {

    func testEveryWeekKeepsTheSameLocalTimeAcrossDaylightSaving() throws {
        // Start three days before this time zone's next daylight-saving change, so the series crosses it.
        let cal = Calendar.current
        let tz = TimeZone.current
        guard var transition = tz.nextDaylightSavingTimeTransition(after: Date()) else {
            throw XCTSkip("\(tz.identifier) has no daylight saving time")
        }
        if transition.timeIntervalSinceNow < 5 * 86_400, let later = tz.nextDaylightSavingTimeTransition(after: transition) {
            transition = later
        }
        let start = cal.date(bySettingHour: 18, minute: 0, second: 0, of: cal.date(byAdding: .day, value: -3, to: transition)!)!
        let series = BookingEditorView.weeklySeries(start: start, end: start.addingTimeInterval(3600), weeks: 3)
        XCTAssertEqual(series.count, 3)
        for (week, session) in series.enumerated() {
            XCTAssertEqual(cal.component(.hour, from: session.start), 18, "week \(week + 1) is booked for \(session.start)")
            XCTAssertEqual(cal.dateComponents([.minute], from: session.start, to: session.end).minute, 60)
        }
    }
}
