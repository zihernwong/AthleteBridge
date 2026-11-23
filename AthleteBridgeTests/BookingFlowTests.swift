import XCTest
import FirebaseFirestore
@testable import AthleteBridge

/// Bookings live in three kinds of copies that both apps read: bookings/{id}, coaches/{coach}/bookings/{id}
/// and clients/{client}/bookings/{id} (one per participant for group sessions). Every change has to reach
/// every copy, or someone sees a stale booking.
@MainActor
final class BookingFlowTests: EmulatorTestCase {

    private var coach: TestUser!
    private var client: TestUser!

    override func setUp() async throws {
        try await super.setUp()
        coach = try await makeUser(.coach, first: "Casey")
        client = try await makeUser(.client, first: "Pat")
    }

    private func copies(_ id: String) -> [String] {
        ["bookings/\(id)", "coaches/\(coach.uid)/bookings/\(id)", "clients/\(client.uid)/bookings/\(id)"]
    }

    /// Requests a session the way the client app does (BookingEditorView → saveBookingAndMirror).
    private func requestSession(start: Date = .inDays(3)) async throws -> String {
        try await signIn(client)
        try await succeed("saveBookingAndMirror") { done in
            fm.saveBookingAndMirror(coachId: coach.uid, clientId: client.uid, startAt: start, endAt: start.addingTimeInterval(3600),
                                    location: "Egret Gym", notes: "Footwork", completion: done)
        }
        let id = try await docs("clients/\(client.uid)/bookings").first?.documentID
        return try XCTUnwrap(id, "booking was not mirrored to the client")
    }

    private func coachView(of id: String) async throws -> FirestoreManager.BookingItem {
        let items: [FirestoreManager.BookingItem] = try await value("fetchBookingsForCoach") { done in
            fm.fetchBookingsForCoach(coachId: coach.uid, completion: done)
        }
        return try XCTUnwrap(items.first { $0.id == id })
    }

    private func clientView(of id: String) async throws -> FirestoreManager.BookingItem {
        let items: [FirestoreManager.BookingItem] = try await value("fetchBookingsForClient") { done in
            fm.fetchBookingsForClient(clientId: client.uid, completion: done)
        }
        return try XCTUnwrap(items.first { $0.id == id })
    }

    func testANewRequestIsCopiedToCoachAndClientInBothCasings() async throws {
        let start = Date.inDays(3)
        let id = try await requestSession(start: start)
        for path in copies(id) {
            let d = try await data(path)
            let booking = try XCTUnwrap(d, path)
            XCTAssertEqual(booking["Status"] as? String, "requested", path)
            XCTAssertEqual(booking["status"] as? String, "requested", path)
            XCTAssertEqual((booking["StartAt"] as? Timestamp)?.dateValue(), start, path)
            XCTAssertEqual((booking["startAt"] as? Timestamp)?.dateValue(), start, path)
            XCTAssertEqual(booking["coachID"] as? String, coach.uid, path)
            XCTAssertEqual(booking["clientID"] as? String, client.uid, path)
            XCTAssertEqual(booking["CoachName"] as? String, "Casey Tester", path)
        }
        let view = try await coachView(of: id)
        XCTAssertEqual(view.location, "Egret Gym")
        XCTAssertEqual(view.notes, "Footwork")
        XCTAssertEqual(view.clientID, client.uid)
    }

    func testTheBookingCarriesTheClientsName() async throws {
        // Client profiles store a single `name` (saveClient), not FirstName/LastName.
        let id = try await requestSession()
        let root = try await data("bookings/\(id)")
        XCTAssertEqual(root?["ClientName"] as? String, "Pat Tester", "the coach's booking list has no client name")
    }

    func testTheCoachIsToldWhoRequestedTheSession() async throws {
        let id = try await requestSession()
        try await eventually("the coach's booking-request push") { try await self.notifications(for: self.coach.uid).count > 0 }
        let push = try await notifications(for: coach.uid)[0]
        XCTAssertEqual(push["bookingId"] as? String, id)
        XCTAssertTrue((push["body"] as? String ?? "").contains("Pat Tester"), "push reads: \(push["body"] ?? "")")
    }

    func testTheBookingRequestPushCarriesARoutableType() async throws {
        _ = try await requestSession()
        try await eventually("the coach's booking-request push") { try await self.notifications(for: self.coach.uid).count > 0 }
        let push = try await notifications(for: coach.uid)[0]
        let type = push["type"] as? String
        XCTAssertTrue(type.map(crossPlatformNotificationTypes.contains) ?? false,
                      "type \(type ?? "nil"): an Android coach tapping this push just lands on the home screen")
    }

