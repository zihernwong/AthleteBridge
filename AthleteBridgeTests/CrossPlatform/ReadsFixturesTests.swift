import XCTest
import FirebaseAuth
import FirebaseFirestore
@testable import AthleteBridge

/// The real cross-platform check: iOS reading and acting on what the Android app wrote.
final class ReadsAndroidFixturesTests: ReadsFixturesTestCase {
    override class var writer: String { "android" }
}

/// Self-check: the same tests on iOS's own recordings. A failure here is a test bug or an iOS-only bug.
final class ReadsIOSFixturesTests: ReadsFixturesTestCase {
    override class var writer: String { "ios" }
}

/// Loads another app's recorded stories (cross-platform/fixtures/<writer>) into the emulator and runs the iOS app's
/// real readers and actions on them: every screen must find each document, show the values the other app saved,
/// act on it so every copy updates, and route its pushes.
@MainActor
class ReadsFixturesTestCase: CrossPlatformTestCase {

    class var writer: String { "" }

    /// The base class has no fixtures of its own; only the two subclasses run.
    nonisolated override class var defaultTestSuite: XCTestSuite {
        self == ReadsFixturesTestCase.self ? XCTestSuite(name: "ReadsFixturesTestCase") : super.defaultTestSuite
    }

    private var writerName: String { Self.writer == "ios" ? "iOS" : "Android" }

    private let knownStatuses = Set((CrossPlatform.contract["statuses"] as! [String: Any])["known"] as! [String])

    private func fixture(_ story: String) throws -> Fixture {
        guard let f = Fixture.load(Self.writer, story) else {
            throw XCTSkip("No \(Self.writer) recording of '\(story)' yet (cross-platform/check.sh --record makes one)")
        }
        return f
    }

    /// An emulator holding `f`'s documents as they stood at `checkpoint`, and a fresh manager.
    private func world(_ f: Fixture, _ checkpoint: String) async throws -> Seeder {
        try await resetWorld()
        let seed = Seeder()
        try await seed.seed(f, at: checkpoint)
        return seed
    }

    /// A fresh manager for `actor`, made once they're signed in, as when a returning user opens the app.
    /// (A manager made while signed out has its first coach-list read denied, and fetchCoaches then
    /// ignores calls for 30 seconds: an iOS-only quirk, kept out of these cross-platform checks.)
    private func use(_ actor: String) async throws {
        fm?.stopAllChatListeners()
        fm?.stopAllPreviewListeners()
        try? Auth.auth().signOut()
        try await Auth.auth().signIn(withEmail: Actors.email(actor), password: Actors.password)
        fm = FirestoreManager()
        try await signIn(actor)
    }

    /// Expected values at `checkpoint`: each recorded checkpoint's expectations so far (status only from `checkpoint` itself).
    private func expected(_ s: Story, _ f: Fixture, _ checkpoint: String) -> [String: Any] {
        var out: [String: Any] = [:]
        guard let last = s.checkpoints.firstIndex(of: checkpoint) else { return out }
        for cp in s.checkpoints[...last] where f.has(cp) {
            for (k, v) in s.expect(cp) where k != "status" || cp == checkpoint { out[k] = v }
        }
        return out
    }

