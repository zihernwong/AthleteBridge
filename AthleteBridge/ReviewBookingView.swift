import SwiftUI

struct ReviewBookingView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    let booking: FirestoreManager.BookingItem

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

                // Offer details are stored on the booking document (RateUSD / RateCents / CoachNote).
                // The BookingItem struct does not carry these fields, so we keep this view minimal for now.
                Text("Coach Price: (see booking details)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if let note = booking.notes, !note.isEmpty {
                    Text("Note from coach:")
                        .font(.subheadline).bold()
                    Text(booking.notes ?? "")
                        .font(.body)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Action buttons: Decline (left) and Confirm (right)
                HStack {
                    Button(role: .destructive) {
                        confirmOrDecline(status: "declined_by_client")
                    } label: {
                        Text("Decline")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        confirmOrDecline(status: "confirmed")
                    } label: {
                        Text("Confirm Booking")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top)

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
        }
    }

    private func confirmOrDecline(status: String) {
        // Call the centralized updater in FirestoreManager which updates root + mirrored docs.
        firestore.updateBookingStatus(bookingId: booking.id, status: status) { err in
            DispatchQueue.main.async {
                if let err = err {
                    firestore.showToast("Failed to update booking: \(err.localizedDescription)")
                } else {
                    let friendly = (status == "confirmed") ? "Booking confirmed" : "Booking declined"
                    firestore.showToast(friendly)
                    // Optionally refresh lists
                    firestore.fetchBookingsForCurrentClientSubcollection()
                    // refresh the coach-specific subcollection listing for the affected coach
                    firestore.fetchBookingsForCoachSubcollection(coachId: booking.coachID)
                    dismiss()
                }
            }
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
