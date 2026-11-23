import XCTest
import FirebaseFirestore
@testable import AthleteBridge

/// Club sign-up events: capacity, waiver, opening time, waitlist and the weekly roll-forward.
@MainActor
final class SignupEventFlowTests: EmulatorTestCase {

    private var organizer: TestUser!
    private var players: [TestUser] = []

    override func setUp() async throws {
        try await super.setUp()
        organizer = try await makeUser(.coach, first: "Olivia")
        players = [try await makeUser(.client, first: "Pat"), try await makeUser(.client, first: "Riley"),
                   try await makeUser(.client, first: "Sam")]
    }

    // MARK: - Helpers

    private func createEvent(max: Int = 2, date: Date = .inDays(5), recurrence: String? = nil, fee: Double? = nil,
                             link: String? = nil, selfReport: Bool = false, opensAt: Date? = nil,
                             notes: String? = nil, waiver: String? = nil) async throws -> String {
        try await signIn(organizer)
        var id: String?
        try await succeed("createSignupEvent") { done in
            id = fm.createSignupEvent(title: "Drop-in", description: "Open play", eventDate: date, location: "Egret Gym",
                                      placeId: "place-\(UUID().uuidString.prefix(8))", placeName: "Egret", maxSignups: max,
                                      recurrence: recurrence, feeUSD: fee, paymentLink: link, allowSelfReportPaid: selfReport,
                                      opensAt: opensAt, notes: notes, waiverText: waiver, completion: done)
        }
        return try XCTUnwrap(id)
    }

    private func signUp(_ player: TestUser, _ eventId: String, acceptWaiver: Bool = false) async throws -> Error? {
        try await signIn(player)
        return try await outcome("signupForEvent") { done in
            fm.signupForEvent(eventId: eventId, acceptedWaiver: acceptWaiver, completion: done)
        }
    }

    private func joinWaitlist(_ player: TestUser, _ eventId: String) async throws {
        try await signIn(player)
        try await succeed("joinEventWaitlist") { done in fm.joinEventWaitlist(eventId: eventId, completion: done) }
    }

    private struct Roster {
        let count: Int
        let signups: [String]     // user ids, one entry per signup
        let waitlist: [String]
        let keys: [String: String] // user id -> signup key
    }

    private func roster(_ id: String) async throws -> Roster {
        let d = try await data("signupEvents/\(id)") ?? [:]
        let raw = d["signups"] as? [String: Any] ?? [:]
        var keys: [String: String] = [:]
        var signups: [String] = []
        for (key, value) in raw {
            guard let uid = (value as? [String: Any])?["userId"] as? String else { continue }
            signups.append(uid)
            keys[uid] = key
        }
        let waitlist = (d["waitlist"] as? [String: Any] ?? [:]).values.compactMap { ($0 as? [String: Any])?["userId"] as? String }
        return Roster(count: d["signupCount"] as? Int ?? -99, signups: signups.sorted(), waitlist: waitlist.sorted(), keys: keys)
    }

    /// Loads the event into the manager's cache (some actions read it from there).
    private func loadEvent(_ id: String, where ready: @escaping (SignupEvent) -> Bool = { _ in true }) async throws -> SignupEvent {
        var found: SignupEvent?
        try await eventually("event \(id) to load") {
            self.fm.fetchSignupEvents()
            try await self.settle(0.4)
            found = self.fm.signupEvents.first { $0.id == id && ready($0) }
            return found != nil
        }
        return try XCTUnwrap(found)
    }

    // MARK: - Creating and signing up

