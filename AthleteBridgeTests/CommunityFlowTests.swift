import XCTest
import FirebaseFirestore
@testable import AthleteBridge

// MARK: - Clubs

@MainActor
final class ClubFlowTests: EmulatorTestCase {

    private func createClub(by user: TestUser) async throws -> String {
        try await signIn(user)
        let result: (String?, Error?) = try await value("addPlaceToPlay") { done in
            fm.addPlaceToPlay(name: "Egret \(UUID().uuidString.prefix(4))", address: "123 Shuttle Ln",
                              playingTimes: ["Tuesday": "6:30 PM - 9:30 PM"], pricePerSession: "$8") { done(($0, $1)) }
        }
        if let error = result.1 { throw error }
        return try XCTUnwrap(result.0)
    }

    /// Waits for the club to show up in the manager's live list (several actions read it from there).
    @discardableResult
    private func club(_ id: String, where ready: @escaping (PlaceToPlay) -> Bool = { _ in true }) async throws -> PlaceToPlay {
        fm.fetchPlacesToPlay()
        var found: PlaceToPlay?
        try await eventually("club \(id) to load") {
            found = self.fm.placesToPlay.first { $0.id == id && ready($0) }
            return found != nil
        }
        return try XCTUnwrap(found)
    }

    private func claim(_ id: String, as user: TestUser, expectingAdmins count: Int) async throws {
        try await signIn(user)
        try await club(id) { $0.admins.count == count - 1 }
        try await succeed("assignPlaceContact") { done in fm.assignPlaceContact(placeId: id, completion: done) }
        try await club(id) { $0.admins.count == count }
    }

    func testClaimingAClubMakesYouAdminMemberAndContact() async throws {
        let olivia = try await makeUser(.coach, first: "Olivia")
        let id = try await createClub(by: olivia)
        try await claim(id, as: olivia, expectingAdmins: 1)
        let d = try await data("placesToPlay/\(id)") ?? [:]
        XCTAssertEqual(d["contactUid"] as? String, olivia.uid)
        XCTAssertEqual(d["contactName"] as? String, "Olivia Tester")
        let place = try await club(id)
        XCTAssertTrue(place.isAdmin(olivia.uid))
        XCTAssertEqual(place.members.map(\.id), [olivia.uid])
    }

    func testWhenTheContactStepsDownAnotherAdminTakesOver() async throws {
        let olivia = try await makeUser(.coach, first: "Olivia")
        let morgan = try await makeUser(.coach, first: "Morgan")
        let id = try await createClub(by: olivia)
        try await claim(id, as: olivia, expectingAdmins: 1)
        try await claim(id, as: morgan, expectingAdmins: 2)
        let afterSecond = try await data("placesToPlay/\(id)")
        XCTAssertEqual(afterSecond?["contactUid"] as? String, olivia.uid, "the first admin stays the contact")

        try await signIn(olivia)
        try await club(id) { $0.admins.count == 2 }
        try await succeed("removePlaceContact") { done in fm.removePlaceContact(placeId: id, completion: done) }
        let d = try await data("placesToPlay/\(id)") ?? [:]
        XCTAssertEqual(d["contactUid"] as? String, morgan.uid)
        XCTAssertEqual(Array((d["admins"] as? [String: Any] ?? [:]).keys), [morgan.uid])
    }

    func testJoinRequestsAndApprovalsNotifyTheRightPeople() async throws {
        let olivia = try await makeUser(.coach, first: "Olivia")
        let pat = try await makeUser(.client, first: "Pat")
        let id = try await createClub(by: olivia)
        try await claim(id, as: olivia, expectingAdmins: 1)

        try await signIn(pat)
        try await club(id) { $0.isAdmin(olivia.uid) }
        try await succeed("requestToJoinClub") { done in fm.requestToJoinClub(placeId: id, completion: done) }
        try await eventually("the admin's join-request push") { try await self.notifications(for: olivia.uid).count > 0 }
        let request = try await notifications(for: olivia.uid)[0]
        XCTAssertEqual(request["type"] as? String, "club_join_request")
        XCTAssertEqual(request["placeId"] as? String, id)

        try await signIn(olivia)
        try await club(id) { !$0.pendingMembers.isEmpty }
        try await succeed("approveClubMember") { done in fm.approveClubMember(placeId: id, userId: pat.uid, completion: done) }
        let place = try await club(id) { $0.members.contains { $0.id == pat.uid } }
        XCTAssertTrue(place.pendingMembers.isEmpty)
        XCTAssertEqual(place.members.first { $0.id == pat.uid }?.name, "Pat Tester")
        try await eventually("Pat's approval push") { try await self.notifications(for: pat.uid).count > 0 }
        let approval = try await notifications(for: pat.uid)[0]
        XCTAssertEqual(approval["type"] as? String, "club_approved")
    }

