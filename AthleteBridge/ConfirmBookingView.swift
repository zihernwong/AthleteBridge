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
                                ForEach(Array(zip(booking.allCoachIDs, booking.allCoachNames)), id: \.0) { coachId, coachName in
                                    let accepted = coachAcceptances[coachId] ?? false
                                    HStack {
                                        Text(coachName)
                                        Spacer()
                                        if accepted {
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

                        Section(header: Text("Coach Price")) {
                            if let r = rateUSD {
                                Text(String(format: "$%.2f", r))
                            } else {
                                Text("Price not provided")
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