    func testCreatingAnEventStoresItsSettings() async throws {
        let opens = Date.inDays(4, hour: 20)
        let id = try await createEvent(max: 12, recurrence: "weekly", fee: 8, link: "@egretclub", selfReport: true,
                                       opensAt: opens, notes: "Shuttles provided", waiver: "Play at your own risk")
        let stored = try await data("signupEvents/\(id)")
        let d = try XCTUnwrap(stored)
        XCTAssertEqual(d["maxSignups"] as? Int, 12)
        XCTAssertEqual(d["signupCount"] as? Int, 0)
        XCTAssertEqual(d["createdBy"] as? String, organizer.uid)
        XCTAssertEqual(d["timeZone"] as? String, TimeZone.current.identifier)
        XCTAssertEqual(d["recurrence"] as? String, "weekly")
        XCTAssertEqual(d["feeUSD"] as? Double, 8)
        XCTAssertEqual(d["paymentLink"] as? String, "@egretclub")
        XCTAssertEqual(d["allowSelfReportPaid"] as? Bool, true)
        XCTAssertEqual((d["opensAt"] as? Timestamp)?.dateValue(), opens)
        XCTAssertEqual(d["notes"] as? String, "Shuttles provided")
        XCTAssertEqual(d["waiverText"] as? String, "Play at your own risk")
    }

