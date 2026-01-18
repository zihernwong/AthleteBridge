import SwiftUI

struct PaymentsView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel

    @State private var platform: String = "Paypal"
    @State private var username: String = ""
    @State private var errorMessage: String? = nil
    @State private var isSaving: Bool = false
    @State private var localPayments: [String: String] = [:]
    @State private var showPaid: Bool = false // keep paid collapsed so unpaid dominates

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

    // Split bookings by payment status for clients
    private var paidBookings: [FirestoreManager.BookingItem] {
        firestore.bookings.filter { ($0.paymentStatus ?? "").lowercased() == "paid" }
    }
    private var unpaidBookings: [FirestoreManager.BookingItem] {
        firestore.bookings.filter { ($0.paymentStatus ?? "").lowercased() != "paid" }
    }

    // Helper: resolve coach name from a booking's coachID, falling back to booking.coachName
    private func nameForCoachId(_ coachId: String?) -> String? {
        guard let id = coachId, !id.isEmpty else { return nil }
        if let coach = firestore.coaches.first(where: { $0.id == id }) {
            return coach.name
        }
        return nil
    }

    private func coachDisplayName(for booking: FirestoreManager.BookingItem) -> String {
        return nameForCoachId(booking.coachID) ?? booking.coachName ?? "Coach"
    }

    // Helper: trigger payment flow for an unpaid booking
    private func makePayment(for booking: FirestoreManager.BookingItem) {
        let returnURL = "https://athletebridge.app/payments/return"
        StripeCheckoutManager.shared.openBillingPortal(returnURL: returnURL) { result in
            switch result {
            case .success:
                break
            case .failure(let err):
                DispatchQueue.main.async { self.errorMessage = "Unable to open payment portal: \(err.localizedDescription)" }
            }
        }
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

            // Input form for new/updated payment entry — SHOW ONLY FOR COACHES
            if isCoach {
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
                    .disabled(username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                    .buttonStyle(.borderedProminent)
                }
            }

            if let err = errorMessage {
                Text(err)
                    .foregroundColor(.red)
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Previous bookings for clients — emphasize Unpaid
            if (firestore.currentUserType ?? "").uppercased() == "CLIENT" {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Previous Bookings")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if firestore.bookings.isEmpty {
                        Text("No previous bookings found.")
                            .foregroundColor(.secondary)
                    } else {
                        // Unpaid section (dominant area)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Unpaid")
                                .font(.subheadline).bold()
                            if unpaidBookings.isEmpty {
                                Text("No unpaid bookings.")
                                    .foregroundColor(.secondary)
                            } else {
                                ScrollView {
                                    VStack(spacing: 12) {
                                        ForEach(unpaidBookings, id: \.id) { b in
                                            bookingRow(for: b)
                                            Divider().opacity(0.15)
                                        }
                                    }
                                    .padding(.bottom, 4)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(maxHeight: .infinity, alignment: .top)
                            }
                        }
                        .padding(.top, 4)
                        .frame(maxWidth: .infinity)

                        // Paid section (collapsed by default)
                        if !paidBookings.isEmpty {
                            DisclosureGroup(isExpanded: $showPaid) {
                                VStack(alignment: .leading, spacing: 8) {
                                    ScrollView {
                                        VStack(spacing: 12) {
                                            ForEach(paidBookings, id: \.id) { b in
                                                bookingRow(for: b)
                                                Divider().opacity(0.15)
                                            }
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                            } label: {
                                HStack {
                                    Text("Paid")
                                        .font(.subheadline).bold()
                                    Spacer()
                                    Text("\(paidBookings.count)")
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.top, 8)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }

            Spacer(minLength: 0)
        }
        .padding()
        .onAppear {
            // Initialize local payments from manager
            localPayments = firestore.currentCoach?.payments ?? [:]
            // For clients, fetch their bookings to show statuses
            if let uid = auth.user?.uid { firestore.fetchBookingsForCurrentClientSubcollection() }
            // Load coaches for id->name mapping
            firestore.fetchCoaches()
        }
        .onChange(of: firestore.currentCoach?.payments ?? [:]) { _, newValue in
            // Keep local state in sync if manager updates behind the scenes
            localPayments = newValue
        }
    }

    private func bookingRow(for b: FirestoreManager.BookingItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(coachDisplayName(for: b)).font(.headline)
                Spacer()
                Text((b.paymentStatus ?? "").capitalized)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if let start = b.startAt {
                Text("Start: \(DateFormatter.localizedString(from: start, dateStyle: .medium, timeStyle: .short))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            if let end = b.endAt {
                Text("End: \(DateFormatter.localizedString(from: end, dateStyle: .medium, timeStyle: .short))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            if let notes = b.notes, !notes.isEmpty {
                Text(notes).font(.footnote).foregroundColor(.secondary)
            }

            // Show Make Payment button only for unpaid bookings
            if (b.paymentStatus ?? "").lowercased() != "paid" {
                HStack {
                    Spacer()
                    Button(action: { makePayment(for: b) }) {
                        Text("Make Payment")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 6)
            }
        }
        .padding(.vertical, 8)
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
