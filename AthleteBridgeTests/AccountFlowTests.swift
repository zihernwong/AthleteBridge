import XCTest
import FirebaseFirestore
@testable import AthleteBridge

/// Profiles and coach subscription tiers.
@MainActor
final class AccountFlowTests: EmulatorTestCase {

    // MARK: - Coach profile

    func testACoachsSavedZipAndCityLoadIntoTheirProfile() async throws {
        let coach = try await makeUser(.coach, first: "Casey", profile: ["ZipCode": "55413", "City": "Minneapolis"])
        try await signIn(coach)
        XCTAssertEqual(fm.currentCoach?.zipCode, "55413", "the profile editor shows coaches an empty ZIP")
        XCTAssertEqual(fm.currentCoach?.city, "Minneapolis")
    }

    func testATierChangeKeepsTheRestOfTheCoachProfile() async throws {
        let link = "https://www.tournamentsoftware.com/player/123"
        let coach = try await makeUser(.coach, first: "Casey", profile: [
            "cancellationWindowHours": 24, "phoneVerified": true, "tournamentSoftwareLink": link, "subscriptionTier": "free"
        ])
        try await signIn(coach)
        XCTAssertEqual(fm.currentCoach?.cancellationWindowHours, 24)
        fm.startSubscriptionListener(for: coach.uid)
        try await settle(0.5)
        // e.g. the Stripe webhook upgrading the coach while the app is open
        try await db.document("coaches/\(coach.uid)").updateData(["subscriptionTier": "pro"])
        try await eventually("the new tier") { self.fm.currentCoach?.subscriptionTier == .pro }
        let updated = try XCTUnwrap(fm.currentCoach)
        XCTAssertEqual(updated.cancellationWindowHours, 24, "saving the profile after this would wipe the cancellation policy")
        XCTAssertTrue(updated.phoneVerified, "the verified badge disappears")
        XCTAssertEqual(updated.tournamentSoftwareLink, link)
    }

    func testSavingTheCoachProfileKeepsBillingPaymentAndDeviceFields() async throws {
        let coach = try await makeUser(.coach, first: "Casey", profile: [
            "subscriptionTier": "pro", "subscriptionSource": "play", "lifetimeTier": "plus", "payments": ["venmo": "@casey"],
            "fcmTokens": ["token-1"], "stripeCustomerId": "cus_123", "calendar": [["id": "b1"]]
        ])
        try await signIn(coach)
        try await succeed("saveCoachWithSchema") { done in
            fm.saveCoachWithSchema(id: coach.uid, firstName: "Casey", lastName: "Tester", specialties: ["Badminton"],
                                   availability: ["Morning"], experienceYears: 4, hourlyRate: 60, photoURL: nil,
                                   cancellationWindowHours: 12, completion: done)
        }
        let d = try await data("coaches/\(coach.uid)") ?? [:]
        for key in ["subscriptionTier", "subscriptionSource", "lifetimeTier", "payments", "fcmTokens", "stripeCustomerId", "calendar"] {
            XCTAssertNotNil(d[key], "\(key) was erased")
        }
        XCTAssertEqual(d["Availability"] as? [String], ["Morning"])
        XCTAssertEqual(d["cancellationWindowHours"] as? Int, 12)
    }

    func testSavingTheClientProfileKeepsOtherFields() async throws {
        let client = try await makeUser(.client, first: "Pat", profile: ["fcmTokens": ["token-1"], "skillLevel": "Intermediate"])
        try await signIn(client)
        try await succeed("saveClient") { done in
            fm.saveClient(id: client.uid, name: "Pat Tester", goals: ["Footwork"], preferredAvailability: ["Weekends"],
                          zipCode: "55102", photoURL: nil, completion: done)
        }
        let d = try await data("clients/\(client.uid)") ?? [:]
        XCTAssertEqual(d["goals"] as? [String], ["Footwork"])
        XCTAssertEqual(d["zipCode"] as? String, "55102")
        XCTAssertNotNil(d["fcmTokens"])
        XCTAssertEqual(d["skillLevel"] as? String, "Intermediate", "skillLevel nil means leave unchanged")
    }

    // MARK: - App Store subscription sync (runs every time the app launches)

    /// Runs SubscriptionStore's StoreKit refresh for the signed-in user. The simulator has no App Store
    /// purchases, as for a client, a coach paying through Stripe, or one subscribed on Google Play.
    private func runAppStoreSync() async throws {
        let store = SubscriptionStore()
        var finished = false
        Task { @MainActor in
            await store.refreshEntitlements()
            finished = true
        }
        try await eventually("the StoreKit refresh", timeout: 20) { finished }
        try await settle(1)
        withExtendedLifetime(store) {}
    }

    func testAppStoreSyncDoesNotGiveClientsACoachProfile() async throws {
        let client = try await makeUser(.client, first: "Pat")
        try await signIn(client)
        try await runAppStoreSync()
        let created = try await exists("coaches/\(client.uid)")
        XCTAssertFalse(created, "every signed-in client gets a coaches/{uid} doc and appears in coach lists without a name")
    }

    func testAppStoreSyncKeepsATierPaidThroughStripe() async throws {
        let coach = try await makeUser(.coach, first: "Casey", profile: ["subscriptionTier": "pro"]) // written by the Stripe webhook
        try await signIn(coach)
        try await runAppStoreSync()
        let tier = try await data("coaches/\(coach.uid)")?["subscriptionTier"] as? String
        XCTAssertEqual(tier, "pro", "opening the iOS app drops a Stripe-paying coach to free")
    }

    func testAnAppStoreTierEndsWhenItsSubscriptionLapses() async throws {
        let coach = try await makeUser(.coach, first: "Riley", profile: ["subscriptionTier": "pro", "subscriptionSource": "appstore"])
        try await signIn(coach)
        try await runAppStoreSync()
        let d = try await data("coaches/\(coach.uid)") ?? [:]
        XCTAssertEqual(d["subscriptionTier"] as? String, "free")
        XCTAssertNil(d["subscriptionSource"])
    }

    func testAppStoreSyncKeepsATierPaidThroughGooglePlay() async throws {
        let coach = try await makeUser(.coach, first: "Morgan", profile: ["subscriptionTier": "plus", "subscriptionSource": "play"])
        try await signIn(coach)
        try await runAppStoreSync()
        let tier = try await data("coaches/\(coach.uid)")?["subscriptionTier"] as? String
        XCTAssertEqual(tier, "plus", "opening the iOS app drops a Google Play subscriber to free")
    }
}