    func testAnnouncementsReachEveryMemberExceptTheSender() async throws {
        let olivia = try await makeUser(.coach, first: "Olivia")
        let members = [try await makeUser(.client, first: "Pat"), try await makeUser(.client, first: "Riley")]
        let id = try await createClub(by: olivia)
        try await claim(id, as: olivia, expectingAdmins: 1)
        for member in members {
            try await signIn(member)
            try await club(id)
            try await succeed("requestToJoinClub") { done in fm.requestToJoinClub(placeId: id, completion: done) }
        }
        try await signIn(olivia)
        for member in members {
            try await club(id) { $0.pendingMembers.contains { $0.id == member.uid } }
            try await succeed("approve") { done in fm.approveClubMember(placeId: id, userId: member.uid, completion: done) }
        }
        let place = try await club(id) { $0.members.count == 3 }
        try await succeed("sendClubAnnouncement") { done in fm.sendClubAnnouncement(placeId: id, body: "Courts close at 8 tonight", completion: done) }

        let stored = try await docs("placesToPlay/\(id)/announcements")
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.data()["title"] as? String, place.name)
        for member in members {
            let push = try await notifications(for: member.uid).first { $0["type"] as? String == "club_announcement" }
            XCTAssertEqual(push?["announcementId"] as? String, stored.first?.documentID, member.name)
            XCTAssertEqual(push?["body"] as? String, "Courts close at 8 tonight")
        }
        let toSender = try await notifications(for: olivia.uid).filter { $0["type"] as? String == "club_announcement" }
        XCTAssertTrue(toSender.isEmpty)
    }

    func testClubsCreatedOnAndroidAppearOnIOS() async throws {
        let pat = try await makeUser(.client, first: "Pat")
        try await signIn(pat)
        // The shape Android's PlaceRepository.addPlace writes
        let ref = db.collection("placesToPlay").document()
        try await ref.setData([
            "name": "Android Club \(UUID().uuidString.prefix(4))", "address": "1 Court St",
            "weeklySchedule": ["Monday": "7:00 PM - 9:00 PM"], "pricing": "$5",
            "members": [String: Any](), "pendingMembers": [String: Any](), "createdBy": pat.uid
        ])
        fm.fetchPlacesToPlay()
        try await settle(2)
        let place = fm.placesToPlay.first { $0.id == ref.documentID }
        XCTAssertNotNil(place, "the club list is ordered by createdAt, which Android never writes, so the club is dropped")
        XCTAssertEqual(place?.playingTimes["Monday"], "7:00 PM - 9:00 PM")
        XCTAssertEqual(place?.pricePerSession, "$5")
    }
}

// MARK: - Stringing orders

@MainActor
final class StringingFlowTests: EmulatorTestCase {

    private var stringer: TestUser!   // the stringer's own account
    private var buyer: TestUser!

    override func setUp() async throws {
        try await super.setUp()
        stringer = try await makeUser(.coach, first: "Sasha")
        buyer = try await makeUser(.client, first: "Pat")
    }

    /// A stringer profile as iOS creates it: the document id is the owner's uid.
    private func seedIOSStringer() async throws -> String {
        try await signIn(stringer)
        try await seed("stringers/\(stringer.uid)", ["name": "Sasha Strings", "laborCost": "$15", "stringsOffered": ["BG65": "$5"],
                                                    "meetupLocationNames": ["Egret Gym"], "createdBy": stringer.uid])
        return stringer.uid
    }

    /// Places an order the way StringerDetailView does.
    private func placeOrder(stringerId: String) async throws -> String {
        try await signIn(buyer)
        try await succeed("submitStringerOrder") { done in
            fm.submitStringerOrder(stringerId: stringerId, racketName: "Astrox 88D", hasOwnString: false, selectedString: "BG65",
                                   stringCost: "$5", laborCost: "$15", orderTotal: "$20.00", tension: 26,
                                   timelinePreference: "This week", stringerCreatedBy: stringer.uid, completion: done)
        }
        let mine = try await db.collection("stringerOrders").whereField("createdBy", isEqualTo: buyer.uid).getDocuments(source: .server)
        return try XCTUnwrap(mine.documents.first?.documentID)
    }

