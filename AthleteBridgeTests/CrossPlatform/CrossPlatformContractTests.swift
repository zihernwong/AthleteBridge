import XCTest
@testable import AthleteBridge

/// contract.json "pushRouting" and "vectors": the routing table and shared logic both apps must agree on.
/// (No emulator needed; these run even when the Firestore tests are skipped.)
@MainActor
final class CrossPlatformContractTests: XCTestCase {

    private func cases(_ name: String) -> [[String: Any]] {
        ((CrossPlatform.contract["vectors"] as! [String: Any])[name] as! [Any]).map { $0 as! [String: Any] }
    }

    func testEveryPushTypeInTheContractOpensTheAgreedScreenOnIOS() {
        let seed = Seeder()
        let problems = PushRoutes.routes.compactMap { route -> String? in
            var notification: [String: Any] = route.data.mapValues { seed.text($0) }
            notification["type"] = route.type
            return PushRoutes.problem(notification, recipient: seed.id("client"))
        }
        XCTAssertEqual(problems, [], "Push types that open the wrong screen (or nothing) on iOS")
    }

    func testTheCloudFunctionForwardsEveryIdARouterReads() {
        // Both apps read these from a push to open the right screen; a key the function drops never arrives.
        let readByRouters: Set<String> = ["chatId", "bookingId", "stringerOrderId", "placeId", "announcementId", "eventId", "type"]
        XCTAssertEqual(readByRouters.subtracting(CloudFunction.forwardedKeys), [],
                       "Keys the apps route on that onPendingNotificationCreate doesn't forward")
    }

    func testPaymentLinksMatchTheContract() {
        let wrong = cases("paymentLinks").compactMap { c -> String? in
            let platform = c["platform"] as! String
            let handle = c["handle"] as! String
            let expected = c["url"] as? String
            let actual = PaymentLinks.deepLink(platform: platform, handle: handle)?.absoluteString
            return actual == expected ? nil : "\(platform) \"\(handle)\": expected \(expected ?? "nil"), got \(actual ?? "nil")"
        }
        XCTAssertEqual(wrong, [], "Payment links that differ from the contract (and so from Android)")
    }

    func testEffectiveCoachTierMatchesTheContract() {
        let wrong = cases("effectiveTier").compactMap { c -> String? in
            var doc: [String: Any] = [:]
            if let sub = c["subscriptionTier"] as? String { doc["subscriptionTier"] = sub }
            if let life = c["lifetimeTier"] as? String { doc["lifetimeTier"] = life }
            let actual = CoachTier.effectiveTier(from: doc).rawValue
            return actual == c["tier"] as? String ? nil : "\(doc): expected \(c["tier"] ?? "nil"), got \(actual)"
        }
        XCTAssertEqual(wrong, [], "Tier rules that differ from the contract (and so from Android)")
    }

    func testTournamentPartnerMatchingMatchesTheContract() {
        let wrong = cases("partnersCompatible").compactMap { c -> String? in
            let a = c["a"] as! [String: Any]
            let b = c["b"] as! [String: Any]
            let other = TournamentParticipantInfo(gender: b["gender"] as! String, events: b["events"] as! [String], skillLevels: b["skillLevels"] as! [String])
            let actual = FirestoreManager.partnersCompatible(gender: a["gender"] as! String, events: Set(a["events"] as! [String]),
                                                             skillLevels: Set(a["skillLevels"] as! [String]), with: other)
            return actual == c["compatible"] as? Bool ? nil : "\(a) with \(b): expected \(c["compatible"] ?? "nil"), got \(actual)"
        }
        XCTAssertEqual(wrong, [], "Partner matches that differ from the contract (and so from Android)")
    }
}