    func testStatusRescheduleAndPaymentReachAllThreeCopies() async throws {
        let id = try await requestSession()
        try await signIn(coach)
        try await succeed("updateBookingStatus") { done in fm.updateBookingStatus(bookingId: id, status: "confirmed", completion: done) }
        let newStart = Date.inDays(4, hour: 10)
        try await succeed("rescheduleBooking") { done in
            fm.rescheduleBooking(bookingId: id, newStart: newStart, newEnd: newStart.addingTimeInterval(5400), newStatus: "Pending Acceptance", completion: done)
        }
        try await succeed("updateBookingPaymentStatus") { done in fm.updateBookingPaymentStatus(bookingId: id, paymentStatus: "paid", completion: done) }
        for path in copies(id) {
            let d = try await data(path) ?? [:]
            XCTAssertEqual(d["Status"] as? String, "Pending Acceptance", path)
            XCTAssertEqual(d["status"] as? String, "Pending Acceptance", path)
            XCTAssertEqual((d["startAt"] as? Timestamp)?.dateValue(), newStart, path)
            XCTAssertEqual((d["StartAt"] as? Timestamp)?.dateValue(), newStart, path)
            XCTAssertEqual(d["PaymentStatus"] as? String, "paid", path)
        }
    }

    func testCancellingCompletesAndReachesAllThreeCopies() async throws {
        let id = try await requestSession()
        try await succeed("cancel") { done in fm.updateBookingStatus(bookingId: id, status: "cancelled", completion: done) }
        for path in copies(id) {
            let d = try await data(path)
            XCTAssertEqual(d?["status"] as? String, "cancelled", path)
        }
    }

    func testSessionNotesTheCoachSavesShowUpAgain() async throws {
        let id = try await requestSession()
        try await signIn(coach)
        try await succeed("saveSessionNotes") { done in
            fm.saveSessionNotes(bookingId: id, coachId: coach.uid, clientId: client.uid, notes: "Late split step", completion: done)
        }
        let reloaded = try await coachView(of: id)
        XCTAssertEqual(reloaded.coachNote, "Late split step", "notes are saved as `coachNote` but read back from `CoachNote`")
    }

    func testRecapAndForfeitedDepositReachAllThreeCopies() async throws {
        let id = try await requestSession()
        try await signIn(coach)
        try await succeed("saveSessionRecap") { done in
            fm.saveSessionRecap(bookingId: id, coachId: coach.uid, clientId: client.uid, recap: "Great rallies", completion: done)
        }
        let recapView = try await clientView(of: id)
        XCTAssertEqual(recapView.sessionRecap, "Great rallies")
        fm.markDepositForfeited(bookingId: id, coachId: coach.uid, clientId: client.uid)
        for path in copies(id) {
            try await eventually("depositForfeited on \(path)") { try await self.data(path)?["depositForfeited"] as? Bool == true }
        }
    }

    // MARK: - Bookings created by the Android app

    /// The shape Android's BookingRepository writes for a 1:1 booking, after a coach note and payment.
    private func seedAndroidBooking(_ id: String, start: Date) async throws {
        let fields: [String: Any] = [
            "coachID": coach.uid, "CoachID": coach.uid, "clientID": client.uid,
            "ClientID": db.document("clients/\(client.uid)"),
            "coachName": "Casey Tester", "CoachName": "Casey Tester", "clientName": "Pat Tester", "ClientName": "Pat Tester",
            "startAt": Timestamp(date: start), "StartAt": Timestamp(date: start),
            "endAt": Timestamp(date: start.addingTimeInterval(3600)), "EndAt": Timestamp(date: start.addingTimeInterval(3600)),
            "status": "confirmed", "Status": "confirmed",
            "location": "Egret Gym", "Location": "Egret Gym", "notes": "Bring shuttles", "Notes": "Bring shuttles",
            "paymentStatus": "paid", "PaymentStatus": "paid", "rateUSD": 45, "RateUSD": 45,
            "coachNote": "Work on backhand clears", "creatorType": "client"
        ]
        for path in copies(id) { try await seed(path, fields) }
    }

    func testAnAndroidBookingReadsBackCompletely() async throws {
        try await signIn(coach)
        let id = "android-\(UUID().uuidString.prefix(8))"
        try await seedAndroidBooking(id, start: .inDays(2))
        let b = try await coachView(of: id)
        XCTAssertEqual(b.clientID, client.uid)
        XCTAssertEqual(b.status, "confirmed")
        XCTAssertEqual(b.location, "Egret Gym")
        XCTAssertEqual(b.notes, "Bring shuttles")
        XCTAssertEqual(b.paymentStatus, "paid")
        XCTAssertEqual(b.RateUSD, 45)
        XCTAssertEqual(b.coachNote, "Work on backhand clears", "Android's coach note (coachNote) is invisible on iOS")
    }