    func testAnOrderReachesTheStringerAndTracksEachStage() async throws {
        let stringerId = try await seedIOSStringer()
        let orderId = try await placeOrder(stringerId: stringerId)
        let stored = try await data("stringerOrders/\(orderId)") ?? [:]
        XCTAssertEqual(stored["status"] as? String, "placed")
        XCTAssertEqual(stored["buyerName"] as? String, "Pat Tester")
        XCTAssertEqual(stored["orderTotal"] as? String, "$20.00")
        try await eventually("the stringer's new-order push") { try await self.notifications(for: self.stringer.uid).count > 0 }
        let newOrder = try await notifications(for: stringer.uid)[0]
        XCTAssertEqual(newOrder["stringerOrderId"] as? String, orderId)

        try await signIn(stringer)
        for status in ["accepted", "stringing", "ready_for_pickup"] {
            try await succeed("update to \(status)") { done in
                fm.updateStringerOrderStatus(orderId: orderId, status: status, buyerUid: buyer.uid, stringerName: "Sasha Strings", completion: done)
            }
        }
        fm.fetchOrdersForStringer(stringerId: stringerId)
        try await eventually("the stringer's order list") {
            self.fm.stringerIncomingOrders.first { $0.id == orderId }?.statusHistory.count == 3
        }
        let order = try XCTUnwrap(fm.stringerIncomingOrders.first { $0.id == orderId })
        XCTAssertTrue(order.isStageReached("ready_for_pickup"))
        XCTAssertFalse(order.isStageReached("picked_up"))
        try await eventually("the buyer's three status pushes") { try await self.notifications(for: self.buyer.uid).count == 3 }
    }

    func testStringingPushesUseTheSharedType() async throws {
        let stringerId = try await seedIOSStringer()
        let orderId = try await placeOrder(stringerId: stringerId)
        try await signIn(stringer)
        try await succeed("accept") { done in
            fm.updateStringerOrderStatus(orderId: orderId, status: "accepted", buyerUid: buyer.uid, stringerName: "Sasha Strings", completion: done)
        }
        try await settle()
        let stringerPushes = try await notifications(for: stringer.uid)
        let buyerPushes = try await notifications(for: buyer.uid)
        let types = (stringerPushes + buyerPushes).map { $0["type"] as? String ?? "nil" }
        XCTAssertEqual(types.filter { !crossPlatformNotificationTypes.contains($0) }, [],
                       "Android only routes `stringer_order` pushes to the order screen")
    }

    /// An order as the Android app wrote it before it started recording `createdBy`.
    private func seedAndroidOrder(stringerId: String) async throws -> String {
        try await signIn(buyer)
        let ref = db.collection("stringerOrders").document()
        try await ref.setData([
            "stringerId": stringerId, "racketName": "Nanoflare 700", "hasOwnString": true, "tension": 25,
            "timelinePreference": "ASAP", "buyerId": buyer.uid, "clientId": buyer.uid, "buyerName": "Pat Tester",
            "status": "placed", "createdAt": Timestamp(date: Date()), "orderTotal": "15.00"
        ])
        return ref.documentID
    }

    func testOrdersPlacedOnAndroidShowInTheBuyersOrders() async throws {
        let stringerId = try await seedIOSStringer()
        let orderId = try await seedAndroidOrder(stringerId: stringerId)
        fm.fetchOrdersForBuyer()
        try await settle(1.5)
        XCTAssertNotNil(fm.myStringerOrders.first { $0.id == orderId }, "My Orders on iOS only finds orders with createdBy")
    }

    func testTheStringerKnowsWhoPlacedAnAndroidOrder() async throws {
        // StringerOrderDetailView notifies `order.createdBy` on every status change; an empty id makes
        // Firestore throw an Objective-C exception (document path "") and the app crashes.
        let stringerId = try await seedIOSStringer()
        let orderId = try await seedAndroidOrder(stringerId: stringerId)
        try await signIn(stringer)
        fm.fetchOrdersForStringer(stringerId: stringerId)
        try await eventually("the stringer's order list") { self.fm.stringerIncomingOrders.contains { $0.id == orderId } }
        let order = try XCTUnwrap(fm.stringerIncomingOrders.first { $0.id == orderId })
        XCTAssertEqual(order.createdBy, buyer.uid)
    }

