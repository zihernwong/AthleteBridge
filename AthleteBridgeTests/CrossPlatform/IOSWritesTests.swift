import XCTest
import FirebaseAuth
import FirebaseFirestore
@testable import AthleteBridge

/// Runs each contract story through the iOS app's real code (the FirestoreManager calls each screen makes) and
/// records what lands in the emulator at every checkpoint. The Android tests read and act on these recordings
/// (cross-platform/fixtures/ios). A failure here means iOS now writes something different from what Android was
/// last checked against: run cross-platform/check.sh --record to re-record and re-check both apps.
///
/// Steps iOS writes from SwiftUI views rather than FirestoreManager can't be recorded and are left out:
/// accepting a 1:1 booking (AcceptBookingView) is the one the contract has.
@MainActor
final class IOSWritesTests: CrossPlatformTestCase {

    private func startRecording(_ story: String) async throws -> (Recorder, Story) {
        try await resetWorld()
        let recorder = Recorder(story)
        for a in Actors.keys {
            recorder.register(Actors.uid(a), a)
            recorder.register(Actors.email(a), "\(a)-email")
        }
        return (recorder, Story(story))
    }

    /// userType and profile documents as iOS sign-up and the profile editors write them.
    private func setUpActors(_ actors: String...) async throws {
        try await Auth.auth().signIn(withEmail: Actors.email(actors[0]), password: Actors.password)
        for a in actors {
            try await db.document("userType/\(uid(a))").setData(["type": Actors.role(a)])
            if Actors.role(a) == "COACH" {
                try await succeed("saveCoachWithSchema") { done in
                    fm.saveCoachWithSchema(id: uid(a), firstName: Actors.first(a), lastName: Actors.last(a), specialties: ["Badminton"],
                                           availability: [], experienceYears: 0, hourlyRate: nil, photoURL: nil, completion: done)
                }
            } else {
                try await succeed("saveClient") { done in
                    fm.saveClient(id: uid(a), name: Actors.name(a), goals: [], preferredAvailability: [], photoURL: nil, completion: done)
                }
            }
        }
        try Auth.auth().signOut()
    }

    /// Lets fire-and-forget writes (pushes, mirrors) land, then records the checkpoint.
    private func checkpoint(_ r: Recorder, _ name: String, settle seconds: Double = 1.0) async throws {
        try await settle(seconds)
        try await r.checkpoint(name)
    }

    private func loadClub(_ id: String, where ready: @escaping (PlaceToPlay) -> Bool = { _ in true }) async throws {
        fm.fetchPlacesToPlay()
        try await eventually("club \(id) to load") { self.fm.placesToPlay.contains { $0.id == id && ready($0) } }
    }

    private func loadEvent(_ id: String) async throws -> SignupEvent {
        var found: SignupEvent?
        try await eventually("event \(id) to load") {
            self.fm.fetchSignupEvents()
            try await self.settle(0.4)
            found = self.fm.signupEvents.first { $0.id == id }
            return found != nil
        }
        return try XCTUnwrap(found)
    }

    private func money(_ amount: Double) -> String {
        amount == amount.rounded() ? "$\(Int(amount))" : String(format: "$%.2f", amount)
    }

    // MARK: - Stories

    func testBookingStory() async throws {
        let (r, s) = try await startRecording("booking")
        try await setUpActors("coach", "client")
        try await checkpoint(r, "setup")

        // BookingEditorView
        try await signIn("client")
        try await succeed("saveBookingAndMirror") { done in
            fm.saveBookingAndMirror(coachId: uid("coach"), clientId: uid("client"), startAt: s.date("start"), endAt: s.date("end"),
                                    location: s.str("location"), notes: s.str("notes"), completion: done)
        }
        let idDocs = try await docs("clients/\(uid("client"))/bookings")
        let id = try XCTUnwrap(idDocs.first?.documentID)
        r.register(id, "booking")
        try await checkpoint(r, "requested")

        // ReviewBookingView (client confirms)
        try await succeed("confirm") { done in fm.updateBookingStatus(bookingId: id, status: "confirmed", completion: done) }
        try await checkpoint(r, "confirmed")

        // CoachConfirmedBookingsView: payment received, notes, reschedule
        try await signIn("coach")
        try await succeed("paid") { done in fm.updateBookingPaymentStatus(bookingId: id, paymentStatus: "paid", completion: done) }
        try await checkpoint(r, "paid")

        try await succeed("notes") { done in
            fm.saveSessionNotes(bookingId: id, coachId: uid("coach"), clientId: uid("client"), notes: s.str("sessionNotes"), completion: done)
        }
        try await succeed("recap") { done in
            fm.saveSessionRecap(bookingId: id, coachId: uid("coach"), clientId: uid("client"), recap: s.str("recap"), completion: done)
        }
        try await checkpoint(r, "session_notes")

        try await succeed("reschedule") { done in
            fm.rescheduleBooking(bookingId: id, newStart: s.date("newStart"), newEnd: s.date("newEnd"), newStatus: "Pending Acceptance", completion: done)
        }
        try await checkpoint(r, "rescheduled")

        // ClientConfirmedBookingsView
        try await signIn("client")
        try await succeed("cancel") { done in fm.updateBookingStatus(bookingId: id, status: "cancelled", completion: done) }
        try await checkpoint(r, "cancelled")
        try r.finish()
    }

