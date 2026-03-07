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

    private func syncTierToFirestore() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let tierValue = currentTier.rawValue
        try? await db.collection("coaches").document(uid)
            .setData(["subscriptionTier": tierValue], mergeFields: ["subscriptionTier"])
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