    func testPickupConfirmationReachesAStringerWhoSignedUpOnAndroid() async throws {
        // Android creates stringer profiles with collection("stringers").add, so the document id is not the owner's uid.
        try await signIn(stringer)
        let profile = db.collection("stringers").document()
        try await profile.setData(["name": "Android Strings", "laborCost": "$12", "stringsOffered": [String: String](),
                                   "createdBy": stringer.uid])
        let orderId = try await placeOrder(stringerId: profile.documentID)

        // The buyer taps "Picked up" — StringerOrderDetailView passes order.stringerId as the stringer to notify.
        fm.fetchOrdersForBuyer()
        try await eventually("the buyer's order list") { self.fm.myStringerOrders.contains { $0.id == orderId } }
        let order = try XCTUnwrap(fm.myStringerOrders.first { $0.id == orderId })
        try await succeed("picked up") { done in
            fm.updateStringerOrderStatusAsBuyer(orderId: orderId, status: "picked_up", stringerUid: order.stringerId,
                                                buyerName: "Pat Tester", completion: done)
        }
        try await settle()
        let pickups = try await notifications(for: stringer.uid).filter { ($0["body"] as? String ?? "").contains("Picked Up") }
        XCTAssertEqual(pickups.count, 1, "the push went to pendingNotifications/\(order.stringerId) instead of the stringer's account")
    }
}

// MARK: - Chat

@MainActor
final class ChatFlowTests: EmulatorTestCase {

    private var coach: TestUser!
    private var client: TestUser!

    override func setUp() async throws {
        try await super.setUp()
        coach = try await makeUser(.coach, first: "Casey")
        client = try await makeUser(.client, first: "Pat")
    }

    private func openChat() async throws -> String {
        try await signIn(client)
        let chatId: String? = try await value("createOrGetChat") { done in fm.createOrGetChat(withCoachId: coach.uid, completion: done) }
        return try XCTUnwrap(chatId)
    }

    private func send(_ text: String, as user: TestUser, in chatId: String) async throws {
        try await signIn(user)
        try await succeed("sendMessage") { done in fm.sendMessage(chatId: chatId, text: text, completion: done) }
    }

    func testStartingAChatUsesTheSortedUidPairAndRecordsBothPeople() async throws {
        let chatId = try await openChat()
        XCTAssertEqual(chatId, [coach.uid, client.uid].sorted().joined(separator: "_"))
        let chat = try await data("chats/\(chatId)") ?? [:]
        let refs = (chat["participantRefs"] as? [DocumentReference] ?? []).map(\.path)
        XCTAssertEqual(Set(refs), ["coaches/\(coach.uid)", "clients/\(client.uid)"])
        let names = chat["participantNames"] as? [String: String]
        XCTAssertEqual(names?[coach.uid], "Casey Tester")
        XCTAssertEqual(names?[client.uid], "Pat Tester")
        let again: String? = try await value("createOrGetChat again") { done in fm.createOrGetChat(withCoachId: coach.uid, completion: done) }
        XCTAssertEqual(again, chatId)
    }

    func testMessagesUpdateTheChatAndNotifyTheOtherPerson() async throws {
        let chatId = try await openChat()
        try await send("Can we move to 7?", as: client, in: chatId)
        let chat = try await data("chats/\(chatId)") ?? [:]
        XCTAssertEqual(chat["lastMessageText"] as? String, "Can we move to 7?")
        let message = try await docs("chats/\(chatId)/messages").first?.data() ?? [:]
        XCTAssertEqual(message["senderId"] as? String, client.uid)
        XCTAssertNotNil(message["createdAt"] as? Timestamp)
        try await eventually("the coach's chat push") { try await self.notifications(for: self.coach.uid).count > 0 }
        let push = try await notifications(for: coach.uid)[0]
        XCTAssertEqual(push["chatId"] as? String, chatId)
        XCTAssertEqual(push["body"] as? String, "Can we move to 7?")
        let toSender = try await notifications(for: client.uid)
        XCTAssertTrue(toSender.isEmpty)
    }

