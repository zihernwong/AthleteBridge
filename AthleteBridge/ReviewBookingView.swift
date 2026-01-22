import SwiftUI
import FirebaseFirestore

struct ReviewBookingView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    let booking: FirestoreManager.BookingItem

    private var coachDisplayName: String {
        booking.coachName ?? "Coach"
    }

    private var rateDisplayText: String {
        if let rate = booking.RateUSD {
            return String(format: "$%.2f", rate)
        }

        return "—"
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Review Booking")
                    .font(.title2)
                    .bold()

                // Coach
                VStack(alignment: .leading, spacing: 4) {
                    Text("Coach")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(coachDisplayName)
                        .font(.headline)
                }

                // Price
                VStack(alignment: .leading, spacing: 4) {
                    Text("Coach Price")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(rateDisplayText)
                        .font(.headline)
                }

                if let start = booking.startAt {
                    Text("Start: \(DateFormatter.localizedString(from: start, dateStyle: .medium, timeStyle: .short))")
                }
                if let end = booking.endAt {
                    Text("End: \(DateFormatter.localizedString(from: end, dateStyle: .medium, timeStyle: .short))")
                }

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

                // Manual add-to-calendar button
                HStack {
                    Spacer()
                    Button(action: { addToCalendar() }) {
                        Label("Add to Calendar", systemImage: "calendar.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
                .padding(.top, 8)

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
        .alert(isPresented: $showCalendarAlert) {
            Alert(title: Text("Calendar"), message: Text(calendarAlertMessage), dismissButton: .default(Text("OK")))
        }
    }

    private func confirmOrDecline(status: String) {
        // Call the centralized updater in FirestoreManager which updates root + mirrored docs.
        firestore.updateBookingStatus(bookingId: booking.id, status: status) { err in
            DispatchQueue.main.async {
                if let err = err {
                    firestore.showToast("Failed to update booking: \(err.localizedDescription)")
                } else {
                    // Send notification to coach when client confirms
                    if status == "confirmed", !booking.coachID.isEmpty {
                        let clientName = firestore.currentClient?.name ?? "Client"
                        let notifRef = Firestore.firestore().collection("pendingNotifications").document(booking.coachID).collection("notifications").document()
                        let notifPayload: [String: Any] = [
                            "title": "Booking Confirmed",
                            "body": "\(clientName) has confirmed the booking.",
                            "bookingId": booking.id,
                            "senderId": booking.clientID,
                            "createdAt": FieldValue.serverTimestamp(),
                            "delivered": false
                        ]
                        notifRef.setData(notifPayload) { nerr in
                            if let nerr = nerr {
                                print("[ReviewBookingView] Failed to send notification to coach: \(nerr)")
                            }
                        }
                    }
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

    @State private var isAddingToCalendar: Bool = false
    @State private var showCalendarAlert: Bool = false
    @State private var calendarAlertMessage: String = ""
    @State private var calendarAlertTitle: String = ""
    @State private var calendarAlertDate: Date? = nil

    private func addToCalendar() {
        guard !isAddingToCalendar else { return }
        isAddingToCalendar = true
        // Extract booking details and call manager
        let title = "Session with \(booking.coachName ?? booking.clientName ?? "Booking")"
        let start = booking.startAt ?? Date()
        let end = booking.endAt ?? Calendar.current.date(byAdding: .minute, value: 30, to: start) ?? Date()
        firestore.addBookingToAppleCalendar(title: title, start: start, end: end, location: booking.location, notes: booking.notes, bookingId: booking.id) { res in
            DispatchQueue.main.async {
                self.isAddingToCalendar = false
                switch res {
                case .success(_):
                    // show user-friendly alert with title and start date
                    self.calendarAlertTitle = title
                    self.calendarAlertDate = start
                    self.calendarAlertMessage = "Added \(title) on \(DateFormatter.localizedString(from: start, dateStyle: .medium, timeStyle: .short))"
                    self.showCalendarAlert = true
                    firestore.showToast("Added to Calendar")
                case .failure(let err):
                    self.calendarAlertMessage = "Failed to add to Calendar: \(err.localizedDescription)"
                    self.showCalendarAlert = true
                    firestore.showToast("Calendar add failed: \(err.localizedDescription)")
                }
            }
        }
    }
}

struct ReviewBookingView_Previews: PreviewProvider {
    static var previews: some View {
        ReviewBookingView(booking: FirestoreManager.BookingItem(id: "sample", clientID: "c1", clientName: "Client One", coachID: "u2", coachName: "Coach Two", startAt: Date(), endAt: Date().addingTimeInterval(3600), location: "Gym", notes: "Bring gear", status: "pending acceptance", paymentStatus: "unpaid", RateUSD: 55.0))
            .environmentObject(FirestoreManager())
            .environmentObject(AuthViewModel())
    }
}