    func testGroupBookingStory() async throws {
        let (r, s) = try await startRecording("group_booking")
        try await setUpActors("coach", "coach2", "client", "client2")
        try await checkpoint(r, "setup")

        try await signIn("client")
        try await succeed("saveGroupBooking") { done in
            fm.saveGroupBooking(coachIds: [uid("coach"), uid("coach2")], clientIds: [uid("client"), uid("client2")],
                                startAt: s.date("start"), endAt: s.date("end"), location: s.str("location"), notes: s.str("notes"),
                                creatorID: uid("client"), creatorType: "client", completion: done)
        }
        let idDocs = try await docs("clients/\(uid("client"))/bookings")
        let id = try XCTUnwrap(idDocs.first?.documentID)
        r.register(id, "booking")
        try await checkpoint(r, "requested")

        for (coach, rate, step) in [("coach", s.dbl("coachRate"), "coach_accepted"), ("coach2", s.dbl("coach2Rate"), "all_accepted")] {
            try await signIn(coach)
            try await succeed("accept") { done in
                fm.acceptGroupBookingAsCoach(bookingId: id, coachId: uid(coach), rateUSD: rate, coachNote: nil, completion: done)
            }
            try await checkpoint(r, step)
        }
        for (client, step) in [("client", "client_confirmed"), ("client2", "all_confirmed")] {
            try await signIn(client)
            try await succeed("confirm") { done in fm.confirmGroupBookingAsClient(bookingId: id, clientId: uid(client), completion: done) }
            try await checkpoint(r, step)
        }

        // CoachConfirmedBookingsView cancels group sessions with updateBookingStatus
        try await signIn("coach")
        try await succeed("cancel") { done in fm.updateBookingStatus(bookingId: id, status: "cancelled", completion: done) }
        try await checkpoint(r, "cancelled")
        try r.finish()
    }

    func testChatStory() async throws {
        let (r, s) = try await startRecording("chat")
        try await setUpActors("coach", "client")
        try await checkpoint(r, "setup")

        try await signIn("client")
        let opened: String? = try await value("createOrGetChat") { done in fm.createOrGetChat(withCoachId: uid("coach"), completion: done) }
        let chat = try XCTUnwrap(opened)
        r.register(chat, "chat")
        try await checkpoint(r, "opened")

        try await succeed("send") { done in fm.sendMessage(chatId: chat, text: s.str("message"), completion: done) }
        let firstDocs = try await docs("chats/\(chat)/messages")
        let first = try XCTUnwrap(firstDocs.first?.documentID)
        r.register(first, "message")
        try await checkpoint(r, "messaged")

        try await signIn("coach")
        try await succeed("reply") { done in fm.sendMessage(chatId: chat, text: s.str("reply"), completion: done) }
        let replyDocs = try await docs("chats/\(chat)/messages")
        let reply = try XCTUnwrap(replyDocs.map(\.documentID).first { $0 != first })
        r.register(reply, "reply")
        try await checkpoint(r, "replied")
        try r.finish()
    }