    func testTheChatRecordsWhoSentTheLastMessage() async throws {
        // Android's chat list decides unread from lastSenderId when it has no read marker.
        let chatId = try await openChat()
        try await send("See you Tuesday", as: client, in: chatId)
        let chat = try await data("chats/\(chatId)")
        XCTAssertEqual(chat?["lastSenderId"] as? String, client.uid)
    }

    func testIncomingMessagesStayUnreadUntilRead() async throws {
        let chatId = try await openChat()
        try await send("Running 5 min late", as: client, in: chatId)
        try await signIn(coach)
        fm.loadPreviewsForChats(chatIds: [chatId])
        try await eventually("the unread preview") {
            self.fm.previewTexts[chatId] == "Running 5 min late" && self.fm.unreadChatIds.contains(chatId)
        }
        let messages = try await docs("chats/\(chatId)/messages")
        let messageId = try XCTUnwrap(messages.first?.documentID)
        try await db.document("chats/\(chatId)/messages/\(messageId)").updateData(["readBy.\(coach.uid)": FieldValue.serverTimestamp()])
        try await eventually("the chat to be marked read") { !self.fm.unreadChatIds.contains(chatId) }

        try await succeed("reply") { done in fm.sendMessage(chatId: chatId, text: "No problem", completion: done) }
        try await eventually("the reply preview") { self.fm.previewTexts[chatId] == "No problem" }
        XCTAssertFalse(fm.unreadChatIds.contains(chatId), "your own message is never unread")
    }

    func testOlderAndroidMessagesStillShowInTheChatPreview() async throws {
        // A legacy Android build wrote `timestamp` instead of `createdAt` on messages.
        let chatId = try await openChat()
        try await db.collection("chats/\(chatId)/messages").document().setData([
            "text": "Courts are booked", "senderId": coach.uid, "timestamp": Timestamp(date: Date())
        ])
        fm.loadPreviewsForChats(chatIds: [chatId])
        try await settle(1.5)
        XCTAssertEqual(fm.previewTexts[chatId], "Courts are booked", "the preview query orders by createdAt and skips the message")
    }
}

// MARK: - Tournaments

@MainActor
final class TournamentFlowTests: EmulatorTestCase {

    func testJoiningNotifiesOnlyCompatiblePartnerSeekers() async throws {
        let organizer = try await makeUser(.coach, first: "Olivia")
        let alex = try await makeUser(.client, first: "Alex")
        let jordan = try await makeUser(.client, first: "Jordan")
        let pat = try await makeUser(.client, first: "Pat")

        try await signIn(organizer)
        let name = "Fall Open \(UUID().uuidString.prefix(6))"
        try await succeed("createTournament") { done in
            fm.createTournament(name: name, startDate: .inDays(20), endDate: .inDays(21), location: "Egret Gym", completion: done)
        }
        let created = try await db.collection("tournaments").whereField("name", isEqualTo: name).getDocuments(source: .server)
        let id = try XCTUnwrap(created.documents.first?.documentID)
        try await db.document("tournaments/\(id)").updateData([
            "participants.\(alex.uid)": ["gender": "Male", "events": ["Men's Doubles"], "skillLevels": ["B"]],
            "participants.\(jordan.uid)": ["gender": "Female", "events": ["Women's Doubles"], "skillLevels": ["B"]]
        ])

        try await signIn(pat)
        fm.fetchTournaments()
        try await eventually("the tournament to load") { self.fm.tournaments.first { $0.id == id }?.participants.count == 2 }
        try await succeed("joinTournament") { done in
            fm.joinTournament(tournamentId: id, gender: "Male", events: ["Men's Doubles"], skillLevels: ["B"], completion: done)
        }
        try await eventually("Alex's partner push") { try await self.notifications(for: alex.uid).count > 0 }
        let push = try await notifications(for: alex.uid)[0]
        XCTAssertEqual(push["type"] as? String, "tournament_partner")
        XCTAssertEqual(push["tournamentId"] as? String, id)
        try await settle()
        let toJordan = try await notifications(for: jordan.uid)
        XCTAssertTrue(toJordan.isEmpty, "Women's Doubles players aren't partners for a Men's Doubles player")
        let joined = try await data("tournaments/\(id)")?["participants"] as? [String: Any]
        XCTAssertNotNil(joined?[pat.uid])
    }
}
