import SwiftUI
import FirebaseFirestore

struct ConfirmedBookingsView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel

    @State private var bookingToCancel: FirestoreManager.BookingItem? = nil
    @State private var showCancelAlert: Bool = false

    private func isConfirmed(_ status: String?) -> Bool {
        let s = (status ?? "").lowercased()
        return s == "confirmed" || s == "accepted" || s == "approved"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                let confirmed = firestore.bookings.filter { isConfirmed($0.status) }
                if confirmed.isEmpty {
                    Text("No confirmed bookings")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(confirmed, id: \ .id) { b in
                        VStack(alignment: .leading, spacing: 8) {
                            BookingRowView(item: b)
                            Button(role: .destructive) {
                                bookingToCancel = b
                                showCancelAlert = true
                            } label: {
                                Text("Cancel Booking")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.vertical, 4)
                        Divider()
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .navigationTitle("Confirmed Bookings")
        .onAppear {
            if let uid = auth.user?.uid {
                firestore.fetchBookingsFromClientSubcollection(clientId: uid)
            } else {
                firestore.fetchBookingsForCurrentClientSubcollection()
            }
        }
        .alert("Cancel Booking", isPresented: $showCancelAlert) {
            Button("Keep Booking", role: .cancel) { }
            Button("Cancel Booking", role: .destructive) {
                if let booking = bookingToCancel {
                    cancelBooking(booking)
                }
            }
        } message: {
            Text("Are you sure you want to cancel this booking? The coach will be notified.")
        }
    }

    private func cancelBooking(_ booking: FirestoreManager.BookingItem) {
        firestore.updateBookingStatus(bookingId: booking.id, status: "cancelled") { err in
            DispatchQueue.main.async {
                if let err = err {
                    firestore.showToast("Failed to cancel: \(err.localizedDescription)")
                } else {
                    // Send notification to coach
                    if !booking.coachID.isEmpty {
                        let clientName = firestore.currentClient?.name ?? "Client"
                        let notifRef = Firestore.firestore().collection("pendingNotifications").document(booking.coachID).collection("notifications").document()
                        let notifPayload: [String: Any] = [
                            "title": "Booking Cancelled",
                            "body": "\(clientName) has cancelled the booking.",
                            "bookingId": booking.id,
                            "senderId": booking.clientID,
                            "createdAt": FieldValue.serverTimestamp(),
                            "delivered": false
                        ]
                        notifRef.setData(notifPayload) { _ in }
                    }
                    firestore.showToast("Booking cancelled")
                    firestore.fetchBookingsForCurrentClientSubcollection()
                }
            }
        }
    }
}

struct ConfirmedBookingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ConfirmedBookingsView()
                .environmentObject(FirestoreManager())
                .environmentObject(AuthViewModel())
        }
    }
}
