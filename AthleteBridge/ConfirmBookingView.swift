import SwiftUI
import Firebase
import FirebaseFirestore

struct ConfirmBookingView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel
    @Environment(\.dismiss) var dismiss

    let booking: FirestoreManager.BookingItem

    @State private var rateUSD: Double? = nil
    @State private var coachNote: String? = nil
    @State private var loading: Bool = true
    @State private var isProcessing: Bool = false
    @State private var errorMessage: String? = nil
    @State private var coachAcceptances: [String: Bool] = [:]
    @State private var clientConfirmations: [String: Bool] = [:]
    @State private var coachRates: [String: Double] = [:]

    // Check if this is a group booking
    private var isGroupBooking: Bool {
        booking.isGroupBooking ?? false ||
        (booking.coachIDs?.count ?? 0) > 1 ||
        (booking.clientIDs?.count ?? 0) > 1
    }

    // Check if this is a multi-client booking
    private var isMultiClientBooking: Bool {
        (booking.clientIDs?.count ?? 0) > 1
    }

    // Check if all coaches have accepted (for group bookings)
    private var allCoachesAccepted: Bool {
        guard isGroupBooking else { return true }
        let coachIds = booking.allCoachIDs
        guard !coachIds.isEmpty else { return true }
        return coachIds.allSatisfy { coachAcceptances[$0] == true }
    }

    // Check if current client has already confirmed
    private var currentClientAlreadyConfirmed: Bool {
        guard isMultiClientBooking else { return false }
        guard let currentClientId = auth.user?.uid else { return false }
        return clientConfirmations[currentClientId] == true
    }

    // Check if all clients have confirmed
    private var allClientsConfirmed: Bool {
        guard isMultiClientBooking else { return true }
        let clientIds = booking.allClientIDs
        guard !clientIds.isEmpty else { return true }
        return clientIds.allSatisfy { clientConfirmations[$0] == true }
    }

    // Check if this is a multi-coach booking
    private var isMultiCoachBooking: Bool {
        booking.allCoachIDs.count > 1
    }

    // Get coach rates paired with names for display
    private var coachRatesForDisplay: [(id: String, name: String, rate: Double?)] {
        let coachIds = booking.allCoachIDs
        let coachNames = booking.allCoachNames

        return coachIds.enumerated().map { (index, coachId) in
            let name = index < coachNames.count ? coachNames[index] : "Coach"
            let rate = coachRates[coachId]
            return (id: coachId, name: name, rate: rate)
        }
    }

    // Calculate duration in 0.5 hour increments
    private var durationHours: Double {
        guard let start = booking.startAt, let end = booking.endAt else { return 0 }
        let totalMinutes = end.timeIntervalSince(start) / 60
        let halfHours = (totalMinutes / 30).rounded()
        return halfHours * 0.5
    }

    // Calculate total cost for all coaches combined
    private var totalCombinedCost: Double? {
        guard durationHours > 0 else { return nil }
        guard !coachRates.isEmpty else { return nil }
        let totalRate = coachRates.values.reduce(0, +)
        return totalRate * durationHours
    }

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView("Loading...")
                } else {
                    Form {
                        Section(header: Text(isGroupBooking ? "Group Appointment" : "Appointment")) {
                            if isGroupBooking {
                                HStack {
                                    Image(systemName: "person.3.fill")
                                        .foregroundColor(.blue)
                                    Text("Group Session")
                                        .font(.subheadline)
                                        .foregroundColor(.blue)
                                }
                                Text(booking.participantSummary)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            // Show clients - use list format for multiple clients
                            if isGroupBooking && booking.allClientNames.count > 1 {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Clients:").font(.subheadline).foregroundColor(.secondary)
                                    ForEach(booking.allClientNames, id: \.self) { name in
                                        Text("• \(name)")
                                    }
                                }
                            } else {
                                Text(booking.clientName ?? "Client")
                            }

                            if let start = booking.startAt {
                                Text("Starts: \(DateFormatter.localizedString(from: start, dateStyle: .medium, timeStyle: .short))")
                            }
                            if let end = booking.endAt {
                                Text("Ends: \(DateFormatter.localizedString(from: end, dateStyle: .medium, timeStyle: .short))")
                            }
                        }

                        // Show coach acceptances for group bookings
                        if isGroupBooking {
                            Section(header: Text("Coach Acceptances")) {
                                let bookingRejected = (booking.status ?? "").lowercased() == "rejected"
                                ForEach(Array(zip(booking.allCoachIDs, booking.allCoachNames)), id: \.0) { coachId, coachName in
                                    let accepted = coachAcceptances[coachId] ?? false
                                    let isRejector = booking.rejectedBy == coachId
                                    HStack {
                                        Text(coachName)
                                        Spacer()
                                        if isRejector || (bookingRejected && !accepted) {
                                            Label("Rejected", systemImage: "xmark.circle.fill")
                                                .foregroundColor(.red)
                                                .font(.caption)
                                        } else if accepted {
                                            Label("Accepted", systemImage: "checkmark.circle.fill")
                                                .foregroundColor(Color("LogoGreen"))
                                                .font(.caption)
                                        } else {
                                            Label("Pending", systemImage: "clock")
                                                .foregroundColor(.orange)
                                                .font(.caption)
                                        }
                                    }
                                }

                                if !allCoachesAccepted {
                                    Text("Waiting for all coaches to accept before you can confirm")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                        }

                        // Show client confirmations for multi-client bookings
                        if isMultiClientBooking {
                            Section(header: Text("Client Confirmations")) {
                                ForEach(Array(zip(booking.allClientIDs, booking.allClientNames)), id: \.0) { clientId, clientName in
                                    let confirmed = clientConfirmations[clientId] ?? false
                                    let isCurrentUser = clientId == auth.user?.uid
                                    HStack {
                                        Text(clientName)
                                        if isCurrentUser {
                                            Text("(You)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        if confirmed {
                                            Label("Confirmed", systemImage: "checkmark.circle.fill")
                                                .foregroundColor(Color("LogoGreen"))
                                                .font(.caption)
                                        } else {
                                            Label("Pending", systemImage: "clock")
                                                .foregroundColor(.orange)
                                                .font(.caption)
                                        }
                                    }
                                }

                                if !allClientsConfirmed && allCoachesAccepted {
                                    if currentClientAlreadyConfirmed {
                                        Text("Waiting for other clients to confirm")
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                    } else {
                                        Text("Please confirm to proceed with the booking")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                    }
                                }
                            }
                        }

                        if isMultiCoachBooking {
                            // Multi-coach booking: show each coach with their rate
                            Section(header: Text("Coach Rates")) {
                                ForEach(coachRatesForDisplay, id: \.id) { coach in
                                    HStack {
                                        Text(coach.name)
                                        Spacer()
                                        if let rate = coach.rate {
                                            Text(String(format: "$%.2f/hr", rate))
                                                .foregroundColor(.secondary)
                                        } else {
                                            Text("Rate pending")
                                                .foregroundColor(.orange)
                                        }
                                    }
                                }

                                if let total = totalCombinedCost {
                                    HStack {
                                        Text("Total Cost")
                                            .bold()
                                        if durationHours > 0 {
                                            Text("(\(String(format: "%.1f", durationHours)) hrs)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Text(String(format: "$%.2f", total))
                                            .bold()
                                    }
                                }
                            }
                        } else {
                            // Single coach booking: original layout
                            Section(header: Text("Coach Price")) {
                                if let r = rateUSD {
                                    Text(String(format: "$%.2f/hr", r))
                                } else {
                                    Text("Price not provided")
                                }
                            }
                        }

                        Section(header: Text("Coach Note")) {
                            Text(coachNote ?? "No note provided").foregroundColor(.secondary)
                        }

                        if let err = errorMessage {
                            Section { Text(err).foregroundColor(.red) }
                        }

                        Section {
                            if currentClientAlreadyConfirmed {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(Color("LogoGreen"))
                                    Text("You have confirmed this booking")
                                        .foregroundColor(Color("LogoGreen"))
                                }
                                if !allClientsConfirmed {
                                    Text("Waiting for other clients to confirm...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Button(action: confirm) {
                                    if isProcessing { ProgressView() } else { Text("Confirm Booking") }
                                }
                                .disabled(isProcessing || rateUSD == nil || (isGroupBooking && !allCoachesAccepted))
                            }

                            Button(role: .destructive, action: decline) {
                                Text("Decline")
                            }
                            .disabled(isProcessing || currentClientAlreadyConfirmed)
                        }
                    }
                }
            }
            .navigationTitle("Review Offer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                await loadBookingDetails()
            }
        }
    }

    private func loadBookingDetails() async {
        loading = true
        defer { loading = false }
        let docRef = Firestore.firestore().collection("bookings").document(booking.id)
        do {
            let snap = try await docRef.getDocument()
            let data = snap.data() ?? [:]
            if let r = data["RateUSD"] as? Double { self.rateUSD = r }
            else if let r = data["RateCents"] as? Int { self.rateUSD = Double(r) / 100.0 }
            self.coachNote = data["CoachNote"] as? String ?? data["CoachNote"] as? String

            // Load coach acceptances for group bookings
            if let acceptances = data["CoachAcceptances"] as? [String: Bool] {
                self.coachAcceptances = acceptances
            }

            // Load client confirmations for multi-client bookings
            if let confirmations = data["ClientConfirmations"] as? [String: Bool] {
                self.clientConfirmations = confirmations
            }

            // Load coach rates for multi-coach bookings
            if let rates = data["CoachRates"] as? [String: Double] {
                self.coachRates = rates
            }
        } catch {
            self.errorMessage = "Failed to load offer: \(error.localizedDescription)"
        }
    }

    private func confirm() {
        guard let clientId = auth.user?.uid else { errorMessage = "Not authenticated"; return }
        isProcessing = true
        errorMessage = nil

        // Use group booking confirm for group bookings
        if isGroupBooking {
            firestore.confirmGroupBookingAsClient(bookingId: booking.id, clientId: clientId) { err in
                DispatchQueue.main.async {
                    self.isProcessing = false
                    if let err = err {
                        self.errorMessage = err.localizedDescription
                    } else {
                        // Fetch will auto-add to calendar if enabled
                        self.firestore.fetchBookingsForCurrentClientSubcollection()
                        self.firestore.showToast("Group booking confirmed")
                        dismiss()
                    }
                }
            }
            return
        }

        // Original single-coach confirm flow
        let bookingRef = Firestore.firestore().collection("bookings").document(booking.id)
        let coachId = booking.coachID

        var updatePayload: [String: Any] = ["Status": "confirmed"]
        updatePayload["confirmedAt"] = FieldValue.serverTimestamp()
        updatePayload["confirmedByClient"] = clientId

        let batch = Firestore.firestore().batch()
        batch.updateData(updatePayload, forDocument: bookingRef)
        if !coachId.isEmpty {
            let coachBookingRef = Firestore.firestore().collection("coaches").document(coachId).collection("bookings").document(booking.id)
            batch.updateData(updatePayload, forDocument: coachBookingRef)
        }
        if !clientId.isEmpty {
            let clientBookingRef = Firestore.firestore().collection("clients").document(clientId).collection("bookings").document(booking.id)
            batch.updateData(updatePayload, forDocument: clientBookingRef)
        }

        batch.commit { err in
            DispatchQueue.main.async {
                self.isProcessing = false
                if let err = err {
                    self.errorMessage = err.localizedDescription
                } else {
                    // Fetch will auto-add to calendar if enabled
                    self.firestore.fetchBookingsForCurrentClientSubcollection()
                    self.firestore.showToast("Booking confirmed")
                    dismiss()
                }
            }
        }
    }

    private func decline() {
        guard let clientId = auth.user?.uid else { errorMessage = "Not authenticated"; return }
        isProcessing = true
        errorMessage = nil

        // Use group booking status update for group bookings
        if isGroupBooking {
            firestore.updateGroupBookingStatus(bookingId: booking.id, status: "declined_by_client") { err in
                DispatchQueue.main.async {
                    self.isProcessing = false
                    if let err = err {
                        self.errorMessage = err.localizedDescription
                    } else {
                        self.firestore.fetchBookingsForCurrentClientSubcollection()
                        self.firestore.showToast("Group booking declined")
                        dismiss()
                    }
                }
            }
            return
        }

        // Original single-coach decline flow
        let bookingRef = Firestore.firestore().collection("bookings").document(booking.id)
        let coachId = booking.coachID

        let updatePayload: [String: Any] = ["Status": "declined_by_client", "declinedAt": FieldValue.serverTimestamp(), "declinedByClient": clientId]
        let batch = Firestore.firestore().batch()
        batch.updateData(updatePayload, forDocument: bookingRef)
        if !coachId.isEmpty {
            let coachBookingRef = Firestore.firestore().collection("coaches").document(coachId).collection("bookings").document(booking.id)
            batch.updateData(updatePayload, forDocument: coachBookingRef)
        }
        if !clientId.isEmpty {
            let clientBookingRef = Firestore.firestore().collection("clients").document(clientId).collection("bookings").document(booking.id)
            batch.updateData(updatePayload, forDocument: clientBookingRef)
        }

        batch.commit { err in
            DispatchQueue.main.async {
                self.isProcessing = false
                if let err = err {
                    self.errorMessage = err.localizedDescription
                } else {
                    self.firestore.fetchBookingsForCurrentClientSubcollection()
                    self.firestore.fetchBookingsForCurrentCoachSubcollection()
                    self.firestore.showToast("Booking declined")
                    dismiss()
                }
            }
        }
    }
}

struct ConfirmBookingView_Previews: PreviewProvider {
    static var previews: some View {
        ConfirmBookingView(booking: FirestoreManager.BookingItem(id: "1", clientID: "c1", clientName: "Alice", coachID: "s1", coachName: "Coach Sam", startAt: Date(), endAt: Date().addingTimeInterval(1800), location: "Court 1", notes: "Bring racket", status: "Pending Acceptance", paymentStatus: "unpaid", RateUSD: 55.0))
            .environmentObject(FirestoreManager())
            .environmentObject(AuthViewModel())
    }
}
