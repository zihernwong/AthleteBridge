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

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView("Loading...")
                } else {
                    Form {
                        Section(header: Text("Appointment")) {
                            Text(booking.clientName ?? "Client")
                            if let start = booking.startAt {
                                Text("Starts: \(DateFormatter.localizedString(from: start, dateStyle: .medium, timeStyle: .short))")
                            }
                            if let end = booking.endAt {
                                Text("Ends: \(DateFormatter.localizedString(from: end, dateStyle: .medium, timeStyle: .short))")
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
                            Button(action: confirm) {
                                if isProcessing { ProgressView() } else { Text("Confirm Booking") }
                            }
                            .disabled(isProcessing || rateUSD == nil)

                            Button(role: .destructive, action: decline) {
                                Text("Decline")
                            }
                            .disabled(isProcessing)
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
        } catch {
            self.errorMessage = "Failed to load offer: \(error.localizedDescription)"
        }
    }

    private func confirm() {
        guard auth.user != nil else { errorMessage = "Not authenticated"; return }
        isProcessing = true
        errorMessage = nil

        let bookingRef = Firestore.firestore().collection("bookings").document(booking.id)
        let coachId = booking.coachID
        let clientId = booking.clientID

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
                    // refresh lists
                    self.firestore.fetchBookingsForCurrentClientSubcollection()
                    self.firestore.fetchBookingsForCurrentCoachSubcollection()
                    self.firestore.showToast("Booking confirmed")
                    dismiss()
                }
            }
        }
    }

    private func decline() {
        guard auth.user != nil else { errorMessage = "Not authenticated"; return }
        isProcessing = true
        errorMessage = nil

        // Simply set status back to 'requested' or 'declined' depending on desired flow. We'll set 'declined_by_client'.
        let bookingRef = Firestore.firestore().collection("bookings").document(booking.id)
        let coachId = booking.coachID
        let clientId = booking.clientID

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
        ConfirmBookingView(booking: FirestoreManager.BookingItem(id: "1", clientID: "c1", clientName: "Alice", coachID: "s1", coachName: "Coach Sam", startAt: Date(), endAt: Date().addingTimeInterval(1800), location: "Court 1", notes: "Bring racket", status: "Pending Acceptance"))
            .environmentObject(FirestoreManager())
            .environmentObject(AuthViewModel())
    }
}
