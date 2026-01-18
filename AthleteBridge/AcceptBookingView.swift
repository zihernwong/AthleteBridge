import SwiftUI
import Firebase
import FirebaseFirestore

struct AcceptBookingView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel
    @Environment(\.dismiss) var dismiss

    let booking: FirestoreManager.BookingItem

    @State private var rateText: String = ""
    @State private var note: String = ""
    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Booking")) {
                    Text(booking.clientName ?? "Client")
                    if let start = booking.startAt {
                        Text("Starts: \(DateFormatter.localizedString(from: start, dateStyle: .medium, timeStyle: .short))")
                    }
                    if let end = booking.endAt {
                        Text("Ends: \(DateFormatter.localizedString(from: end, dateStyle: .medium, timeStyle: .short))")
                    }
                }

                Section(header: Text("Rate (USD)")) {
                    HStack {
                        Text("$")
                        TextField("e.g. 45.00", text: $rateText)
                            .keyboardType(.decimalPad)
                            .disableAutocorrection(true)
                    }
                }

                Section(header: Text("Optional note to client")) {
                    TextEditor(text: $note)
                        .frame(minHeight: 100)
                }

                if let err = errorMessage {
                    Section {
                        Text(err).foregroundColor(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Accept Booking")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: save) {
                        if isSaving { ProgressView() } else { Text("Save") }
                    }
                    .disabled(isSaving || !(isValidRate() || note.count > 0))
                }
            }
        }
    }

    private func isValidRate() -> Bool {
        guard !rateText.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return Double(rateText.replacingOccurrences(of: ",", with: ".")) != nil
    }

    private func save() {
        // Use AuthViewModel's user property for auth state rather than calling Firebase directly
        guard auth.user != nil else {
            errorMessage = "Not authenticated"
            return
        }

        isSaving = true
        errorMessage = nil

        let rateVal = Double(rateText.replacingOccurrences(of: ",", with: "."))

        // Build update payload and write directly to Firestore in a batched update.
        let bookingRef = Firestore.firestore().collection("bookings").document(booking.id)
        let coachId = booking.coachID
        let clientId = booking.clientID

        var updatePayload: [String: Any] = ["Status": "Pending Acceptance"]
        if let r = rateVal { updatePayload["RateUSD"] = r }
        if !note.isEmpty { updatePayload["CoachNote"] = note }
        updatePayload["pendingAt"] = FieldValue.serverTimestamp()

        let batch = Firestore.firestore().batch()
        batch.updateData(updatePayload, forDocument: bookingRef)

        if !coachId.isEmpty {
            let coachBookingRef = Firestore.firestore().collection("coaches").document(coachId).collection("bookings").document(booking.id)
            batch.updateData(updatePayload, forDocument: coachBookingRef)
            // append small summary to coach.calendar
            var bookingSummary: [String: Any] = ["id": booking.id, "updatedAt": Timestamp(date: Date()), "Status": "Pending Acceptance"]
            if let r = rateVal { bookingSummary["RateUSD"] = r }
            if !note.isEmpty { bookingSummary["CoachNote"] = note }
            let coachDocRef = Firestore.firestore().collection("coaches").document(coachId)
            batch.updateData(["calendar": FieldValue.arrayUnion([bookingSummary])], forDocument: coachDocRef)
        }

        if !clientId.isEmpty {
            let clientBookingRef = Firestore.firestore().collection("clients").document(clientId).collection("bookings").document(booking.id)
            batch.updateData(updatePayload, forDocument: clientBookingRef)
        }

        batch.commit { err in
            DispatchQueue.main.async {
                self.isSaving = false
                if let err = err {
                    self.errorMessage = err.localizedDescription
                } else {
                    // refresh using environment object's convenience method
                    self.firestore.fetchBookingsForCurrentCoachSubcollection()
                    self.firestore.showToast("Booking pending acceptance")
                    dismiss()
                }
            }
        }
    }
}

struct AcceptBookingView_Previews: PreviewProvider {
    static var previews: some View {
        AcceptBookingView(booking: FirestoreManager.BookingItem(id: "1", clientID: "c1", clientName: "Alice", coachID: "s1", coachName: "Coach Sam", startAt: Date(), endAt: Date().addingTimeInterval(1800), location: "Court 1", notes: "Bring racket", status: "requested", paymentStatus: "unpaid", RateUSD: 45.0))
            .environmentObject(FirestoreManager())
            .environmentObject(AuthViewModel())
    }
}