    func testClubStory() async throws {
        let (r, s) = try await startRecording("club")
        try await setUpActors("coach", "client")
        try await checkpoint(r, "setup")

        try await signIn("coach")
        let created: (String?, Error?) = try await value("addPlaceToPlay") { done in
            fm.addPlaceToPlay(name: s.str("name"), address: s.str("address"), playingTimes: s.stringMap("playingTimes"),
                              pricePerSession: s.str("price")) { done(($0, $1)) }
        }
        if let error = created.1 { throw error }
        let club = try XCTUnwrap(created.0)
        r.register(club, "club")
        try await checkpoint(r, "created")

        try await loadClub(club)
        try await succeed("assignPlaceContact") { done in fm.assignPlaceContact(placeId: club, completion: done) }
        try await checkpoint(r, "claimed")

        let coachUid = uid("coach")
        let clientUid = uid("client")
        try await signIn("client")
        try await loadClub(club) { $0.isAdmin(coachUid) }
        try await succeed("requestToJoinClub") { done in fm.requestToJoinClub(placeId: club, completion: done) }
        try await checkpoint(r, "join_requested")

        try await signIn("coach")
        try await loadClub(club) { !$0.pendingMembers.isEmpty }
        try await succeed("approveClubMember") { done in fm.approveClubMember(placeId: club, userId: clientUid, completion: done) }
        try await checkpoint(r, "approved")

        try await loadClub(club) { $0.members.contains { $0.id == clientUid } }
        try await succeed("sendClubAnnouncement") { done in fm.sendClubAnnouncement(placeId: club, body: s.str("announcement"), completion: done) }
        let announcementDocs = try await docs("placesToPlay/\(club)/announcements")
        let announcement = try XCTUnwrap(announcementDocs.first?.documentID)
        r.register(announcement, "announcement")
        try await checkpoint(r, "announced")
        try r.finish()
    }

    func testSignupEventStory() async throws {
        let saved = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: Story("signup_event").str("timeZone"))!
        defer { NSTimeZone.default = saved }

        let (r, s) = try await startRecording("signup_event")
        try await setUpActors("coach", "client", "client2")
        try await signIn("coach")
        let created: (String?, Error?) = try await value("addPlaceToPlay") { done in
            fm.addPlaceToPlay(name: s.str("club"), address: "100 Shuttle Ln, Minneapolis, MN", playingTimes: [:], pricePerSession: "") { done(($0, $1)) }
        }
        let club = try XCTUnwrap(created.0)
        r.register(club, "club")
        try await checkpoint(r, "setup")

        var eventId: String?
        try await succeed("createSignupEvent") { done in
            eventId = fm.createSignupEvent(title: s.str("title"), description: s.str("description"), eventDate: s.date("eventDate"),
                                           location: s.str("location"), placeId: club, placeName: s.str("club"),
                                           maxSignups: s.int("maxSignups"), recurrence: s.str("recurrence"), feeUSD: s.dbl("feeUSD"),
                                           paymentLink: s.str("paymentLink"), completion: done)
        }
        let event = try XCTUnwrap(eventId)
        r.register(event, "event")
        try await checkpoint(r, "created")

        try await signIn("client")
        try await succeed("signupForEvent") { done in fm.signupForEvent(eventId: event, completion: done) }
        try await checkpoint(r, "signed_up")

        try await signIn("client2")
        try await succeed("joinEventWaitlist") { done in fm.joinEventWaitlist(eventId: event, completion: done) }
        try await checkpoint(r, "waitlisted")

        try await signIn("client")
        let mine = try await loadEvent(event)
        try await succeed("cancelMySignup") { done in fm.cancelMySignup(event: mine, completion: done) }
        try await checkpoint(r, "promoted", settle: 2)

