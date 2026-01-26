import SwiftUI
import FirebaseFirestore

struct CoachConfirmedBookingsView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel

    @State private var bookingToCancel: FirestoreManager.BookingItem? = nil
    @State private var showCancelAlert: Bool = false

    @State private var bookingToReschedule: FirestoreManager.BookingItem? = nil

    private func isConfirmed(_ status: String?) -> Bool {
        return (status ?? "").lowercased() == "confirmed"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Confirmed Bookings").font(.largeTitle).bold()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)

                let confirmed = firestore.coachBookings.filter { isConfirmed($0.status) }
                if confirmed.isEmpty {
                    Text("No confirmed bookings")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(confirmed, id: \ .id) { b in
                        VStack(alignment: .leading, spacing: 8) {
                            BookingRowView(item: b)
                            // Hide Cancel and Reschedule buttons once payment is acknowledged
                            if (b.paymentStatus ?? "").lowercased() != "paid" {
                                Button(role: .destructive) {
                                    bookingToCancel = b
                                    showCancelAlert = true
                                } label: {
                                    Text("Cancel Booking")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)

                                Button {
                                    bookingToReschedule = b
                                } label: {
                                    Text("Reschedule Booking")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .tint(.blue)
                            }
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
        .sheet(item: $bookingToReschedule) { booking in
            CoachRescheduleView(booking: booking) {
                bookingToReschedule = nil
                firestore.fetchBookingsForCurrentCoachSubcollection()
            }
            .environmentObject(firestore)
            .environmentObject(auth)
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

struct CoachConfirmedBookingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            CoachConfirmedBookingsView()
                .environmentObject(FirestoreManager())
                .environmentObject(AuthViewModel())
        }
    }
}
