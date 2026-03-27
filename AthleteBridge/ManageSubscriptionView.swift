import SwiftUI
import StoreKit

struct ManageSubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @EnvironmentObject var auth: AuthViewModel
    @EnvironmentObject var firestore: FirestoreManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    currentPlanHeader

                    if subscriptionStore.productsLoadFailed {
                        VStack(spacing: 12) {
                            Text("Could not load subscription plans.")
                                .foregroundColor(.secondary)
                            Button("Retry") {
                                Task { await subscriptionStore.loadProducts() }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.top, 40)
                    } else if subscriptionStore.isLoadingProducts || subscriptionStore.products.isEmpty {
                        ProgressView("Loading plans...")
                            .padding(.top, 40)
                    } else {
                        productCards
                    }

                    // Restore Purchases — required by App Store guidelines
                    Button("Restore Purchases") {
                        Task { await subscriptionStore.restore() }
                    }
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)

                    // Privacy Policy and Terms of Use — required by App Store guideline 3.1.2(c)
                    HStack(spacing: 16) {
                        Link("Privacy Policy", destination: URL(string: "https://athletebridge-63176.web.app/privacy/")!)
                        Text("·").foregroundColor(.secondary)
                        Link("Terms of Use", destination: URL(string: "https://athletebridge-63176.web.app/terms/")!)
                    }
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)

                    // Opens Apple's native subscription management UI
                    if subscriptionStore.currentTier != .free {
                        Button(action: openSystemSubscriptionManager) {
                            HStack {
                                Image(systemName: "creditcard")
                                Text("Manage Subscription")
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Error", isPresented: Binding(
                get: { subscriptionStore.errorMessage != nil },
                set: { if !$0 { subscriptionStore.errorMessage = nil } }
            )) {
                Button("OK") { subscriptionStore.errorMessage = nil }
            } message: {
                Text(subscriptionStore.errorMessage ?? "")
            }
            .task {
                // Refresh StoreKit entitlements (writes tier to Firestore on change)
                await subscriptionStore.refreshEntitlements()
                if subscriptionStore.products.isEmpty {
                    await subscriptionStore.loadProducts()
                }
            }
            .onAppear {
                // Real-time listener keeps firestore.currentCoach.subscriptionTier in sync
                // so PaymentsView and AcceptBookingView gate features correctly
                if let uid = auth.user?.uid {
                    firestore.startSubscriptionListener(for: uid)
                }
            }
            .onDisappear {
                firestore.stopSubscriptionListener()
            }
        }
    }

    // MARK: - Subviews

    private var currentPlanHeader: some View {
        let tier = subscriptionStore.currentTier
        return VStack(spacing: 6) {
            Text("Current Plan")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(tier.displayName)
                .font(.title2)
                .bold()
                .foregroundColor(colorForTier(tier))
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(UIColor.secondarySystemBackground)))
        .padding(.horizontal)
    }

    private var productCards: some View {
        VStack(spacing: 12) {
            tierCard(tier: .free, product: nil)
            ForEach(subscriptionStore.products, id: \.id) { product in
                tierCard(tier: tierFor(productID: product.id), product: product)
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func tierCard(tier: CoachTier, product: Product?) -> some View {
        let isCurrent = tier == subscriptionStore.currentTier
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(tier.displayName)
                    .font(.headline)
                    .foregroundColor(colorForTier(tier))
                Spacer()
                if isCurrent {
                    Text("Current")
                        .font(.caption).bold()
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(colorForTier(tier).opacity(0.2)))
                        .foregroundColor(colorForTier(tier))
                }
                if let product {
                    Text(product.displayPrice + "/mo")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            featureList(for: tier)

            if !isCurrent, let product {
                let isThisProcessing = subscriptionStore.purchasingProductID == product.id
                let anyProcessing = subscriptionStore.purchasingProductID != nil
                Button {
                    Task { await subscriptionStore.purchase(product) }
                } label: {
                    HStack {
                        if isThisProcessing {
                            ProgressView().progressViewStyle(CircularProgressViewStyle())
                        }
                        Text(isThisProcessing ? "Processing..." : "Subscribe – \(product.displayPrice)/mo")
                            .bold()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(colorForTier(tier)))
                    .foregroundColor(.white)
                }
                .disabled(anyProcessing)

                // Required by App Store guideline 3.1.2(c)
                VStack(spacing: 3) {
                    Text("Auto-renews monthly at \(product.displayPrice). Cancel anytime.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                    HStack(spacing: 4) {
                        Link("Terms of Use", destination: URL(string: "https://athletebridge-63176.web.app/terms/")!)
                        Text("·").foregroundColor(.secondary)
                        Link("Privacy Policy", destination: URL(string: "https://athletebridge-63176.web.app/privacy/")!)
                    }
                    .font(.caption2)
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(UIColor.secondarySystemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isCurrent ? colorForTier(tier) : Color.clear, lineWidth: 2))
    }

    @ViewBuilder
    private func featureList(for tier: CoachTier) -> some View {
        switch tier {
        case .free:
            Text("Basic coaching profile")
                .font(.subheadline).foregroundColor(.secondary)
        case .plus:
            Label("Revenue Insights", systemImage: "chart.bar.fill")
                .font(.subheadline).foregroundColor(.secondary)
        case .pro:
            VStack(alignment: .leading, spacing: 4) {
                Label("Revenue Insights", systemImage: "chart.bar.fill")
                    .font(.subheadline).foregroundColor(.secondary)
                Label("Listed in Coach Search Engine", systemImage: "magnifyingglass")
                    .font(.subheadline).foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private func tierFor(productID: String) -> CoachTier {
        switch productID {
        case SubscriptionStore.proProductID:  return .pro
        case SubscriptionStore.plusProductID: return .plus
        default: return .free
        }
    }

    private func colorForTier(_ tier: CoachTier) -> Color {
        switch tier {
        case .free: return .gray
        case .plus: return .blue
        case .pro:  return .purple
        }
    }

    private func openSystemSubscriptionManager() {
        guard #available(iOS 15, *) else { return }
        guard let windowScene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
        Task { try? await AppStore.showManageSubscriptions(in: windowScene) }
    }
}