    func testEachPlayerCanSignUpOnce() async throws {
        let id = try await createEvent(max: 4)
        let first = try await signUp(players[0], id)
        XCTAssertNil(first)
        let again = try await signUp(players[0], id)
        XCTAssertNotNil(again, "a second signup by the same player should be refused")
        let r = try await roster(id)
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r.signups, [players[0].uid])
        let entry = try await data("signupEvents/\(id)")?["signups"] as? [String: [String: Any]]
        XCTAssertEqual(entry?.values.first?["name"] as? String, "Pat Tester")
    }

    func testAFullEventTurnsPlayersAway() async throws {
        let id = try await createEvent(max: 1)
        let first = try await signUp(players[0], id)
        XCTAssertNil(first)
        let second = try await signUp(players[1], id)
        XCTAssertEqual((second as NSError?)?.code, 409)
        let r = try await roster(id)
        XCTAssertEqual(r.signups, [players[0].uid])
    }

    func testTheWaiverMustBeAccepted() async throws {
        let id = try await createEvent(max: 4, waiver: "Play at your own risk")
        let refused = try await signUp(players[0], id, acceptWaiver: false)
        XCTAssertNotNil(refused)
        let accepted = try await signUp(players[0], id, acceptWaiver: true)
        XCTAssertNil(accepted)
        let entry = try await data("signupEvents/\(id)")?["signups"] as? [String: [String: Any]]
        XCTAssertNotNil(entry?.values.first?["waiverAcceptedAt"] as? Timestamp)
    }

    func testSignupsOpenOnScheduleExceptForTheOrganizer() async throws {
        let id = try await createEvent(max: 4, opensAt: .inDays(2))
        let early = try await signUp(players[0], id)
        XCTAssertEqual((early as NSError?)?.code, 403)
        try await signIn(organizer)
        let organizerSignup = try await outcome("organizer signup") { done in fm.signupForEvent(eventId: id, completion: done) }
        XCTAssertNil(organizerSignup, "organizers can add themselves before signups open")
    }

    func testRemovingTheSameSignupTwiceDoesNotFreeAnExtraSpot() async throws {
        // e.g. an organizer double-tapping "Remove", or removing a player who just cancelled
        let id = try await createEvent(max: 2)
        _ = try await signUp(players[0], id)
        _ = try await signUp(players[1], id)
        let keys = try await roster(id).keys
        let key = try XCTUnwrap(keys[players[0].uid])
        try await signIn(organizer)
        try await succeed("remove") { done in fm.removeSignupFromEvent(eventId: id, signupId: key, completion: done) }
        _ = try await outcome("remove again") { done in fm.removeSignupFromEvent(eventId: id, signupId: key, completion: done) }
        try await settle()
        let r = try await roster(id)
        XCTAssertEqual(r.count, r.signups.count,
                       "signupCount \(r.count) for \(r.signups.count) signups: the event now accepts one player too many")
    }

    // MARK: - Waitlist

    func testJoiningTheWaitlistTwiceKeepsOneEntry() async throws {
        let id = try await createEvent(max: 1)
        _ = try await signUp(players[0], id)
        try await joinWaitlist(players[1], id)
        try await joinWaitlist(players[1], id)
        let r = try await roster(id)
        XCTAssertEqual(r.waitlist, [players[1].uid])
    }

    func testACancellationPromotesTheFirstWaitlistedPlayer() async throws {
        let id = try await createEvent(max: 1)
        _ = try await signUp(players[0], id)
        try await joinWaitlist(players[1], id)
        try await joinWaitlist(players[2], id)

        try await signIn(players[0])
        let event = try await loadEvent(id) { $0.signups.count == 1 && $0.waitlist.count == 2 }
        try await succeed("cancelMySignup") { done in fm.cancelMySignup(event: event, completion: done) }

        try await eventually("Riley to be promoted") { try await self.roster(id).signups == [self.players[1].uid] }
        let r = try await roster(id)
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r.waitlist, [players[2].uid])
        try await eventually("Riley's push") { try await self.notifications(for: self.players[1].uid).count > 0 }
        let push = try await notifications(for: players[1].uid).first { $0["type"] as? String == "event_waitlist_promoted" }
        XCTAssertEqual(push?["eventId"] as? String, id)
        XCTAssertNotNil(push?["placeId"] as? String)
    }

    func testRaisingCapacityLetsWaitlistedPlayersIn() async throws {
        let id = try await createEvent(max: 1)
        _ = try await signUp(players[0], id)
        try await joinWaitlist(players[1], id)
        try await joinWaitlist(players[2], id)
        try await signIn(organizer)
        try await succeed("updateSignupEventCapacity") { done in fm.updateSignupEventCapacity(eventId: id, newMax: 3, completion: done) }
        try await settle(1.5)
        let r = try await roster(id)
        XCTAssertEqual(r.signups, players.map(\.uid).sorted(), "two spots opened up but the waitlist is still waiting")
        XCTAssertEqual(r.waitlist, [])
        XCTAssertEqual(r.count, 3)
    }

    func testAWaitlistedPlayerWhoGetsInIsCountedOnce() async throws {
        let id = try await createEvent(max: 1)
        _ = try await signUp(players[0], id)
        try await joinWaitlist(players[1], id)
        // The organizer adds a spot, Riley sees it open and signs up directly…
        try await signIn(organizer)
        try await succeed("updateSignupEventCapacity") { done in fm.updateSignupEventCapacity(eventId: id, newMax: 2, completion: done) }
        _ = try await signUp(players[1], id)
        // …then Pat cancels, which promotes the first waitlisted player.
        try await signIn(players[0])
        let event = try await loadEvent(id) { $0.signups.contains { $0.userId == self.players[0].uid } }
        try await succeed("cancelMySignup") { done in fm.cancelMySignup(event: event, completion: done) }
        try await settle(1.5)
        let r = try await roster(id)
        XCTAssertEqual(r.signups.filter { $0 == players[1].uid }.count, 1, "Riley holds \(r.signups.filter { $0 == players[1].uid }.count) spots")
        XCTAssertEqual(r.waitlist, [])
        XCTAssertEqual(r.count, r.signups.count)
    }

    func testPlayersCanMarkThemselvesPaidPendingConfirmation() async throws {
        let id = try await createEvent(max: 4, fee: 8, link: "@egretclub", selfReport: true)
        _ = try await signUp(players[0], id)
        _ = try await loadEvent(id) { $0.signups.contains { $0.userId == self.players[0].uid } }
        try await succeed("selfReportEventPaid") { done in fm.selfReportEventPaid(eventId: id, completion: done) }
        let reported = try await loadEvent(id) { $0.selfReportedCount == 1 }
        XCTAssertEqual(reported.paidCount, 0, "self-reported payments wait for the organizer")

        try await signIn(organizer)
        let signupId = try XCTUnwrap(reported.signups.first?.id)
        fm.toggleSignupPaid(eventId: id, signupId: signupId, paid: true)
        let confirmed = try await loadEvent(id) { $0.paidCount == 1 }
        XCTAssertEqual(confirmed.selfReportedCount, 0)
    }

    // MARK: - Weekly roll-forward

    func testRollingAWeeklyEventKeepsItsLocalTimeAndSettings() async throws {
        // Start three days before this time zone's next daylight-saving change, so next week is on the other side of it.
        let cal = Calendar.current
        let tz = TimeZone.current
        guard var transition = tz.nextDaylightSavingTimeTransition(after: Date()) else {
            throw XCTSkip("\(tz.identifier) has no daylight saving time")
        }
        if transition.timeIntervalSinceNow < 5 * 86_400, let later = tz.nextDaylightSavingTimeTransition(after: transition) {
            transition = later
        }
        let start = cal.date(bySettingHour: 19, minute: 0, second: 0, of: cal.date(byAdding: .day, value: -3, to: transition)!)!
        let opens = cal.date(byAdding: .day, value: -1, to: start)!
        let id = try await createEvent(max: 10, date: start, recurrence: "weekly", fee: 8, link: "@egretclub",
                                       opensAt: opens, notes: "Shuttles provided", waiver: "Play at your own risk")
        let event = try await loadEvent(id)
        try await succeed("createNextOccurrence") { done in fm.createNextOccurrence(of: event, completion: done) }

        var nextId: String?
        try await eventually("the source to link next week's event") {
            nextId = try await self.data("signupEvents/\(id)")?["nextOccurrenceId"] as? String
            return nextId != nil
        }
        let nextPath = "signupEvents/\(try XCTUnwrap(nextId))"
        let stored = try await data(nextPath)
        let next = try XCTUnwrap(stored)
        let nextDate = try XCTUnwrap((next["eventDate"] as? Timestamp)?.dateValue())
        XCTAssertEqual(cal.component(.hour, from: nextDate), 19, "next week's session moved to \(nextDate)")
        XCTAssertEqual(cal.dateComponents([.day], from: start, to: nextDate).day, 7)
        let nextOpens = try XCTUnwrap((next["opensAt"] as? Timestamp)?.dateValue())
        XCTAssertEqual(cal.component(.hour, from: nextOpens), cal.component(.hour, from: opens))
        XCTAssertEqual(next["recurrence"] as? String, "weekly")
        XCTAssertEqual(next["feeUSD"] as? Double, 8)
        XCTAssertEqual(next["paymentLink"] as? String, "@egretclub")
        XCTAssertEqual(next["notes"] as? String, "Shuttles provided")
        XCTAssertEqual(next["waiverText"] as? String, "Play at your own risk")
        XCTAssertEqual(next["maxSignups"] as? Int, 10)
        XCTAssertEqual(next["signupCount"] as? Int, 0)
    }

    func testRollingAnEventTheServerAlreadyRolledDoesNotDuplicateIt() async throws {
        let id = try await createEvent(max: 10, recurrence: "weekly")
        let stale = try await loadEvent(id)
        // The scheduled roll-forward function already created next week and linked it…
        try await db.document("signupEvents/\(id)").updateData(["nextOccurrenceId": "rolled-by-server"])
        // …but this phone's copy of the event list predates that.
        fm.signupEvents = []
        let error = try await outcome("createNextOccurrence") { done in fm.createNextOccurrence(of: stale, completion: done) }
        try await settle()
        let copies = try await docs("signupEvents").filter {
            $0.documentID != id && ($0.data()["placeId"] as? String) == stale.placeId
        }
        XCTAssertNotNil(error, "rolling an already-rolled event should be refused")
        XCTAssertEqual(copies.count, 0, "a second copy of next week's event was created")
    }
}
