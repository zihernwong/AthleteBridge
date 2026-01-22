import SwiftUI

struct AcceptedBookingsView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel

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
                        }
                        .padding(.vertical, 4)
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