    private func amount(_ s: String?) -> Double? {
        s.flatMap { Double($0.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)) }
    }

    private func copies(_ id: String, coaches: [String], clients: [String]) -> [String] {
        ["bookings/\(id)"] + coaches.map { "coaches/\(uid($0))/bookings/\(id)" } + clients.map { "clients/\(uid($0))/bookings/\(id)" }
    }

    private func pushes(to actor: String) async throws -> [[String: Any]] { try await notifications(for: uid(actor)) }

    // MARK: - 1:1 bookings

    func testBookingsShowTheSameSessionOnEveryIOSScreen() async throws {
        let f = try fixture("booking")
        let s = Story("booking")
        let p = Problems("iOS reading \(writerName)'s booking story")
        for cp in s.checkpoints.dropFirst() where f.has(cp) {
            let seed = try await world(f, cp)
            let id = seed.id("booking")
            let want = expected(s, f, cp)
            let start = Typed.parseISO(want["start"] as? String ?? s.str("start"))!
            let end = Typed.parseISO(want["end"] as? String ?? s.str("end"))!
            try await use("coach")
            var views: [(String, FirestoreManager.BookingItem?)] = []
            let coachList: [FirestoreManager.BookingItem] = try await value("coach's bookings") { done in
                fm.fetchBookingsForCoach(coachId: uid("coach"), completion: done)
            }
            views.append(("coach's bookings", coachList.first { $0.id == id }))
            let day: [FirestoreManager.BookingItem] = try await value("coach's calendar day") { done in
                fm.fetchBookingsForCoach(coachId: uid("coach"), start: start.addingTimeInterval(-12 * 3600), end: start.addingTimeInterval(12 * 3600), completion: done)
            }
            views.append(("coach's calendar day", day.first { $0.id == id }))
            let root: [FirestoreManager.BookingItem] = try await value("root bookings") { done in
                fm.fetchRootBookingsForCoach(coachId: uid("coach"), completion: done)
            }
            views.append(("coach's bookings from bookings/{id}", root.first { $0.id == id }))
            let clientList: [FirestoreManager.BookingItem] = try await value("client's bookings") { done in
                fm.fetchBookingsForClient(clientId: uid("client"), completion: done)
            }
            views.append(("client's bookings", clientList.first { $0.id == id }))
            for (screen, booking) in views {
                guard let b = booking else { p.add("\(cp): missing from the \(screen)"); continue }
                let at = "\(cp), \(screen)"
                p.eq("\(at): coach", uid("coach"), b.coachID)
                p.eq("\(at): client", uid("client"), b.clientID)
                p.eq("\(at): coach name", Actors.name("coach"), b.coachName)
                p.eq("\(at): client name", Actors.name("client"), b.clientName)
                p.eq("\(at): start", start, b.startAt)
                p.eq("\(at): end", end, b.endAt)
                p.eq("\(at): location", s.str("location"), b.location)
                p.eq("\(at): notes", s.str("notes"), b.notes)
                p.check(knownStatuses.contains(b.status ?? ""), "\(at): status '\(b.status ?? "nil")' is not one iOS knows")
                if let status = want["status"] as? String { p.eq("\(at): status", status, b.status) }
                if let rate = Typed.double(want["rateUSD"]) { p.eq("\(at): rate", rate, b.RateUSD) }
                if let note = want["coachNote"] as? String { p.eq("\(at): coach note", note, b.coachNote) }
                if let paid = want["paymentStatus"] as? String { p.eq("\(at): payment status", paid, b.paymentStatus) }
                if let recap = want["sessionRecap"] as? String { p.eq("\(at): session recap", recap, b.sessionRecap) }
            }
        }
        p.assertNone()
    }

    func testIOSCanConfirmPayRescheduleAndCancelABookingFromTheOtherApp() async throws {
        let f = try fixture("booking")
        let s = Story("booking")
        let from = f.has("accepted") ? "accepted" : "requested"
        let seed = try await world(f, from)
        let id = seed.id("booking")
        let p = Problems("iOS acting on \(writerName)'s booking (from '\(from)')")
        let paths = copies(id, coaches: ["coach"], clients: ["client"])

        try await use("client")
        if let e = try await outcome("confirm", { done in fm.updateBookingStatus(bookingId: id, status: "confirmed", completion: done) }) {
            p.add("confirming failed: \(e.localizedDescription)")
        }
        for path in paths {
            let d = try await data(path) ?? [:]
            p.eq("\(path) Status after confirming", "confirmed", d["Status"] as? String)
            p.eq("\(path) status after confirming", "confirmed", d["status"] as? String)
        }

        try await use("coach")
        if let e = try await outcome("paid", { done in fm.updateBookingPaymentStatus(bookingId: id, paymentStatus: "paid", completion: done) }) {
            p.add("recording payment failed: \(e.localizedDescription)")
        }
        if let e = try await outcome("reschedule", { done in
            fm.rescheduleBooking(bookingId: id, newStart: s.date("newStart"), newEnd: s.date("newEnd"), newStatus: "Pending Acceptance", completion: done)
        }) { p.add("rescheduling failed: \(e.localizedDescription)") }
        for path in paths {
            let d = try await data(path) ?? [:]
            p.eq("\(path) PaymentStatus", "paid", d["PaymentStatus"] as? String)
            p.eq("\(path) paymentStatus", "paid", d["paymentStatus"] as? String)
            p.eq("\(path) StartAt after rescheduling", s.date("newStart"), (d["StartAt"] as? Timestamp)?.dateValue())
            p.eq("\(path) startAt after rescheduling", s.date("newStart"), (d["startAt"] as? Timestamp)?.dateValue())
        }

        try await use("client")
        if let e = try await outcome("cancel", { done in fm.updateBookingStatus(bookingId: id, status: "cancelled", completion: done) }) {
            p.add("cancelling failed: \(e.localizedDescription)")
        }
        for path in paths {
            let d = try await data(path) ?? [:]
            p.eq("\(path) Status after cancelling", "cancelled", d["Status"] as? String)
            p.eq("\(path) status after cancelling", "cancelled", d["status"] as? String)
        }
        p.assertNone()
    }

    // MARK: - Group sessions

    func testGroupSessionsShowEveryParticipantTheSameSession() async throws {
        let f = try fixture("group_booking")
        let s = Story("group_booking")
        let p = Problems("iOS reading \(writerName)'s group session story")
        let coaches = ["coach", "coach2"]
        let clients = ["client", "client2"]
        for cp in s.checkpoints.dropFirst() where f.has(cp) {
            let seed = try await world(f, cp)
            let id = seed.id("booking")
            let want = expected(s, f, cp)
            let accepted = want["accepted"] as? [String] ?? []
            let confirmed = want["confirmed"] as? [String] ?? []
            try await use("coach")
            var views: [(String, FirestoreManager.BookingItem?)] = []
            for c in coaches {
                let list: [FirestoreManager.BookingItem] = try await value("\(c)'s bookings") { done in fm.fetchBookingsForCoach(coachId: uid(c), completion: done) }
                views.append(("\(c)'s bookings", list.first { $0.id == id }))
            }
            for c in clients {
                let list: [FirestoreManager.BookingItem] = try await value("\(c)'s bookings") { done in fm.fetchBookingsForClient(clientId: uid(c), completion: done) }
                views.append(("\(c)'s bookings", list.first { $0.id == id }))
            }
            for (screen, booking) in views {
                guard let b = booking else { p.add("\(cp): missing from \(screen)"); continue }
                let at = "\(cp), \(screen)"
                p.eq("\(at): coaches", coaches.map(uid), b.coachIDs)
                p.eq("\(at): clients", clients.map(uid), b.clientIDs)
                p.eq("\(at): coach names", coaches.map(Actors.name), b.coachNames)
                p.eq("\(at): client names", clients.map(Actors.name), b.clientNames)
                p.eq("\(at): start", s.date("start"), b.startAt)
                p.eq("\(at): location", s.str("location"), b.location)
                p.eq("\(at): notes", s.str("notes"), b.notes)
                p.eq("\(at): is a group session", true, b.isGroupBooking)
                p.check(knownStatuses.contains(b.status ?? ""), "\(at): status '\(b.status ?? "nil")' is not one iOS knows")
                if let status = want["status"] as? String { p.eq("\(at): status", status, b.status) }
                for c in coaches { p.eq("\(at): \(c) accepted", accepted.contains(c), b.coachAcceptances?[uid(c)] == true) }
                for c in clients { p.eq("\(at): \(c) confirmed", confirmed.contains(c), b.clientConfirmations?[uid(c)] == true) }
                if accepted.contains("coach") { p.eq("\(at): coach's rate", s.dbl("coachRate"), b.coachRates?[uid("coach")]) }
                if accepted.contains("coach2") { p.eq("\(at): coach2's rate", s.dbl("coach2Rate"), b.coachRates?[uid("coach2")]) }
            }
        }
        p.assertNone()
    }

    func testIOSParticipantsCanAcceptConfirmAndCancelAGroupSessionFromTheOtherApp() async throws {
        let f = try fixture("group_booking")
        let s = Story("group_booking")
        let seed = try await world(f, "requested")
        let id = seed.id("booking")
        let p = Problems("iOS participants acting on \(writerName)'s group session")
        let paths = copies(id, coaches: ["coach", "coach2"], clients: ["client", "client2"])
        for (coach, rate) in [("coach", s.dbl("coachRate")), ("coach2", s.dbl("coach2Rate"))] {
            try await use(coach)
            if let e = try await outcome("accept", { done in
                fm.acceptGroupBookingAsCoach(bookingId: id, coachId: uid(coach), rateUSD: rate, coachNote: nil, completion: done)
            }) { p.add("\(coach) accepting failed: \(e.localizedDescription)") }
            for path in paths {
                let d = try await data(path) ?? [:]
                p.eq("\(path) coachAcceptances.\(coach)", true, (d["coachAcceptances"] as? [String: Bool])?[uid(coach)])
                p.eq("\(path) CoachAcceptances.\(coach)", true, (d["CoachAcceptances"] as? [String: Bool])?[uid(coach)])
            }
        }
        for path in paths { p.eq("\(path) status once both coaches accept", "Pending Acceptance", try await data(path)?["status"] as? String) }
        for client in ["client", "client2"] {
            try await use(client)
            if let e = try await outcome("confirm", { done in fm.confirmGroupBookingAsClient(bookingId: id, clientId: uid(client), completion: done) }) {
                p.add("\(client) confirming failed: \(e.localizedDescription)")
            }
        }
        for path in paths { p.eq("\(path) status once both clients confirm", "confirmed", try await data(path)?["status"] as? String) }
        // ClientConfirmedBookingsView cancels group sessions with updateGroupBookingStatus
        if let e = try await outcome("cancel", { done in fm.updateGroupBookingStatus(bookingId: id, status: "cancelled", completion: done) }) {
            p.add("cancelling failed: \(e.localizedDescription)")
        }
        for path in paths {
            let d = try await data(path) ?? [:]
            p.eq("\(path) Status after cancelling", "cancelled", d["Status"] as? String)
            p.eq("\(path) status after cancelling", "cancelled", d["status"] as? String)
        }
        p.assertNone()
    }

    // MARK: - Chat

    func testChatsAndMessagesShowUpOnIOS() async throws {
        let f = try fixture("chat")
        let s = Story("chat")
        let p = Problems("iOS reading \(writerName)'s chat story")
        for cp in s.checkpoints.dropFirst() where f.has(cp) {
            let seed = try await world(f, cp)
            let chatId = seed.id("chat")
            let last: String? = cp == "messaged" ? s.str("message") : cp == "replied" ? s.str("reply") : nil
            let sender: String? = cp == "messaged" ? "client" : cp == "replied" ? "coach" : nil
            for actor in ["coach", "client"] {
                try await use(actor)
                fm.fetchUserType(for: uid(actor))
                _ = await soon { self.fm.userTypeLoaded }
                fm.listenForChatsForCurrentUser()
                let listed = await soon { self.fm.chats.contains { $0.id == chatId } }
                p.check(listed, "\(cp): the chat is missing from the \(actor)'s chat list")
                if listed, let last {
                    _ = await soon { self.fm.chats.first { $0.id == chatId }?.lastMessageText == last }
                    p.eq("\(cp): \(actor)'s chat list preview", last, fm.chats.first { $0.id == chatId }?.lastMessageText)
                }
                guard let last, let sender else { continue }
                fm.loadPreviewsForChats(chatIds: [chatId])
                _ = await soon { self.fm.previewTexts[chatId] == last }
                p.eq("\(cp): \(actor)'s message preview", last, fm.previewTexts[chatId])
                let unread = actor != sender
                _ = await soon(4) { self.fm.unreadChatIds.contains(chatId) == unread }
                p.eq("\(cp): \(actor) sees the chat as unread", unread, fm.unreadChatIds.contains(chatId))
            }
            let want = cp == "messaged" ? [s.str("message")] : cp == "replied" ? [s.str("message"), s.str("reply")] : []
            fm.listenForMessages(chatId: chatId)
            _ = await soon { (self.fm.messagesByChat[chatId]?.count ?? 0) == want.count }
            let messages = fm.messagesByChat[chatId] ?? []
            p.eq("\(cp): messages in order", want, messages.map(\.text))
            p.check(messages.allSatisfy { $0.createdAt != nil }, "\(cp): some messages have no time, so they sort wrongly")
            if !want.isEmpty { p.eq("\(cp): first message sender", uid("client"), messages.first?.senderId) }
        }
        p.assertNone()
    }

    func testAnIOSCoachCanReplyInAChatTheOtherAppStarted() async throws {
        let f = try fixture("chat")
        let s = Story("chat")
        let seed = try await world(f, "messaged")
        let chatId = seed.id("chat")
        let p = Problems("iOS replying in \(writerName)'s chat")
        try await use("client")
        let reopened: String? = try await value("createOrGetChat") { done in fm.createOrGetChat(withCoachId: uid("coach"), completion: done) }
        p.eq("iOS opens the same chat id", chatId, reopened)
        try await use("coach")
        if let e = try await outcome("reply", { done in fm.sendMessage(chatId: chatId, text: s.str("reply"), completion: done) }) {
            p.add("sending failed: \(e.localizedDescription)")
        }
        let chat = try await data("chats/\(chatId)") ?? [:]
        p.eq("chat preview", s.str("reply"), chat["lastMessageText"] as? String)
        p.eq("last sender", uid("coach"), chat["lastSenderId"] as? String)
        p.eq("messages", 2, try await docs("chats/\(chatId)/messages").count)
        p.assertNone()
    }

    // MARK: - Clubs

    private func loadClub(_ id: String, where ready: @escaping (PlaceToPlay) -> Bool = { _ in true }) async -> PlaceToPlay? {
        fm.fetchPlacesToPlay()
        _ = await soon { self.fm.placesToPlay.contains { $0.id == id && ready($0) } }
        return fm.placesToPlay.first { $0.id == id }
    }

    func testClubsMembersAndAnnouncementsShowUpOnIOS() async throws {
        let f = try fixture("club")
        let s = Story("club")
        let p = Problems("iOS reading \(writerName)'s club story")
        func reached(_ cp: String, _ step: String) -> Bool {
            f.has(step) && (s.checkpoints.firstIndex(of: cp) ?? 0) >= (s.checkpoints.firstIndex(of: step) ?? .max)
        }
        let clientUid = uid("client")
        for cp in s.checkpoints.dropFirst() where f.has(cp) {
            let seed = try await world(f, cp)
            let clubId = seed.id("club")
            try await use("client")
            guard let club = await loadClub(clubId) else { p.add("\(cp): the club is missing from Places to Play"); continue }
            p.eq("\(cp): name", s.str("name"), club.name)
            p.eq("\(cp): address", s.str("address"), club.address)
            p.eq("\(cp): schedule", s.stringMap("playingTimes"), club.playingTimes)
            p.eq("\(cp): price", s.str("price"), club.pricePerSession)
            if reached(cp, "claimed") {
                p.check(club.isAdmin(uid("coach")), "\(cp): the coach isn't an admin (admins \(club.adminIds))")
                p.eq("\(cp): contact", uid("coach"), club.contactUid)
            }
            if reached(cp, "approved") {
                p.eq("\(cp): member name", Actors.name("client"), club.members.first { $0.id == clientUid }?.name)
                p.check(!club.pendingMembers.contains { $0.id == clientUid }, "\(cp): the client is still pending")
            } else if reached(cp, "join_requested") {
                p.eq("\(cp): pending member name", Actors.name("client"), club.pendingMembers.first { $0.id == clientUid }?.name)
            }
            if reached(cp, "announced") {
                fm.fetchClubAnnouncements(placeId: clubId)
                _ = await soon { (self.fm.clubAnnouncements[clubId]?.count ?? 0) > 0 }
                let news = fm.clubAnnouncements[clubId] ?? []
                p.eq("\(cp): announcement", [s.str("announcement")], news.map(\.body))
                p.eq("\(cp): announcement author", uid("coach"), news.first?.createdBy)
            }
        }
        p.assertNone()
    }

    func testAnIOSMemberCanJoinAClubListedOnTheOtherApp() async throws {
        let f = try fixture("club")
        let from = f.has("claimed") ? "claimed" : "created"
        let seed = try await world(f, from)
        let clubId = seed.id("club")
        let p = Problems("iOS joining \(writerName)'s club (from '\(from)')")
        let clientUid = uid("client")
        try await use("client")
        _ = await loadClub(clubId)
        if let e = try await outcome("requestToJoinClub", { done in fm.requestToJoinClub(placeId: clubId, completion: done) }) {
            p.add("asking to join failed: \(e.localizedDescription)")
        }
        try await settle()
        let pending = ((try await data("placesToPlay/\(clubId)"))?["pendingMembers"] as? [String: Any])?[clientUid] as? [String: Any]
        p.eq("pending entry name", Actors.name("client"), pending?["name"] as? String)
        if from == "claimed" {
            let toAdmin = try await pushes(to: "coach").first { $0["type"] as? String == "club_join_request" }
            p.eq("the admin's join-request push points at the club", clubId, toAdmin?["placeId"] as? String)
        }
        try await use("coach")
        _ = await loadClub(clubId) { !$0.pendingMembers.isEmpty }
        if let e = try await outcome("approveClubMember", { done in fm.approveClubMember(placeId: clubId, userId: clientUid, completion: done) }) {
            p.add("approving failed: \(e.localizedDescription)")
        }
        try await settle()
        let member = ((try await data("placesToPlay/\(clubId)"))?["members"] as? [String: Any])?[clientUid] as? [String: Any]
        p.eq("member name", Actors.name("client"), member?["name"] as? String)
        p.check(try await pushes(to: "client").contains { $0["type"] as? String == "club_approved" }, "the new member isn't told")
        p.assertNone()
    }

    // MARK: - Signup events

    private func loadEvent(_ id: String) async -> SignupEvent? {
        _ = await soon {
            self.fm.fetchSignupEvents()
            try? await self.settle(0.4)
            return self.fm.signupEvents.contains { $0.id == id }
        }
        return fm.signupEvents.first { $0.id == id }
    }

    func testSignupEventsSpotsAndTheWaitlistShowUpOnIOS() async throws {
        let f = try fixture("signup_event")
        let s = Story("signup_event")
        let p = Problems("iOS reading \(writerName)'s signup event story")
        for cp in s.checkpoints.dropFirst() where f.has(cp) {
            let seed = try await world(f, cp)
            try await use("client")
            guard let e = await loadEvent(seed.id("event")) else { p.add("\(cp): the event is missing from the events list"); continue }
            p.eq("\(cp): title", s.str("title"), e.title)
            p.eq("\(cp): description", s.str("description"), e.description)
            p.eq("\(cp): date", s.date("eventDate"), e.eventDate)
            p.eq("\(cp): location", s.str("location"), e.location)
            p.eq("\(cp): club", seed.id("club"), e.placeId)
            p.eq("\(cp): spots", s.int("maxSignups"), e.maxSignups)
            p.eq("\(cp): fee", s.dbl("feeUSD"), e.feeUSD)
            p.eq("\(cp): payment link", s.str("paymentLink"), e.paymentLink)
            p.eq("\(cp): repeats weekly", true, e.isRecurringWeekly)
            let signedUp = ["signed_up", "waitlisted"].contains(cp) ? ["client"] : ["promoted", "next_week"].contains(cp) ? ["client2"] : []
            p.eq("\(cp): signed up", signedUp.map(uid), e.signups.map { $0.userId ?? "nil" })
            p.eq("\(cp): signup names", signedUp.map(Actors.name), e.signups.map(\.name))
            p.eq("\(cp): signup count", signedUp.count, e.signupCount)
            p.eq("\(cp): waitlist", cp == "waitlisted" ? [uid("client2")] : [], e.waitlist.map { $0.userId ?? "nil" })
            if cp == "next_week" {
                let next = await loadEvent(seed.id("nextEvent"))
                p.eq("next week's date (same local time across the DST change)", s.date("nextEventDate"), next?.eventDate)
                p.eq("next week's signups", 0, next?.signupCount)
                p.eq("next week's fee", s.dbl("feeUSD"), next?.feeUSD)
            }
        }
        p.assertNone()
    }

    func testIOSPlayersCanSignUpWaitAndLeaveAnEventFromTheOtherApp() async throws {
        let saved = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: Story("signup_event").str("timeZone"))!
        defer { NSTimeZone.default = saved }
        let f = try fixture("signup_event")
        let s = Story("signup_event")
        let seed = try await world(f, "created")
        let eventId = seed.id("event")
        let p = Problems("iOS players using \(writerName)'s signup event")
        try await use("client")
        if let e = try await outcome("signupForEvent", { done in fm.signupForEvent(eventId: eventId, completion: done) }) {
            p.add("signing up failed: \(e.localizedDescription)")
        }
        try await use("client2")
        let full = try await outcome("second signup", { done in fm.signupForEvent(eventId: eventId, completion: done) })
        p.check(full != nil, "a full event let a second player in")
        if let e = try await outcome("joinEventWaitlist", { done in fm.joinEventWaitlist(eventId: eventId, completion: done) }) {
            p.add("joining the waitlist failed: \(e.localizedDescription)")
        }
        try await use("client")
        if let mine = await loadEvent(eventId) {
            if let e = try await outcome("cancelMySignup", { done in fm.cancelMySignup(event: mine, completion: done) }) {
                p.add("leaving failed: \(e.localizedDescription)")
            }
        } else { p.add("the event doesn't load") }
        try await settle(2)
        let signups = (try await data("signupEvents/\(eventId)"))?["signups"] as? [String: Any] ?? [:]
        p.eq("signed up after the first player leaves", [uid("client2")], signups.values.compactMap { ($0 as? [String: Any])?["userId"] as? String })
        p.check(try await pushes(to: "client2").contains { $0["type"] as? String == "event_waitlist_promoted" }, "the promoted player isn't told")
        try await use("coach")
        if let current = await loadEvent(eventId) {
            if let e = try await outcome("createNextOccurrence", { done in fm.createNextOccurrence(of: current, completion: done) }) {
                p.add("rolling to next week failed: \(e.localizedDescription)")
            }
            let next = try await docs("signupEvents").first { $0.documentID != eventId }
            p.eq("next week's date from iOS (same local time across DST)", s.date("nextEventDate"), (next?.data()["eventDate"] as? Timestamp)?.dateValue())
        }
        p.assertNone()
    }

    // MARK: - Stringing

    func testStringerProfilesAndOrdersShowUpOnIOS() async throws {
        let f = try fixture("stringing")
        let s = Story("stringing")
        let p = Problems("iOS reading \(writerName)'s stringing story")
        let stringerUid = uid(s.str("stringer"))
        for cp in s.checkpoints.dropFirst() where f.has(cp) {
            let seed = try await world(f, cp)
            try await use("client")
            fm.fetchStringers()
            _ = await soon { self.fm.stringers.contains { $0.createdBy == stringerUid } }
            // iOS keys a stringer profile by its owner's uid, Android by a generated id: find it by owner
            guard let profile = fm.stringers.first(where: { $0.createdBy == stringerUid }) else {
                p.add("\(cp): the stringer is missing from the stringer list (\(fm.stringers.map(\.name)))")
                continue
            }
            p.eq("\(cp): stringer name", s.str("name"), profile.name)
            p.eq("\(cp): string price", s.dbl("stringPrice"), amount(profile.stringsOffered[s.str("string")]))
            p.eq("\(cp): labor", s.dbl("laborCost"), amount(profile.laborCost))
            p.eq("\(cp): meetup", [s.str("meetup")], profile.meetupLocationNames)
            if cp == "profile" { continue }
            let orderId = seed.id("order")
            fm.fetchOrdersForBuyer()
            _ = await soon { self.fm.myStringerOrders.contains { $0.id == orderId } }
            let mine = fm.myStringerOrders.first { $0.id == orderId }
            p.check(mine != nil, "\(cp): the order is missing from the buyer's orders")
            try await use(s.str("stringer"))
            fm.fetchOrdersForStringer(stringerId: profile.id)
            _ = await soon { self.fm.stringerIncomingOrders.contains { $0.id == orderId } }
            let incoming = fm.stringerIncomingOrders.first { $0.id == orderId }
            p.check(incoming != nil, "\(cp): the order is missing from the stringer's incoming orders")
            guard let o = mine ?? incoming else { continue }
            p.eq("\(cp): racket", s.str("racket"), o.racketName)
            p.eq("\(cp): string", s.str("string"), o.selectedString)
            p.eq("\(cp): tension", s.int("tension"), o.tension)
            p.eq("\(cp): total", s.dbl("stringPrice") + s.dbl("laborCost"), amount(o.orderTotal))
            p.eq("\(cp): string cost", s.dbl("stringPrice"), amount(o.stringCost))
            p.eq("\(cp): labor cost", s.dbl("laborCost"), amount(o.laborCost))
            p.eq("\(cp): buyer", uid("client"), o.createdBy)
            p.eq("\(cp): buyer name", Actors.name("client"), o.buyerName)
            p.eq("\(cp): status", cp == "ordered" ? "placed" : cp, o.status)
            if cp != "ordered" { p.check(o.statusHistory[cp] != nil, "\(cp): no time for this stage in the order timeline (\(o.statusHistory.keys.sorted()))") }
        }
        p.assertNone()
    }

    func testAnIOSStringerCanWorkAnOrderPlacedOnTheOtherApp() async throws {
        let f = try fixture("stringing")
        let s = Story("stringing")
        let seed = try await world(f, "ordered")
        let orderId = seed.id("order")
        let stringer = s.str("stringer")
        let stringerUid = uid(stringer)
        let p = Problems("iOS stringer updating \(writerName)'s order")
        try await use(stringer)
        fm.fetchStringers()
        _ = await soon { self.fm.stringers.contains { $0.createdBy == stringerUid } }
        // The stringer screens load orders by the stringer's profile id, so they need the profile first
        guard let profileId = fm.stringers.first(where: { $0.createdBy == stringerUid })?.id else {
            p.add("the stringer's own profile, made on \(writerName), doesn't load on iOS, so iOS never fetches their orders")
            p.assertNone()
            return
        }
        fm.fetchOrdersForStringer(stringerId: profileId)
        _ = await soon { self.fm.stringerIncomingOrders.contains { $0.id == orderId } }
        guard let order = fm.stringerIncomingOrders.first(where: { $0.id == orderId }) else {
            p.add("the order isn't in the stringer's incoming orders")
            p.assertNone()
            return
        }
        if let e = try await outcome("accept", { done in
            fm.updateStringerOrderStatus(orderId: orderId, status: "accepted", buyerUid: order.createdBy, stringerName: s.str("name"), completion: done)
        }) { p.add("accepting failed: \(e.localizedDescription)") }
        try await settle()
        p.eq("status", "accepted", try await data("stringerOrders/\(orderId)")?["status"] as? String)
        let push = try await pushes(to: "client").first { $0["type"] as? String == "stringer_order" }
        p.eq("the buyer's push points at the order", orderId, push?["stringerOrderId"] as? String)
        p.assertNone()
    }

    // MARK: - Reviews, tournaments, profiles

    func testReviewsShowUpOnIOS() async throws {
        let f = try fixture("review")
        let s = Story("review")
        let seed = try await world(f, "reviewed")
        let p = Problems("iOS reading \(writerName)'s review")
        try await use("coach")
        let reviews: [FirestoreManager.ReviewItem] = try await value("fetchReviewsForCoach") { done in fm.fetchReviewsForCoach(coachId: uid("coach"), completion: done) }
        if let review = reviews.first(where: { $0.id == seed.id("review") }) {
            p.eq("rating", String(s.int("rating")), review.rating)
            p.eq("comment", s.str("comment"), review.ratingMessage)
            p.eq("reviewer", uid("client"), review.clientID)
        } else {
            p.add("the review is missing from the coach's reviews")
        }
        p.assertNone()
    }

    func testTournamentsAndPartnerSeekersShowUpOnIOS() async throws {
        let f = try fixture("tournament")
        let s = Story("tournament")
        let p = Problems("iOS reading \(writerName)'s tournament story")
        for cp in s.checkpoints.dropFirst() where f.has(cp) {
            let seed = try await world(f, cp)
            let id = seed.id("tournament")
            try await use("client")
            fm.fetchTournaments()
            _ = await soon { self.fm.tournaments.contains { $0.id == id } }
            guard let t = fm.tournaments.first(where: { $0.id == id }) else { p.add("\(cp): the tournament is missing"); continue }
            p.eq("\(cp): name", s.str("name"), t.name)
            p.eq("\(cp): start", s.date("start"), t.startDate)
            p.eq("\(cp): end", s.date("end"), t.endDate)
            p.eq("\(cp): location", s.str("location"), t.location)
            p.eq("\(cp): signup link", s.str("signupLink"), t.signupLink)
            let joined = cp == "joined" ? ["client"] : cp == "partner_joined" ? ["client", "client2"] : []
            p.eq("\(cp): players", Set(joined.map(uid)), Set(t.participants.keys))
            for a in joined {
                let want = s.obj(a)
                let info = t.participants[uid(a)]
                p.eq("\(cp): \(a)'s gender", want["gender"] as? String, info?.gender)
                p.eq("\(cp): \(a)'s events", want["events"] as? [String], info?.events)
                p.eq("\(cp): \(a)'s levels", want["skillLevels"] as? [String], info?.skillLevels)
            }
        }
        p.assertNone()
    }

    func testAPartnerJoiningOnIOSTellsACompatiblePlayerFromTheOtherApp() async throws {
        let f = try fixture("tournament")
        let s = Story("tournament")
        let seed = try await world(f, "joined")
        let id = seed.id("tournament")
        let p = Problems("iOS player joining \(writerName)'s tournament")
        try await use("client2")
        fm.fetchTournaments()
        _ = await soon { self.fm.tournaments.first { $0.id == id }?.participants.count == 1 }
        let info = s.obj("client2")
        if let e = try await outcome("joinTournament", { done in
            fm.joinTournament(tournamentId: id, gender: info["gender"] as! String, events: info["events"] as! [String],
                              skillLevels: info["skillLevels"] as! [String], completion: done)
        }) { p.add("joining failed: \(e.localizedDescription)") }
        try await settle()
        p.check(try await pushes(to: "client").contains { $0["type"] as? String == "tournament_partner" },
                "the compatible player who joined on \(writerName) isn't told")
        p.assertNone()
    }

    func testProfilesAndPaymentHandlesShowUpOnIOS() async throws {
        let f = try fixture("profiles")
        let s = Story("profiles")
        let p = Problems("iOS reading \(writerName)'s profiles")
        guard let last = s.checkpoints.last(where: { f.has($0) }) else { return }
        _ = try await world(f, last)
        try await use("coach")
        let c = s.obj("coach")
        if let coach = fm.currentCoach, f.has("coach_profile") {
            p.eq("coach name", Actors.name("coach"), coach.name)
            p.eq("specialties", c["specialties"] as? [String], coach.specialties)
            p.eq("experience", Int(c["experienceYears"] as! Int64), coach.experienceYears)
            p.eq("availability", c["availability"] as? [String], coach.availability)
            p.eq("bio", c["bio"] as? String, coach.bio)
            p.eq("hourly rate", Typed.double(c["hourlyRate"]), coach.hourlyRate)
            p.eq("rate range", (c["rateRange"] as! [Any]).compactMap { Typed.double($0) }, coach.rateRange)
            p.eq("meeting preference", c["meetingPreference"] as? String, coach.meetingPreference)
            p.eq("zip", c["zipCode"] as? String, coach.zipCode)
            p.eq("city", c["city"] as? String, coach.city)
            p.eq("tournament link", c["tournamentSoftwareLink"] as? String, coach.tournamentSoftwareLink)
            p.eq("cancellation window", Int(c["cancellationWindowHours"] as! Int64), coach.cancellationWindowHours)
        } else if fm.currentCoach == nil { p.add("the coach profile doesn't load") }
        fm.fetchCoaches()
        p.check(await soon { self.fm.coaches.contains { $0.id == self.uid("coach") } }, "the coach is missing from the coach list")
        if f.has("payment_methods") {
            let payments: [String: String] = try await value("fetchCoachPayments") { done in fm.fetchCoachPayments(coachIdOrPath: uid("coach"), completion: done) }
            for (platform, handle) in s.stringMap("payments") {
                p.check(payments[platform] != nil, "no \(platform) handle (payments: \(payments))")
                p.eq("\(platform) link", PaymentLinks.deepLink(platform: platform, handle: handle), payments[platform].flatMap { PaymentLinks.deepLink(platform: platform, handle: $0) })
            }
        }
        try await use("client")
        let cl = s.obj("client")
        if let client = fm.currentClient, f.has("client_profile") {
            p.eq("client name", Actors.name("client"), client.name)
            p.eq("goals", cl["goals"] as? [String], client.goals)
            p.eq("availability", cl["preferredAvailability"] as? [String], client.preferredAvailability)
            p.eq("meeting preference", cl["meetingPreference"] as? String, client.meetingPreference)
            p.eq("skill level", cl["skillLevel"] as? String, client.skillLevel)
            p.eq("zip", cl["zipCode"] as? String, client.zipCode)
            p.eq("city", cl["city"] as? String, client.city)
            p.eq("bio", cl["bio"] as? String, client.bio)
        } else if fm.currentClient == nil { p.add("the client profile doesn't load") }
        p.assertNone()
    }

    func testSavingAProfileOnIOSKeepsWhatTheOtherAppStored() async throws {
        let f = try fixture("profiles")
        guard let last = Story("profiles").checkpoints.last(where: { f.has($0) }) else { return }
        _ = try await world(f, last)
        let p = Problems("iOS saving profiles over \(writerName)'s")
        try await use("coach")
        let coachPath = "coaches/\(uid("coach"))"
        let coachBefore = Set((try await data(coachPath) ?? [:]).keys)
        if let c = fm.currentCoach {
            if let e = try await outcome("saveCoachWithSchema", { done in
                fm.saveCoachWithSchema(id: c.id, firstName: Actors.first("coach"), lastName: Actors.last("coach"), specialties: c.specialties,
                                       availability: c.availability, experienceYears: c.experienceYears, hourlyRate: c.hourlyRate,
                                       meetingPreference: c.meetingPreference, photoURL: c.photoURLString, bio: c.bio, zipCode: c.zipCode,
                                       city: c.city, rateRange: c.rateRange, tournamentSoftwareLink: c.tournamentSoftwareLink,
                                       linkedPlaceIds: c.linkedPlaceIds, cancellationWindowHours: c.cancellationWindowHours, completion: done)
            }) { p.add("saving the coach failed: \(e.localizedDescription)") }
        } else { p.add("the coach profile doesn't load") }
        p.eq("coach fields lost by saving on iOS", Set<String>(), coachBefore.subtracting((try await data(coachPath) ?? [:]).keys))
        try await use("client")
        let clientPath = "clients/\(uid("client"))"
        let clientBefore = Set((try await data(clientPath) ?? [:]).keys)
        if let c = fm.currentClient {
            if let e = try await outcome("saveClient", { done in
                fm.saveClient(id: c.id, name: c.name, goals: c.goals, preferredAvailability: c.preferredAvailability, meetingPreference: c.meetingPreference,
                              skillLevel: c.skillLevel, zipCode: c.zipCode, city: c.city, bio: c.bio, tournamentSoftwareLink: c.tournamentSoftwareLink,
                              photoURL: nil, completion: done)
            }) { p.add("saving the client failed: \(e.localizedDescription)") }
        } else { p.add("the client profile doesn't load") }
        p.eq("client fields lost by saving on iOS", Set<String>(), clientBefore.subtracting((try await data(clientPath) ?? [:]).keys))
        p.assertNone()
    }

    // MARK: - Pushes

    func testEveryPushTheOtherAppSendsOpensTheRightIOSScreen() throws {
        let p = Problems("Pushes \(writerName) queued, as iOS handles them after the Cloud Function")
        var count = 0
        for story in CrossPlatform.storyNames {
            guard let f = Fixture.load(Self.writer, story) else { continue }
            let seed = Seeder()
            for cp in f.checkpoints {
                for (recipient, doc) in f.pushes(cp.name) {
                    count += 1
                    let notification = seed.tree(doc) as? [String: Any] ?? [:]
                    if let problem = PushRoutes.duplicate(notification) ?? PushRoutes.problem(notification, recipient: seed.text(recipient)) {
                        p.add("\(story)/\(cp.name): \(problem)")
                    }
                }
            }
        }
        if count == 0 { throw XCTSkip("No \(Self.writer) pushes recorded yet") }
        p.assertNone()
    }
}