        try await signIn("coach")
        let current = try await loadEvent(event)
        try await succeed("createNextOccurrence") { done in fm.createNextOccurrence(of: current, completion: done) }
        let nextDocs = try await docs("signupEvents")
        let next = try XCTUnwrap(nextDocs.map(\.documentID).first { $0 != event })
        r.register(next, "nextEvent")
        try await checkpoint(r, "next_week")
        try r.finish()
    }

    func testStringingStory() async throws {
        let (r, s) = try await startRecording("stringing")
        try await setUpActors("coach2", "client")
        try await checkpoint(r, "setup")

        // EditStringerView: prices are typed as "$5"; the profile document is keyed by the stringer's uid
        try await signIn("coach2")
        try await succeed("addStringer") { done in
            fm.addStringer(name: s.str("name"), meetupLocationNames: [s.str("meetup")],
                           stringsOffered: [s.str("string"): money(s.dbl("stringPrice"))], laborCost: money(s.dbl("laborCost")), completion: done)
        }
        let profileDocs = try await docs("stringers")
        let profile = try XCTUnwrap(profileDocs.first?.documentID)
        if profile != uid("coach2") { r.register(profile, "stringerProfile") }
        try await checkpoint(r, "profile")

        // StringerDetailView
        try await signIn("client")
        try await succeed("submitStringerOrder") { done in
            fm.submitStringerOrder(stringerId: profile, racketName: s.str("racket"), hasOwnString: false, selectedString: s.str("string"),
                                   stringCost: money(s.dbl("stringPrice")), laborCost: money(s.dbl("laborCost")),
                                   orderTotal: s.str("orderTotal"), tension: s.int("tension"), timelinePreference: s.str("timeline"),
                                   stringerCreatedBy: uid("coach2"), completion: done)
        }
        let orderDocs = try await docs("stringerOrders")
        let order = try XCTUnwrap(orderDocs.first?.documentID)
        r.register(order, "order")
        try await checkpoint(r, "ordered")

        // StringerOrderDetailView
        try await signIn("coach2")
        for status in ["accepted", "ready_for_pickup"] {
            try await succeed("status \(status)") { done in
                fm.updateStringerOrderStatus(orderId: order, status: status, buyerUid: uid("client"), stringerName: s.str("name"), completion: done)
            }
            try await checkpoint(r, status)
        }
        try r.finish()
    }

    func testReviewStory() async throws {
        let (r, s) = try await startRecording("review")
        try await setUpActors("coach", "client")
        try await checkpoint(r, "setup")

        try await signIn("client")
        try await succeed("saveReview") { done in
            fm.saveReview(clientID: uid("client"), coachID: uid("coach"), rating: String(s.int("rating")), ratingMessage: s.str("comment"), completion: done)
        }
        let reviewDocs = try await docs("reviews")
        let review = try XCTUnwrap(reviewDocs.first?.documentID)
        r.register(review, "review")
        try await checkpoint(r, "reviewed")
        try r.finish()
    }

    func testTournamentStory() async throws {
        let (r, s) = try await startRecording("tournament")
        try await setUpActors("coach", "client", "client2")
        try await checkpoint(r, "setup")

        try await signIn("coach")
        try await succeed("createTournament") { done in
            fm.createTournament(name: s.str("name"), startDate: s.date("start"), endDate: s.date("end"), location: s.str("location"),
                                signupLink: s.str("signupLink"), completion: done)
        }
        let tournamentDocs = try await docs("tournaments")
        let tournament = try XCTUnwrap(tournamentDocs.first?.documentID)
        r.register(tournament, "tournament")
        try await checkpoint(r, "created")

        for (player, step, already) in [("client", "joined", 0), ("client2", "partner_joined", 1)] {
            try await signIn(player)
            fm.fetchTournaments()
            try await eventually("the tournament to load") { self.fm.tournaments.first { $0.id == tournament }?.participants.count == already }
            let info = s.obj(player)
            try await succeed("joinTournament") { done in
                fm.joinTournament(tournamentId: tournament, gender: info["gender"] as! String, events: info["events"] as! [String],
                                  skillLevels: info["skillLevels"] as! [String], completion: done)
            }
            try await checkpoint(r, step)
        }
        try r.finish()
    }

    func testProfilesStory() async throws {
        let (r, s) = try await startRecording("profiles")
        try await setUpActors("coach", "client")
        try await checkpoint(r, "setup")

        let c = s.obj("coach")
        try await signIn("coach")
        try await succeed("saveCoachWithSchema") { done in
            fm.saveCoachWithSchema(id: uid("coach"), firstName: Actors.first("coach"), lastName: Actors.last("coach"),
                                   specialties: c["specialties"] as! [String], availability: c["availability"] as! [String],
                                   experienceYears: Int(c["experienceYears"] as! Int64), hourlyRate: Typed.double(c["hourlyRate"]),
                                   meetingPreference: c["meetingPreference"] as? String, photoURL: nil, bio: c["bio"] as? String,
                                   zipCode: c["zipCode"] as? String, city: c["city"] as? String,
                                   rateRange: (c["rateRange"] as! [Any]).compactMap { Typed.double($0) },
                                   tournamentSoftwareLink: c["tournamentSoftwareLink"] as? String,
                                   cancellationWindowHours: Int(c["cancellationWindowHours"] as! Int64), completion: done)
        }
        try await checkpoint(r, "coach_profile")

        let cl = s.obj("client")
        try await signIn("client")
        try await succeed("saveClient") { done in
            fm.saveClient(id: uid("client"), name: Actors.name("client"), goals: cl["goals"] as! [String],
                          preferredAvailability: cl["preferredAvailability"] as! [String], meetingPreference: cl["meetingPreference"] as? String,
                          skillLevel: cl["skillLevel"] as? String, zipCode: cl["zipCode"] as? String, city: cl["city"] as? String,
                          bio: cl["bio"] as? String, photoURL: nil, completion: done)
        }
        try await checkpoint(r, "client_profile")

        // PaymentsView saves the whole map through updateCurrentCoachPayments
        try await signIn("coach")
        try await succeed("updateCurrentCoachPayments") { done in fm.updateCurrentCoachPayments(s.stringMap("payments"), completion: done) }
        try await checkpoint(r, "payment_methods")
        try r.finish()
    }
}
