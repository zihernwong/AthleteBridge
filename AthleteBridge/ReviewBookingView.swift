import SwiftUI
import FirebaseFirestore

struct ReviewBookingView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    let booking: FirestoreManager.BookingItem

    // Fetch coach-provided offer details at runtime (BookingItem doesn't include rate/coachNote)
    @State private var rateUSD: Double? = nil
    @State private var coachNoteText: String? = nil
    @State private var loadingDetails: Bool = true
    @State private var fetchError: String? = nil

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Review Booking")
                    .font(.title2)
                    .bold()

                if let start = booking.startAt {
                    Text("Start: \(DateFormatter.localizedString(from: start, dateStyle: .medium, timeStyle: .short))")
                }
                if let end = booking.endAt {
                    Text("End: \(DateFormatter.localizedString(from: end, dateStyle: .medium, timeStyle: .short))")
                }

                if loadingDetails {
                    HStack { ProgressView(); Text("Loading offer...").font(.subheadline).foregroundColor(.secondary) }
                } else {
                    if let rate = rateUSD {
                        Text(String(format: "Coach Price: $%.2f", rate))
                            .font(.headline)
                    } else {
                        Text("Coach Price: Not provided")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    if let note = coachNoteText, !note.isEmpty {
                        Text("Note from coach:")
                            .font(.subheadline).bold()
                        Text(note)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }

                    if let err = fetchError {
                        Text("Error loading offer: \(err)")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                Spacer()

                Text("This is a placeholder page where the client can confirm or decline the pending booking. UI to be implemented.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()
            }
            .padding()
            .navigationTitle("Review")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                await fetchOfferDetails()
            }
        }
    }

    // Fetch RateUSD / RateCents and CoachNote / Notes from root booking doc
    private func fetchOfferDetails() async {
        loadingDetails = true
        fetchError = nil
        let docRef = Firestore.firestore().collection("bookings").document(booking.id)
        docRef.getDocument { snap, err in
            if let err = err {
                fetchError = err.localizedDescription
                loadingDetails = false
                return
            }
            guard let data = snap?.data() else {
                fetchError = "Booking not found"
                loadingDetails = false
                return
            }

            if let r = data["RateUSD"] as? Double {
                rateUSD = r
            } else if let cents = data["RateCents"] as? Int {
                rateUSD = Double(cents) / 100.0
            } else if let rStr = data["RateUSD"] as? String, let r = Double(rStr) {
                rateUSD = r
            }

            // Try several keys that might hold the coach note
            coachNoteText = (data["CoachNote"] as? String) ?? (data["coachNote"] as? String) ?? (data["Notes"] as? String)
            loadingDetails = false
        }
    }
}

struct ReviewBookingView_Previews: PreviewProvider {
    static var previews: some View {
        ReviewBookingView(booking: FirestoreManager.BookingItem(id: "sample", clientID: "c1", clientName: "Client One", coachID: "u2", coachName: "Coach Two", startAt: Date(), endAt: Date().addingTimeInterval(3600), location: "Gym", notes: "Bring gear", status: "pending acceptance"))
            .environmentObject(FirestoreManager())
            .environmentObject(AuthViewModel())
    }
}