    func testIOSStatusChangesReachAnAndroidBookingsCopies() async throws {
        try await signIn(coach)
        let id = "android-\(UUID().uuidString.prefix(8))"
        try await seedAndroidBooking(id, start: .inDays(2))
        try await succeed("cancel") { done in fm.updateBookingStatus(bookingId: id, status: "cancelled", completion: done) }
        for path in copies(id) {
            let d = try await data(path)
            XCTAssertEqual(d?["status"] as? String, "cancelled", path)
            XCTAssertEqual(d?["Status"] as? String, "cancelled", path)
        }
    }

    func testAnAndroidGroupBookingShowsItsNotes() async throws {
        // Android's group-booking write stores notes only as camelCase `notes`.
        try await signIn(client)
        let id = "android-group-\(UUID().uuidString.prefix(6))"
        let start = Date.inDays(5)
        let fields: [String: Any] = [
            "coachID": coach.uid, "coachIDs": [coach.uid], "CoachIDs": [coach.uid], "clientID": client.uid,
            "clientIDs": [client.uid], "ClientIDs": [client.uid], "ClientID": db.document("clients/\(client.uid)"),
            "startAt": Timestamp(date: start), "StartAt": Timestamp(date: start),
            "endAt": Timestamp(date: start.addingTimeInterval(3600)), "EndAt": Timestamp(date: start.addingTimeInterval(3600)),
            "status": "requested", "Status": "requested", "isGroupBooking": true,
            "location": "Egret Gym", "Location": "Egret Gym", "notes": "Doubles rotation drills",
            "creatorID": client.uid, "creatorType": "client"
        ]
        for path in copies(id) { try await seed(path, fields) }
        let b = try await clientView(of: id)
        XCTAssertEqual(b.notes, "Doubles rotation drills")
    }
}

/// Group sessions: two coaches and two clients, each with their own copy.
@MainActor
final class GroupBookingFlowTests: EmulatorTestCase {

    private var coaches: [TestUser] = []
    private var clients: [TestUser] = []

    override func setUp() async throws {
        try await super.setUp()
        coaches = [try await makeUser(.coach, first: "Casey"), try await makeUser(.coach, first: "Morgan")]
        clients = [try await makeUser(.client, first: "Pat"), try await makeUser(.client, first: "Riley")]
    }

    private func copies(_ id: String) -> [String] {
        ["bookings/\(id)"] + coaches.map { "coaches/\($0.uid)/bookings/\(id)" } + clients.map { "clients/\($0.uid)/bookings/\(id)" }
    }

    /// The first client books both coaches for both clients (BookingEditorView → saveGroupBooking).
    private func requestGroupSession(start: Date = .inDays(6)) async throws -> String {
        try await signIn(clients[0])
        try await succeed("saveGroupBooking") { done in
            fm.saveGroupBooking(coachIds: coaches.map(\.uid), clientIds: clients.map(\.uid), startAt: start,
                                endAt: start.addingTimeInterval(5400), location: "Egret Gym", notes: "Doubles",
                                creatorID: clients[0].uid, creatorType: "client", completion: done)
        }
        let id = try await docs("clients/\(clients[0].uid)/bookings").first?.documentID
        return try XCTUnwrap(id)
    }

    private func statuses(_ id: String) async throws -> [String: String] {
        var result: [String: String] = [:]
        for path in copies(id) { result[path] = try await data(path)?["status"] as? String ?? "missing" }
        return result
    }

    private func assertStatuses(_ id: String, _ expected: Set<String>, line: UInt = #line) async throws {
        let current = try await statuses(id)
        XCTAssertEqual(Set(current.values), expected, "\(current)", line: line)
    }

    func testAGroupRequestIsCopiedToEveryParticipant() async throws {
        let id = try await requestGroupSession()
        for path in copies(id) {
            let d = try await data(path)
            let booking = try XCTUnwrap(d, path)
            XCTAssertEqual(booking["CoachIDs"] as? [String], coaches.map(\.uid), path)
            XCTAssertEqual(booking["isGroupBooking"] as? Bool, true, path)
            XCTAssertEqual((booking["coachAcceptances"] as? [String: Bool])?.values.contains(true), false, path)
        }
        let root = try await data("bookings/\(id)")
        XCTAssertEqual(root?["ClientNames"] as? [String], ["Pat Tester", "Riley Tester"])
    }

