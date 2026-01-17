import SwiftUI

struct PaymentsView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel

    @State private var platform: String = "Paypal"
    @State private var username: String = ""
    @State private var errorMessage: String? = nil
    @State private var isSaving: Bool = false
    @State private var localPayments: [String: String] = [:]

    private let paymentOptions: [String] = ["Paypal", "Venmo", "Zelle"]

    private var payments: [String: String] {
        // Fallback to manager if local state is empty and manager has data
        if !localPayments.isEmpty { return localPayments }
        return firestore.currentCoach?.payments ?? [:]
    }

    private var isCoach: Bool {
        // conservative: require currentCoach profile present
        if let uid = auth.user?.uid, firestore.currentCoach?.id == uid { return true }
        return (firestore.currentUserType ?? "").uppercased() == "COACH"
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "creditcard")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(.accentColor)
                Text("Payments")
                    .font(.title2).bold()
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !isCoach {
                Text("Only coaches can set payment preferences.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Existing saved payments list
            if !payments.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Saved Payment Handles")
                        .font(.headline)
                    ForEach(payments.sorted(by: { $0.key.lowercased() < $1.key.lowercased() }), id: \.key) { key, value in
                        HStack {
                            Text(key.capitalized)
                            Spacer()
                            Text(value)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 6)
                        Divider().opacity(0.2)
                    }
                }
            } else {
                Text("No payment handles saved yet.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Input form for new/updated payment entry
            VStack(spacing: 10) {
                // Platform dropdown
                HStack {
                    Text("Platform")
                    Spacer()
                    Picker("Platform", selection: $platform) {
                        ForEach(paymentOptions, id: \.self) { opt in
                            Text(opt).tag(opt)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .padding(10)
                .background(Color(UIColor.systemGray6))
                .cornerRadius(8)

                // Username/handle text field
                HStack {
                    TextField("Username/handle for this platform", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .disableAutocorrection(true)
                }
                .padding(10)
                .background(Color(UIColor.systemGray6))
                .cornerRadius(8)

                Button(action: saveEntry) {
                    if isSaving { ProgressView().progressViewStyle(.circular) }
                    Text(isSaving ? "Saving…" : "Save Payment")
                        .bold()
                        .frame(maxWidth: .infinity)
                }
                .disabled(!isCoach || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                .buttonStyle(.borderedProminent)
            }

            if let err = errorMessage {
                Text(err)
                    .foregroundColor(.red)
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
        }
        .padding()
        .onAppear {
            // Initialize local payments from manager
            localPayments = firestore.currentCoach?.payments ?? [:]
        }
        .onChange(of: firestore.currentCoach?.payments ?? [:]) { _, newValue in
            // Keep local state in sync if manager updates behind the scenes
            localPayments = newValue
        }
    }

    private func saveEntry() {
        errorMessage = nil
        let key = platform.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let value = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty && !value.isEmpty else { return }
        guard isCoach else { errorMessage = "You must be a coach to update payments."; return }

        // Merge with existing map
        var next = payments
        next[key] = value
        isSaving = true
        FirestoreManager.shared.updateCurrentCoachPayments(next) { err in
            isSaving = false
            if let err = err {
                errorMessage = "Failed to save: \(err.localizedDescription)"
            } else {
                // Refresh local list immediately
                localPayments = next
                username = ""
            }
        }
    }
}

struct PaymentsView_Previews: PreviewProvider {
    static var previews: some View {
        PaymentsView().environmentObject(FirestoreManager()).environmentObject(AuthViewModel())
    }
}
