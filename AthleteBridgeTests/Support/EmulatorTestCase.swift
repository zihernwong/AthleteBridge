import XCTest
import FirebaseAuth
import FirebaseFirestore
@testable import AthleteBridge

enum TestError: Error { case timedOut(String) }

/// Base class for tests that drive the real `FirestoreManager` against the local Firebase emulators.
///
/// The app is this bundle's test host, and whenever it runs under XCTest it points Auth and Firestore
/// at the emulators before anything touches them (`AppDelegate.useFirebaseEmulatorsWhenUnitTesting`),
/// so these tests can never read or write production data. `scripts/run-ios-unit-tests.sh` starts the
/// emulators and runs the suite; to run from Xcode instead, start them first:
///
///     npx firebase-tools@13.35.1 emulators:start --config firebase.emulators.json --only auth,firestore --project athletebridge-63176
///
/// (firebase-tools 14+ needs Java 21.) The emulator enforces the real `firestore.rules`.
@MainActor
class EmulatorTestCase: XCTestCase {

    enum Role: String { case coach = "COACH", client = "CLIENT" }

    struct TestUser {
        let uid: String
        let email: String
        let password: String
        let first: String
        let name: String
        let role: Role
    }

    var db: Firestore { Firestore.firestore() }
    /// A fresh manager per test, like the one the app creates at launch.
    var fm: FirestoreManager!

    private static var emulatorReachable: Bool?

    override func setUp() async throws {
        try await super.setUp()
        // Safety net: refuse to run anything unless Firestore is pointed at the local emulator.
        guard AppDelegate.isRunningUnitTests,
              Firestore.firestore().settings.host == AppDelegate.emulatorFirestoreHost else {
            XCTFail("Firestore is not pointed at the local emulator; refusing to run data tests")
            throw XCTSkip("Firestore emulator not configured")
        }
        try? Auth.auth().signOut()
        try await Self.requireEmulator()
        fm = FirestoreManager()
    }

    override func tearDown() async throws {
        fm?.stopAllChatListeners()
        fm?.stopSubscriptionListener()
        fm = nil
        try? Auth.auth().signOut()
        try await super.tearDown()
    }