    func testGroupPushesCarryARoutableType() async throws {
        let id = try await requestGroupSession()
        try await signIn(coaches[0])
        try await succeed("accept") { done in
            fm.acceptGroupBookingAsCoach(bookingId: id, coachId: coaches[0].uid, rateUSD: 40, coachNote: nil, completion: done)
        }
        try await settle()
        var untyped: [String] = []
        for user in coaches + clients {
            for push in try await notifications(for: user.uid) {
                let type = push["type"] as? String
                if !(type.map(crossPlatformNotificationTypes.contains) ?? false) {
                    untyped.append("\(push["title"] ?? "?") → \(user.first) (type \(type ?? "nil"))")
                }
            }
        }
        XCTAssertEqual(untyped, [], "Android users tapping these land on the home screen")
    }

    func testTheSessionWaitsForEveryCoachThenEveryClient() async throws {
        let id = try await requestGroupSession()
        try await signIn(coaches[0])
        try await succeed("first coach accepts") { done in
            fm.acceptGroupBookingAsCoach(bookingId: id, coachId: coaches[0].uid, rateUSD: 40, coachNote: "Bring water", completion: done)
        }
        try await assertStatuses(id,["partially_accepted"])

        try await signIn(coaches[1])
        try await succeed("second coach accepts") { done in
            fm.acceptGroupBookingAsCoach(bookingId: id, coachId: coaches[1].uid, rateUSD: 50, coachNote: nil, completion: done)
        }
        try await assertStatuses(id,["Pending Acceptance"])

        try await signIn(clients[0])
        try await succeed("first client confirms") { done in fm.confirmGroupBookingAsClient(bookingId: id, clientId: clients[0].uid, completion: done) }
        try await assertStatuses(id,["partially_confirmed"])

        try await signIn(clients[1])
        try await succeed("second client confirms") { done in fm.confirmGroupBookingAsClient(bookingId: id, clientId: clients[1].uid, completion: done) }
        try await assertStatuses(id,["confirmed"])
        let rates = try await data("bookings/\(id)")?["coachRates"] as? [String: Double]
        XCTAssertEqual(rates, [coaches[0].uid: 40, coaches[1].uid: 50])
    }

    func testAClientCancellingReachesEveryParticipant() async throws {
        // ClientConfirmedBookingsView.cancelBooking → updateGroupBookingStatus for group sessions
        let id = try await requestGroupSession()
        try await succeed("cancel") { done in fm.updateGroupBookingStatus(bookingId: id, status: "cancelled", completion: done) }
        try await assertStatuses(id,["cancelled"])
    }

    func testACoachCancellingReachesEveryParticipant() async throws {
        // CoachConfirmedBookingsView.cancelBooking always calls updateBookingStatus, even for group sessions
        let id = try await requestGroupSession()
        try await signIn(coaches[0])
        try await succeed("cancel") { done in fm.updateBookingStatus(bookingId: id, status: "cancelled", completion: done) }
        let stale = try await statuses(id).filter { $0.value != "cancelled" }
        XCTAssertEqual(stale, [:], "these participants still see the session as booked")
    }

    func testReschedulingReachesEveryParticipant() async throws {
        // Both confirmed-bookings screens reschedule through rescheduleBooking
        let id = try await requestGroupSession()
        let newStart = Date.inDays(8, hour: 9)
        try await succeed("reschedule") { done in
            fm.rescheduleBooking(bookingId: id, newStart: newStart, newEnd: newStart.addingTimeInterval(5400), newStatus: "requested", completion: done)
        }
        var stale: [String] = []
        for path in copies(id) {
            let start = (try await data(path)?["startAt"] as? Timestamp)?.dateValue()
            if start != newStart { stale.append(path) }
        }
        XCTAssertEqual(stale, [], "these copies still show the old time")
    }

    func testRecapAndForfeitedDepositReachEveryParticipant() async throws {
        let id = try await requestGroupSession()
        try await signIn(coaches[0])
        try await succeed("saveSessionRecap") { done in
            fm.saveSessionRecap(bookingId: id, coachId: coaches[0].uid, clientId: clients[0].uid, recap: "Rotations improved", completion: done)
        }
        fm.markDepositForfeited(bookingId: id, coachId: coaches[0].uid, clientId: clients[0].uid)
        try await settle()
        let other = "clients/\(clients[1].uid)/bookings/\(id)"
        let d = try await data(other)
        XCTAssertEqual(d?["sessionRecap"] as? String, "Rotations improved", "the second client never sees the recap")
        XCTAssertEqual(d?["depositForfeited"] as? Bool, true)
    }
}
