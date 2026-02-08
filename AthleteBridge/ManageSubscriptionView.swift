import SwiftUI
import FirebaseAuth

struct ManageSubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var auth: AuthViewModel
    @EnvironmentObject var firestore: FirestoreManager

    @State private var processingTier: CoachTier? = nil
    @State private var showErrorAlert = false
    @State private var errorMessage: String?

    // Stripe Price IDs for each paid tier
    private let plusPriceId = "price_1SxAIYCwBbNOdG5zZNx22J39"
    private let proPriceId = "price_1SxFtwCwBbNOdG5zLXuos2Yt"

    private var currentTier: CoachTier {
        firestore.currentCoach?.subscriptionTier ?? .free
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Current plan header
                    VStack(spacing: 6) {
                        Text("Current Plan")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(currentTier.displayName)
                            .font(.title2)
                            .bold()
                            .foregroundColor(colorForTier(currentTier))
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(UIColor.secondarySystemBackground)))
                    .padding(.horizontal)

                    // Tier cards
                    VStack(spacing: 12) {
                        tierCard(tier: .free, price: nil)
                        tierCard(tier: .plus, price: "Coach Plus")
                        tierCard(tier: .pro, price: "Coach Pro")
                    }
                    .padding(.horizontal)

                    // Billing portal for existing subscribers
                    if currentTier != .free {
                        Button(action: openBillingPortal) {
                            HStack {
                                Image(systemName: "creditcard")
                                Text("Manage Billing")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary, lineWidth: 1))
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Subscription")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert(isPresented: $showErrorAlert) {
                Alert(title: Text("Error"), message: Text(errorMessage ?? "Unknown error"), dismissButton: .default(Text("OK")))
            }
            .onAppear {
                // Sync subscription tier from Stripe and start listening for updates
                if let uid = auth.user?.uid {
                    firestore.syncSubscriptionTierFromStripe(for: uid)
                    firestore.startSubscriptionListener(for: uid)
                }
            }
            .onDisappear {
                firestore.stopSubscriptionListener()
            }
            .onChange(of: scenePhase) { newPhase in
                // Refresh subscription when app comes back to foreground (after Safari dismissal)
                if newPhase == .active, let uid = auth.user?.uid {
                    print("[ManageSubscriptionView] App became active, syncing subscription")
                    firestore.syncSubscriptionTierFromStripe(for: uid)
                }
            }
        }
    }

    // MARK: - Tier Card

    @ViewBuilder
    private func tierCard(tier: CoachTier, price: String?) -> some View {
        let isCurrent = tier == currentTier
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(tier.displayName)
                    .font(.headline)
                    .foregroundColor(colorForTier(tier))
                Spacer()
                if isCurrent {
                    Text("Current")
                        .font(.caption)
                        .bold()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(colorForTier(tier).opacity(0.2)))
                        .foregroundColor(colorForTier(tier))
                }
            }

            if tier == .free {
                Text("Basic coaching profile")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else if tier == .plus {
                Text("Enhanced coaching features")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Text("Full access to all features")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if !isCurrent && tier != .free {
                let isThisTierProcessing = processingTier == tier
                Button(action: { startCheckout(for: tier) }) {
                    HStack {
                        if isThisTierProcessing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        }
                        Text(isThisTierProcessing ? "Starting checkout..." : "Subscribe to \(tier.displayName)")
                            .bold()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(colorForTier(tier)))
                    .foregroundColor(.white)
                }
                .disabled(processingTier != nil || auth.user == nil)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(UIColor.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isCurrent ? colorForTier(tier) : Color.clear, lineWidth: 2)
        )
    }

    // MARK: - Actions

    private func startCheckout(for tier: CoachTier) {
        guard let uid = auth.user?.uid else {
            show(error: "You must be signed in to subscribe.")
            return
        }

        let priceId: String
        switch tier {
        case .plus: priceId = plusPriceId
        case .pro: priceId = proPriceId
        case .free: return
        }

        processingTier = tier

        let success = "https://athletebridge-63176.web.app/stripe/success?session_id={CHECKOUT_SESSION_ID}"
        let cancel = "https://athletebridge-63176.web.app/stripe/cancel"

        StripeCheckoutManager.shared.startCheckout(priceId: priceId, mode: "subscription", successURL: success, cancelURL: cancel, metadata: ["uid": uid]) { result in
            DispatchQueue.main.async {
                self.processingTier = nil
                switch result {
                case .success:
                    break
                case .failure(let err):
                    show(error: err.localizedDescription)
                }
            }
        }
    }

    private func openBillingPortal() {
        print("[ManageSubscriptionView] openBillingPortal called")
        StripeCheckoutManager.shared.openBillingPortal(returnURL: "https://athletebridge-63176.web.app/stripe/success") { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    print("[ManageSubscriptionView] Billing portal opened successfully")
                case .failure(let err):
                    print("[ManageSubscriptionView] Billing portal error: \(err)")
                    self.show(error: err.localizedDescription)
                }
            }
        }
    }

    private func show(error: String) {
        errorMessage = error
        showErrorAlert = true
    }

    private func colorForTier(_ tier: CoachTier) -> Color {
        switch tier {
        case .free: return .gray
        case .plus: return .blue
        case .pro: return .purple
        }
    }
}
