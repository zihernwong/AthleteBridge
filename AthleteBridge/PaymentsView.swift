import SwiftUI

struct PaymentsView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel

    @State private var platform: String = "Paypal"
    @State private var username: String = ""
    @State private var errorMessage: String? = nil
    @State private var isSaving: Bool = false
    @State private var localPayments: [String: String] = [:]

    // New state: present coach payment methods for an unpaid booking
    @State private var showCoachPaymentsSheet: Bool = false
    @State private var selectedCoachPayments: [String: String] = [:]
    @State private var selectedCoachName: String = "Coach"

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

    // Helper: trigger payment flow for an unpaid booking — now fetch and show coach payment methods
    private func makePayment(for booking: FirestoreManager.BookingItem) {
        // Resolve coach ID string (uid or path tolerated by helper)
        let coachId = booking.coachID
        guard !coachId.isEmpty else {
            self.errorMessage = "Missing coach ID for this booking."
            return
        }
        // Fetch payments and coach name, then present sheet
        FirestoreManager.shared.fetchCoachPayments(coachIdOrPath: coachId) { map in
            DispatchQueue.main.async {
                self.selectedCoachPayments = map
                self.selectedCoachName = self.coachDisplayName(for: booking)
                self.showCoachPaymentsSheet = true
            }
        }
        // Optionally also refresh name from Firestore if local cache lacked it
        FirestoreManager.shared.fetchCoachDisplayName(coachIdOrPath: coachId) { name in
            DispatchQueue.main.async {
                if !name.isEmpty { self.selectedCoachName = name }
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

            // Previous bookings for clients — show PaymentStatus
            if (firestore.currentUserType ?? "").uppercased() == "CLIENT" {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Previous Bookings")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if firestore.bookings.isEmpty {
                        Text("No previous bookings found.")
                            .foregroundColor(.secondary)
                    } else {
                        // Unpaid section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Unpaid")
                                .font(.subheadline).bold()
                            if unpaidBookings.isEmpty {
                                Text("No unpaid bookings.")
                                    .foregroundColor(.secondary)
                            } else {
                                ScrollView {
                                    VStack(spacing: 12) {
                                        ForEach(unpaidBookings, id: \ .id) { b in
                                            bookingRow(for: b)
                                            Divider().opacity(0.15)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.top, 4)

                        // Paid section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Paid")
                                .font(.subheadline).bold()
                            if paidBookings.isEmpty {
                                Text("No paid bookings.")
                                    .foregroundColor(.secondary)
                            } else {
                                ScrollView {
                                    VStack(spacing: 12) {
                                        ForEach(paidBookings, id: \ .id) { b in
                                            bookingRow(for: b)
                                            Divider().opacity(0.15)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.top, 12)
                    }
                }
            }

            Spacer()
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
        // Present a sheet with the coach's payment methods when requested
        .sheet(isPresented: $showCoachPaymentsSheet) {
            NavigationStack {
                List {
                    if selectedCoachPayments.isEmpty {
                        Section("Payment Methods") {
                            Text("No payment methods provided yet.")
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Section("Payment Methods") {
                            ForEach(selectedCoachPayments.sorted(by: { $0.key.lowercased() < $1.key.lowercased() }), id: \.key) { key, value in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(key.capitalized).bold()
                                        Spacer()
                                        Text(value).foregroundColor(.secondary)
                                    }
                                    // Provide simple deep links for common platforms
                                    if let url = paymentDeepLink(for: key, value: value) {
                                        Link("Open \(key.capitalized)", destination: url)
                                            .font(.footnote)
                                    }
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Pay \(selectedCoachName)")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { showCoachPaymentsSheet = false }
                    }
                }
            }
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
            // Show RateUSD for this booking
            Text(rateUSD(for: b))
                .font(.subheadline)
                .foregroundColor(.secondary)
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

    // Resolve the USD rate directly from the booking's RateUSD field using reflection (works for Swift structs)
    private func rateUSD(for booking: FirestoreManager.BookingItem) -> String {
        let mirror = Mirror(reflecting: booking)
        if let child = mirror.children.first(where: { $0.label == "RateUSD" || $0.label == "rateUSD" }) {
            // Handle Double
            if let rate = child.value as? Double {
                return String(format: "$%.0f/hr", rate)
            }
            // Handle String
            if let rateStr = child.value as? String, !rateStr.isEmpty {
                return rateStr.contains("$") ? rateStr : "$\(rateStr)/hr"
            }
        }
        return "Rate: N/A"
    }

    // Build a deep link URL for common platforms
    private func paymentDeepLink(for key: String, value: String) -> URL? {
        let k = key.lowercased()
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.isEmpty { return nil }
        switch k {
        case "venmo":
            return URL(string: "https://venmo.com/u/\(v)")
        case "paypal":
            // support paypal.me handles or email (email won’t deep link reliably)
            if v.range(of: "^[A-Za-z0-9.-_]+$", options: .regularExpression) != nil {
                return URL(string: "https://paypal.me/\(v)")
            }
            return nil
        case "cashapp":
            return URL(string: "https://cash.app/\(v)")
        case "zelle":
            return nil // banking deep link not standardized
        default:
            return nil
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
