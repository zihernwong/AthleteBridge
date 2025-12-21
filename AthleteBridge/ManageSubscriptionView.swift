import SwiftUI
import FirebaseAuth

struct ManageSubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var auth: AuthViewModel
    @EnvironmentObject var firestore: FirestoreManager

    @State private var isProcessing = false
    @State private var showErrorAlert = false
    @State private var errorMessage: String?

    // Using the real Stripe Price ID provided earlier
    private var defaultPriceId: String { "price_1SfmO9CwBbNOdG5ziKfoylkl" }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Subscription")) {
                    if let user = auth.user {
                        Text("Signed in as: \(user.email ?? "Unknown")")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Please sign in to manage your subscription.")
                    }
                }

                Section {
                    Button(action: startCheckout) {
                        HStack {
                            if isProcessing { ProgressView().progressViewStyle(CircularProgressViewStyle()) }
                            Text(isProcessing ? "Starting checkout..." : "Manage / Subscribe")
                                .bold()
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .disabled(isProcessing || auth.user == nil)
                }

                Section(header: Text("Advanced / Debug")) {
                    Button("Open Billing Portal (if available)") {
                        openBillingPortal()
                    }
                }
            }
            .navigationTitle("Manage Subscription")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert(isPresented: $showErrorAlert) {
                Alert(title: Text("Error"), message: Text(errorMessage ?? "Unknown error"), dismissButton: .default(Text("OK")))
            }
        }
    }

    private func startCheckout() {
        guard let uid = auth.user?.uid else {
            show(error: "You must be signed in to subscribe.")
            return
        }
        isProcessing = true

        let priceId = defaultPriceId
        // Use the deployed Firebase Hosting URLs. Include the placeholder so Stripe will
        // substitute the real session id when redirecting.
        let success = "https://athletebridge-63176.web.app/stripe/success?session_id={CHECKOUT_SESSION_ID}"
        let cancel = "https://athletebridge-63176.web.app/stripe/cancel"

        StripeCheckoutManager.shared.startCheckout(priceId: priceId, mode: "subscription", successURL: success, cancelURL: cancel, metadata: ["uid": uid]) { result in
            DispatchQueue.main.async {
                self.isProcessing = false
                switch result {
                case .success:
                    // SFSafariViewController is presented by the manager; optionally dismiss this sheet
                    break
                case .failure(let err):
                    show(error: err.localizedDescription)
                }
            }
        }
    }

    private func openBillingPortal() {
        show(error: "Billing portal not configured. Configure firestore-stripe-payments portal_sessions to enable this.")
    }

    private func show(error: String) {
        errorMessage = error
        showErrorAlert = true
    }
}

// A minimal preview
struct ManageSubscriptionView_Previews: PreviewProvider {
    class DummyAuth: AuthViewModel { override init() { super.init(); self.user = nil } }
    class DummyFS: FirestoreManager { override init() { super.init() } }
    static var previews: some View {
        ManageSubscriptionView()
            .environmentObject(DummyAuth())
            .environmentObject(DummyFS())
    }
}
