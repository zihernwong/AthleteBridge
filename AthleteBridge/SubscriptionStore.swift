import StoreKit
import FirebaseAuth
import FirebaseFirestore

/// Manages StoreKit 2 subscription state for coach tiers.
/// Listens for transaction updates and syncs the active entitlement to Firestore.
@MainActor
final class SubscriptionStore: ObservableObject {

    // MARK: - Product IDs — must match App Store Connect exactly
    static let plusProductID = "AthleteBridge.coach.plus.monthly"
    static let proProductID  = "AthleteBridge.coach.pro.monthly"

    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs: Set<String> = []
    @Published private(set) var purchasingProductID: String? = nil
    @Published var isLoadingProducts = false
    @Published var productsLoadFailed = false
    @Published var errorMessage: String?

    private var updateListenerTask: Task<Void, Never>?
    private let db = Firestore.firestore()

    init() {
        // Start listening for StoreKit transaction updates before any other work
        updateListenerTask = listenForTransactions()
        Task { await loadProducts() }
        Task { await refreshEntitlements() }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - Products

    func loadProducts() async {
        isLoadingProducts = true
        productsLoadFailed = false
        defer { isLoadingProducts = false }
        do {
            let loaded = try await Product.products(for: [Self.plusProductID, Self.proProductID])
            if loaded.isEmpty {
                print("[SubscriptionStore] Product.products returned empty — check App Store Connect product IDs and status")
                productsLoadFailed = true
            } else {
                products = loaded.sorted { $0.price < $1.price }
                productsLoadFailed = false
            }
        } catch {
            print("[SubscriptionStore] Failed to load products: \(error)")
            productsLoadFailed = true
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async {
        purchasingProductID = product.id
        errorMessage = nil
        defer { purchasingProductID = nil }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await refreshEntitlements()
                await transaction.finish()
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Restore Purchases (required by App Store guidelines)

    func restore() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            errorMessage = "Restore failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Current tier derived from StoreKit entitlements

    var currentTier: CoachTier {
        if purchasedProductIDs.contains(Self.proProductID)  { return .pro }
        if purchasedProductIDs.contains(Self.plusProductID) { return .plus }
        return .free
    }

    /// Re-reads StoreKit current entitlements and syncs the result to Firestore.
    func refreshEntitlements() async {
        var active: Set<String> = []
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            if transaction.revocationDate == nil {
                active.insert(transaction.productID)
            }
        }
        purchasedProductIDs = active
        await syncTierToFirestore()
    }

    // MARK: - Private

    /// Marks a coach tier granted by an App Store subscription (the Android app tags its own "play").
    static let appStoreSource = "appstore"

    /// Runs on every launch. Only App Store-granted tiers are ever lowered here: a coach paying through
    /// Stripe or Google Play has no StoreKit entitlement on this device and must keep their tier. Clients
    /// (no coaches/{uid} doc) are left alone instead of being given a nameless coach profile.
    private func syncTierToFirestore() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let storeTier = currentTier
        let ref = db.collection("coaches").document(uid)
        for attempt in 1...3 {
            do {
                guard let data = try await ref.getDocument().data() else { return }
                let current = CoachTier(rawValue: (data["subscriptionTier"] as? String ?? "free").lowercased()) ?? .free
                let source = data["subscriptionSource"] as? String
                if storeTier != .free {
                    if storeTier == current {
                        // StoreKit confirms the stored tier: tag it so a later lapse is noticed
                        if source == nil { try await ref.updateData(["subscriptionSource": Self.appStoreSource]) }
                        return
                    }
                    // A higher tier paid for elsewhere stays
                    if source != Self.appStoreSource && storeTier.rank < current.rank { return }
                    try await ref.updateData(["subscriptionTier": storeTier.rawValue, "subscriptionSource": Self.appStoreSource])
                } else if source == Self.appStoreSource && current != .free {
                    // The App Store subscription ended
                    try await ref.updateData(["subscriptionTier": CoachTier.free.rawValue, "subscriptionSource": FieldValue.delete()])
                }
                return
            } catch {
                print("[SubscriptionStore] syncTierToFirestore attempt \(attempt) failed: \(error)")
                if attempt < 3 {
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
                }
            }
        }
        print("[SubscriptionStore] syncTierToFirestore gave up after 3 attempts — tier may be stale in Firestore")
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self else { break }
                if let transaction = try? await self.checkVerified(result) {
                    await self.refreshEntitlements()
                    await transaction.finish()
                }
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified: throw SubscriptionStoreError.failedVerification
        case .verified(let value): return value
        }
    }

    enum SubscriptionStoreError: Error {
        case failedVerification
    }
}
