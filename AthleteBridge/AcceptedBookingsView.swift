import SwiftUI
import FirebaseFirestore

struct AcceptedBookingsView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel

    @State private var bookingToCancel: FirestoreManager.BookingItem? = nil
    @State private var showCancelAlert: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                let confirmedBookings = firestore.coachBookings.filter { ($0.status ?? "").lowercased() == "confirmed" }
                if confirmedBookings.isEmpty {
                    Text("No confirmed bookings found")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                } else {
                    ForEach(confirmedBookings, id: \ .id) { b in
                        VStack(alignment: .leading, spacing: 8) {
                            BookingRowView(item: b)

                            if (b.paymentStatus ?? "").lowercased() != "paid" {
                                Button(action: {
                                    firestore.updateBookingPaymentStatus(bookingId: b.id, paymentStatus: "paid") { err in
                                        DispatchQueue.main.async {
                                            if let err = err {
                                                firestore.showToast("Failed: \(err.localizedDescription)")
                                            } else {
                                                firestore.fetchBookingsForCurrentCoachSubcollection()
                                                firestore.showToast("Payment acknowledged")
                                            }
                                        }
                                    }
                                }) {
                                    Text("Acknowledge Payment")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                            } else {
                                Text("Payment: Paid")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }

                            // Cancel booking button
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
            firestore.fetchBookingsForCurrentCoachSubcollection()
        }
        .alert("Cancel Booking", isPresented: $showCancelAlert) {
            Button("Keep Booking", role: .cancel) { }
            Button("Cancel Booking", role: .destructive) {
                if let booking = bookingToCancel {
                    cancelBooking(booking)
                }
            }
        } message: {
            Text("Are you sure you want to cancel this booking? The client will be notified.")
        }
    }

    private func cancelBooking(_ booking: FirestoreManager.BookingItem) {
        firestore.updateBookingStatus(bookingId: booking.id, status: "cancelled") { err in
            DispatchQueue.main.async {
                if let err = err {
                    firestore.showToast("Failed to cancel: \(err.localizedDescription)")
                } else {
                    // Send notification to client
                    if !booking.clientID.isEmpty {
                        let coachName = firestore.currentCoach?.name ?? "Coach"
                        let notifRef = Firestore.firestore().collection("pendingNotifications").document(booking.clientID).collection("notifications").document()
                        let notifPayload: [String: Any] = [
                            "title": "Booking Cancelled",
                            "body": "\(coachName) has cancelled the booking.",
                            "bookingId": booking.id,
                            "senderId": booking.coachID,
                            "createdAt": FieldValue.serverTimestamp(),
                            "delivered": false
                        ]
                        notifRef.setData(notifPayload) { _ in }
                    }
                    firestore.showToast("Booking cancelled")
                    firestore.fetchBookingsForCurrentCoachSubcollection()
                }
            }
        }
    }
}

struct AcceptedBookingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            AcceptedBookingsView()
                .environmentObject(FirestoreManager())
                .environmentObject(AuthViewModel())
        }
    }
}