    private static func requireEmulator() async throws {
        if emulatorReachable == nil {
            // The client may still be connecting right after launch, so give it a few tries.
            for attempt in 1...8 {
                do {
                    _ = try await Firestore.firestore().document("_ping/ping").getDocument(source: .server)
                    emulatorReachable = true
                } catch let error as NSError {
                    // Unauthenticated reads are denied by the rules, which still proves the emulator answered.
                    emulatorReachable = error.code != FirestoreErrorCode.unavailable.rawValue
                }
                if emulatorReachable == true || attempt == 8 { break }
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        if emulatorReachable == false {
            throw XCTSkip("Firebase emulators are not running. Use scripts/run-ios-unit-tests.sh, or start them with: npx firebase-tools@13.35.1 emulators:start --config firebase.emulators.json --only auth,firestore --project athletebridge-63176")
        }
    }

    // MARK: - Users

    /// Creates an Auth emulator account (which signs in as it) and writes its `userType` and profile
    /// documents in the shape the app's onboarding writes them.
    @discardableResult
    func makeUser(_ role: Role, first: String, last: String = "Tester", profile extra: [String: Any] = [:]) async throws -> TestUser {
        let email = "\(first.lowercased())-\(UUID().uuidString.prefix(8).lowercased())@athletebridge.test"
        let password = "test-password-123"
        let uid = try await Auth.auth().createUser(withEmail: email, password: password).user.uid
        try await db.document("userType/\(uid)").setData(["type": role.rawValue])
        switch role {
        case .coach:
            var data: [String: Any] = [
                "FirstName": first, "LastName": last, "Specialties": ["Badminton"],
                "Availability": ["Evening"], "ExperienceYears": 3, "Active": true
            ]
            data.merge(extra) { _, new in new }
            try await db.document("coaches/\(uid)").setData(data)
        case .client:
            var data: [String: Any] = ["name": "\(first) \(last)", "goals": ["Badminton"], "preferredAvailability": ["Evening"]]
            data.merge(extra) { _, new in new }
            try await db.document("clients/\(uid)").setData(data)
        }
        return TestUser(uid: uid, email: email, password: password, first: first, name: "\(first) \(last)", role: role)
    }

    /// Signs in as `user` and waits until the manager has loaded their profile (names on outgoing
    /// notifications and signups come from it).
    func signIn(_ user: TestUser) async throws {
        if let current = Auth.auth().currentUser?.uid, current != user.uid {
            // Switch accounts the way the app does — log out first, which stops the previous
            // user's chat and preview listeners — instead of signing in over the top.
            try Auth.auth().signOut()
            try await settle(0.3)
        }
        if Auth.auth().currentUser?.uid != user.uid {
            try await Auth.auth().signIn(withEmail: user.email, password: user.password)
        }
        // A read issued while Auth is swapping tokens can fail, so ask again until the profile arrives
        var lastRequest = Date.distantPast
        try await eventually("\(user.name)'s profile to load", timeout: 20) {
            let loaded: Bool
            switch user.role {
            case .coach: loaded = self.fm.currentCoach?.id == user.uid
            case .client: loaded = self.fm.currentClient?.id == user.uid
            }
            if !loaded && Date().timeIntervalSince(lastRequest) > 2 {
                self.fm.fetchCurrentProfiles(for: user.uid)
                lastRequest = Date()
            }
            return loaded
        }
    }

    // MARK: - Waiting

    /// Runs a callback-style API and returns the first value it calls back with.
    func value<T>(_ what: String = "callback", timeout: TimeInterval = 15, _ body: (@escaping (T) -> Void) -> Void) async throws -> T {
        let exp = expectation(description: what)
        exp.assertForOverFulfill = false
        var results: [T] = []
        body { v in
            if results.isEmpty { results.append(v) }
            exp.fulfill()
        }
        await fulfillment(of: [exp], timeout: timeout)
        guard let first = results.first else { throw TestError.timedOut(what) }
        return first
    }

    // succeed/outcome are generic (E is always `any Error`): the non-generic form with an existential
    // nested in the closure type trips "escaping local function captures non-escaping value" in async code.

    /// Runs an API whose completion reports `Error?` and fails the test if it reports an error.
    func succeed<E: Error>(_ what: String, timeout: TimeInterval = 15, _ body: (@escaping (E?) -> Void) -> Void) async throws {
        let exp = expectation(description: what)
        exp.assertForOverFulfill = false
        var called = false
        var failure: E?
        body { error in
            if !called { called = true; failure = error }
            exp.fulfill()
        }
        await fulfillment(of: [exp], timeout: timeout)
        guard called else { throw TestError.timedOut(what) }
        if let failure {
            XCTFail("\(what) failed: \(failure.localizedDescription)")
            throw failure
        }
    }

    /// Runs an API whose completion reports `Error?` and returns that error (nil when it succeeded).
    func outcome<E: Error>(_ what: String, timeout: TimeInterval = 15, _ body: (@escaping (E?) -> Void) -> Void) async throws -> E? {
        let exp = expectation(description: what)
        exp.assertForOverFulfill = false
        var called = false
        var result: E?
        body { error in
            if !called { called = true; result = error }
            exp.fulfill()
        }
        await fulfillment(of: [exp], timeout: timeout)
        guard called else { throw TestError.timedOut(what) }
        return result
    }

    /// Polls until `condition` holds; fails the test (and stops it) after `timeout`.
    func eventually(_ what: String, timeout: TimeInterval = 10, _ condition: () async throws -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if try await condition() { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        } while Date() < deadline
        XCTFail("Timed out waiting for \(what)")
        throw TestError.timedOut(what)
    }

    /// Gives fire-and-forget writes (notifications, follow-up promotions) time to land.
    func settle(_ seconds: Double = 1.0) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    // MARK: - Data

    func data(_ path: String) async throws -> [String: Any]? {
        try await db.document(path).getDocument(source: .server).data()
    }

    func exists(_ path: String) async throws -> Bool {
        try await db.document(path).getDocument(source: .server).exists
    }

    func seed(_ path: String, _ fields: [String: Any]) async throws {
        try await db.document(path).setData(fields)
    }

    func docs(_ collectionPath: String) async throws -> [QueryDocumentSnapshot] {
        try await db.collection(collectionPath).getDocuments(source: .server).documents
    }

    /// Push payloads queued for `uid` (the pendingNotifications Cloud Function forwards these to FCM).
    func notifications(for uid: String) async throws -> [[String: Any]] {
        try await docs("pendingNotifications/\(uid)/notifications").map { $0.data() }
    }
}

extension Date {
    /// A whole-minute time `days` from now (avoids sub-second noise in timestamp comparisons).
    static func inDays(_ days: Double, hour: Int = 18) -> Date {
        let base = Calendar.current.date(byAdding: .day, value: Int(days), to: Date())!
        return Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: base)!
    }
}

/// Notification types both apps route when tapped. iOS routes by payload ids, Android by `type`
/// (NotificationService.deepLinkFor); a push lands on the right screen on both only if it carries
/// one of these types (chat pushes route by `chatId` on both).
let crossPlatformNotificationTypes: Set<String> = [
    "booking_request", "booking_confirmed", "payment_submitted", "booking_accepted", "booking_rejected",
    "booking_rescheduled", "booking_declined", "payment_acknowledged", "payment_confirmed", "payment_reminder",
    "booking_cancelled", "stringer_order", "club_join_request", "club_approved", "club_announcement",
    "event_waitlist_promoted", "tournament_partner", "tournament_recommendation"
]
