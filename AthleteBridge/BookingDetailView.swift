import SwiftUI
import FirebaseFirestore

struct BookingDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel

    let booking: FirestoreManager.BookingItem

    // Payment-related state variables
    @State private var showCoachPaymentsSheet: Bool = false
    @State private var selectedCoachPayments: [String: String] = [:]
    @State private var selectedCoachName: String = "Coach"
    @State private var errorMessage: String? = nil
    @State private var showCoachPickerForNotify: Bool = false

    private var currentUserRole: String? {
        firestore.currentUserType?.uppercased()
    }

    private var isGroupBooking: Bool {
        booking.isGroupBooking ?? false ||
        (booking.coachIDs?.count ?? 0) > 1 ||
        (booking.clientIDs?.count ?? 0) > 1
    }

    private var coachDisplayName: String {
        if isGroupBooking && !booking.allCoachNames.isEmpty {
            return booking.allCoachNames.joined(separator: ", ")
        }
        return booking.coachName ?? "Coach"
    }

    private var clientDisplayName: String {
        if isGroupBooking && !booking.allClientNames.isEmpty {
            return booking.allClientNames.joined(separator: ", ")
        }
        return booking.clientName ?? "Client"
    }

    private func displayStatus(for status: String?) -> String {
        let raw = status ?? "Unknown"
        if raw.lowercased() == "declined_by_client" {
            return currentUserRole == "COACH" ? "Declined By Client" : "Declined"
        }
        return raw.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func statusColor(for status: String?) -> Color {
        switch (status ?? "").lowercased() {
        case "confirmed", "fully_confirmed":
            return Color("LogoGreen")
        case "requested":
            return Color("LogoBlue")
        case "pending acceptance":
            return .orange
        case "rejected", "declined", "declined_by_client", "cancelled":
            return .red
        case "partially_accepted", "partially_confirmed":
            return .orange
        default:
            return .secondary
        }
    }

    // Calculate duration in 0.5 hour increments
    private var durationHours: Double {
        guard let start = booking.startAt, let end = booking.endAt else { return 0 }
        let totalMinutes = end.timeIntervalSince(start) / 60
        let halfHours = (totalMinutes / 30).rounded()
        return halfHours * 0.5
    }

    private var durationMinutes: Int {
        guard let start = booking.startAt, let end = booking.endAt else { return 0 }
        return Int(end.timeIntervalSince(start) / 60)
    }

    // Calculate total booking cost
    private var totalBookingCost: Double? {
        if isGroupBooking {
            guard durationHours > 0 else { return nil }
            let rates = booking.coachRates ?? [:]
            guard !rates.isEmpty else { return nil }
            let totalRate = rates.values.reduce(0, +)
            return totalRate * durationHours
        } else {
            guard let rate = booking.RateUSD, durationHours > 0 else { return nil }
            return rate * durationHours
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Status Header
                    statusSection

                    // Booking Type
                    if isGroupBooking {
                        groupBadge
                    }

                    // Participants Section
                    participantsSection

                    // Date & Time Section
                    dateTimeSection

                    // Location Section
                    if let location = booking.location, !location.isEmpty {
                        locationSection(location)
                    }

                    // Rate & Cost Section
                    rateSection

                    // Payment Section (for unpaid confirmed bookings - client only)
                    if currentUserRole == "CLIENT" && 
                       (booking.status ?? "").lowercased() == "confirmed" &&
                       (booking.paymentStatus ?? "").lowercased() != "paid" {
                        paymentActionsSection
                    }

                    // Notes Section
                    notesSection

                    // Rejection Reason (if applicable)
                    if let reason = booking.rejectionReason, !reason.isEmpty {
                        rejectionSection(reason)
                    }

                    // Client Decline Reason (if applicable)
                    if let reason = booking.clientDeclineReason, !reason.isEmpty {
                        clientDeclineSection(reason)
                    }

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Booking Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showCoachPaymentsSheet) {
                CoachPaymentMethodsSheet(
                    coachName: selectedCoachName,
                    payments: selectedCoachPayments
                )
            }
            .sheet(isPresented: $showCoachPickerForNotify) {
                CoachPickerForNotifySheet(
                    booking: booking,
                    onCoachSelected: { coachId in
                        showCoachPickerForNotify = false
                        sendPaymentNotification(to: coachId)
                    }
                )
                .environmentObject(firestore)
            }
            .alert("Payment Notification", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - View Components

    private var statusSection: some View {
        HStack {
            Text("Status")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(displayStatus(for: booking.status))
                .font(.headline)
                .foregroundColor(statusColor(for: booking.status))
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(UIColor.secondarySystemBackground)))
    }

    private var groupBadge: some View {
        HStack {
            Image(systemName: "person.3.fill")
                .foregroundColor(.blue)
            Text("Group Session")
                .font(.subheadline)
                .foregroundColor(.blue)
            Spacer()
            Text(booking.participantSummary)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.blue.opacity(0.1)))
    }

    private var participantsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Participants")
                .font(.headline)

            // Coach(es)
            VStack(alignment: .leading, spacing: 8) {
                Text(isGroupBooking && booking.allCoachIDs.count > 1 ? "Coaches" : "Coach")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if isGroupBooking && booking.allCoachIDs.count > 1 {
                    let bookingRejected = (booking.status ?? "").lowercased() == "rejected"
                    ForEach(Array(zip(booking.allCoachIDs, booking.allCoachNames)), id: \.0) { coachId, coachName in
                        HStack {
                            Text(coachName)
                                .font(.body)
                            Spacer()
                            let accepted = booking.coachAcceptances?[coachId] ?? false
                            let isRejector = booking.rejectedBy == coachId
                            if isRejector || (bookingRejected && !accepted) {
                                Label("Rejected", systemImage: "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            } else if accepted {
                                Label("Accepted", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(Color("LogoGreen"))
                            } else {
                                Label("Pending", systemImage: "clock")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                            if let rates = booking.coachRates, let rate = rates[coachId] {
                                Text(String(format: "$%.2f", rate))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } else {
                    Text(coachDisplayName)
                        .font(.body)
                }
            }

            Divider()

            // Client(s)
            VStack(alignment: .leading, spacing: 8) {
                Text(isGroupBooking && booking.allClientIDs.count > 1 ? "Clients" : "Client")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if isGroupBooking && booking.allClientIDs.count > 1 {
                    ForEach(Array(zip(booking.allClientIDs, booking.allClientNames)), id: \.0) { clientId, clientName in
                        HStack {
                            Text(clientName)
                                .font(.body)
                            Spacer()
                            if let confirmations = booking.clientConfirmations {
                                let confirmed = confirmations[clientId] ?? false
                                Label(confirmed ? "Confirmed" : "Pending", systemImage: confirmed ? "checkmark.circle.fill" : "clock")
                                    .font(.caption)
                                    .foregroundColor(confirmed ? Color("LogoGreen") : .orange)
                            }
                        }
                    }
                } else {
                    Text(clientDisplayName)
                        .font(.body)
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(UIColor.secondarySystemBackground)))
    }

    private var dateTimeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Date & Time")
                .font(.headline)

            if let start = booking.startAt {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(.secondary)
                    Text(DateFormatter.localizedString(from: start, dateStyle: .full, timeStyle: .none))
                }
            }

            if let start = booking.startAt, let end = booking.endAt {
                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(.secondary)
                    Text("\(DateFormatter.localizedString(from: start, dateStyle: .none, timeStyle: .short)) - \(DateFormatter.localizedString(from: end, dateStyle: .none, timeStyle: .short))")
                }

                HStack {
                    Image(systemName: "hourglass")
                        .foregroundColor(.secondary)
                    Text("\(durationMinutes) minutes")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(UIColor.secondarySystemBackground)))
    }

    private func locationSection(_ location: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Location")
                .font(.headline)

            HStack {
                Image(systemName: "mappin.circle")
                    .foregroundColor(.secondary)
                Text(location)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(UIColor.secondarySystemBackground)))
    }

    private var rateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pricing")
                .font(.headline)

            if isGroupBooking {
                if let rates = booking.coachRates, !rates.isEmpty {
                    ForEach(Array(zip(booking.allCoachIDs, booking.allCoachNames)), id: \.0) { coachId, coachName in
                        if let rate = rates[coachId] {
                            HStack {
                                Text(coachName)
                                    .font(.body)
                                Spacer()
                                Text(String(format: "$%.2f", rate))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } else {
                    Text("Rates pending")
                        .foregroundColor(.orange)
                }
            } else {
                HStack {
                    Text("Rate")
                    Spacer()
                    if let rate = booking.RateUSD {
                        Text(String(format: "$%.2f", rate))
                    } else {
                        Text("—")
                            .foregroundColor(.secondary)
                    }
                }
            }

            Divider()

            HStack {
                Text("Total Cost")
                    .font(.headline)
                Spacer()
                if let total = totalBookingCost {
                    Text(String(format: "$%.2f", total))
                        .font(.headline)
                        .foregroundColor(Color("LogoGreen"))
                } else {
                    Text("—")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(UIColor.secondarySystemBackground)))
    }

    private var hasNotes: Bool {
        let hasClientNotes = !(booking.notes ?? "").isEmpty
        let hasCoachNote = !(booking.coachNote ?? "").isEmpty
        return hasClientNotes || hasCoachNote
    }

    @ViewBuilder
    private var notesSection: some View {
        if hasNotes {
            VStack(alignment: .leading, spacing: 12) {
                Text("Notes")
                    .font(.headline)

                if let notes = booking.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.body)
                        .foregroundColor(.secondary)
                }

                if let coachNote = booking.coachNote, !coachNote.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Coach Note")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(coachNote)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(UIColor.secondarySystemBackground)))
        }
    }

    private func rejectionSection(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                Text("Rejection Reason")
                    .font(.headline)
            }
            Text(reason)
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.red.opacity(0.1)))
    }

    private func clientDeclineSection(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                Text("Client Decline Reason")
                    .font(.headline)
            }
            Text(reason)
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.red.opacity(0.1)))
    }

    // MARK: - Payment Actions Section

    private var paymentActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Payment")
                .font(.headline)

            HStack {
                Button(action: { startNotifyCoachOfPayment() }) {
                    Text("Notify Coach of Payment")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(action: { makePayment() }) {
                    Text("Make Payment")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(UIColor.secondarySystemBackground)))
    }

    // MARK: - Payment Helper Functions

    private func startNotifyCoachOfPayment() {
        let coachIds = booking.allCoachIDs
        if coachIds.count > 1 {
            showCoachPickerForNotify = true
        } else if let coachId = coachIds.first, !coachId.isEmpty {
            sendPaymentNotification(to: coachId)
        } else {
            errorMessage = "Missing coach ID for this booking."
        }
    }

    private func sendPaymentNotification(to coachId: String) {
        var clientName = "A client"
        if let client = firestore.currentClient, !client.name.isEmpty {
            clientName = client.name
        }

        let db = Firestore.firestore()
        let notifRef = db.collection("pendingNotifications").document(coachId).collection("notifications").document()
        let notifPayload: [String: Any] = [
            "title": "Payment Notification",
            "body": "\(clientName) has marked booking as paid. Please confirm",
            "bookingId": booking.id,
            "senderId": auth.user?.uid ?? "",
            "createdAt": FieldValue.serverTimestamp(),
            "delivered": false
        ]
        notifRef.setData(notifPayload) { err in
            DispatchQueue.main.async {
                if let err = err {
                    errorMessage = "Failed to notify coach: \(err.localizedDescription)"
                } else {
                    let coachName = nameForCoachId(coachId) ?? "Coach"
                    errorMessage = "\(coachName) has been notified of your payment."
                }
            }
        }
    }

    private func makePayment() {
        let coachId = booking.coachID
        guard !coachId.isEmpty else {
            self.errorMessage = "Missing coach ID for this booking."
            return
        }
        // Fetch payments and coach name, then present sheet
        FirestoreManager.shared.fetchCoachPayments(coachIdOrPath: coachId) { map in
            DispatchQueue.main.async {
                self.selectedCoachPayments = map
                self.selectedCoachName = booking.coachName ?? "Coach"
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

    private func nameForCoachId(_ coachId: String?) -> String? {
        guard let id = coachId, !id.isEmpty else { return nil }
        if let coach = firestore.coaches.first(where: { $0.id == id }) {
            return coach.name
        }
        return nil
    }
}

// MARK: - Coach Payment Methods Sheet

struct CoachPaymentMethodsSheet: View {
    let coachName: String
    let payments: [String: String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Pay \(coachName)")
                    .font(.title2)
                    .bold()
                    .padding(.top)

                if payments.isEmpty {
                    Text("No payment methods available for this coach.")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    ForEach(payments.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        HStack {
                            Text(key.capitalized)
                                .font(.headline)
                            Spacer()
                            Text(value)
                                .foregroundColor(.secondary)
                            if let url = paymentDeepLink(for: key, value: value) {
                                Link(destination: url) {
                                    Image(systemName: "arrow.up.right.square")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(UIColor.secondarySystemBackground)))
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Payment Methods")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func paymentDeepLink(for key: String, value: String) -> URL? {
        let k = key.lowercased()
        var v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.isEmpty { return nil }
        switch k {
        case "venmo":
            if v.hasPrefix("@") { v.removeFirst() }
            return URL(string: "https://venmo.com/u/\(v)")
        case "paypal":
            if v.range(of: "^[A-Za-z0-9.-_]+$", options: .regularExpression) != nil {
                return URL(string: "https://paypal.me/\(v)")
            }
            return nil
        case "cashapp":
            return URL(string: "https://cash.app/\(v)")
        case "zelle":
            return nil
        default:
            return nil
        }
    }
}

// MARK: - Coach Picker for Notify Sheet

struct CoachPickerForNotifySheet: View {
    let booking: FirestoreManager.BookingItem
    let onCoachSelected: (String) -> Void
    @EnvironmentObject var firestore: FirestoreManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(zip(booking.allCoachIDs, booking.allCoachNames)), id: \.0) { coachId, coachName in
                    Button(action: {
                        onCoachSelected(coachId)
                    }) {
                        Text(coachName)
                    }
                }
            }
            .navigationTitle("Select Coach to Notify")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct BookingDetailView_Previews: PreviewProvider {
    static var previews: some View {
        BookingDetailView(booking: FirestoreManager.BookingItem(
            id: "sample",
            clientID: "c1",
            clientName: "John Doe",
            coachID: "coach1",
            coachName: "Coach Smith",
            startAt: Date(),
            endAt: Date().addingTimeInterval(3600),
            location: "Tennis Court 1",
            notes: "Bring your own racket",
            status: "confirmed",
            paymentStatus: "paid",
            RateUSD: 50.0
        ))
        .environmentObject(FirestoreManager())
        .environmentObject(AuthViewModel())
    }
}
