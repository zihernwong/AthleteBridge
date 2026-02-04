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

    // Calculate duration in 0.5 hour increments
    private var durationHours: Double {
        guard let start = booking.startAt, let end = booking.endAt else { return 0 }
        let totalMinutes = end.timeIntervalSince(start) / 60
        // Round to nearest 0.5 hour increment
        let halfHours = (totalMinutes / 30).rounded()
        return halfHours * 0.5
    }

    // Calculate total booking cost based on hourly rate and duration
    private var totalBookingCost: Double? {
        guard let rate = booking.RateUSD, durationHours > 0 else { return nil }
        return rate * durationHours
    }

    private var totalCostDisplayText: String {
        if let total = totalBookingCost {
            return String(format: "$%.2f", total)
        }
        return "—"
    }

    // Check if this is a group booking with multiple coaches
    private var isMultiCoachBooking: Bool {
        booking.isGroupBooking == true && booking.allCoachIDs.count > 1
    }

    // Get coach rates paired with names for display
    private var coachRatesForDisplay: [(id: String, name: String, rate: Double?)] {
        let coachIds = booking.allCoachIDs
        let coachNames = booking.allCoachNames
        let rates = booking.coachRates ?? [:]

        return coachIds.enumerated().map { (index, coachId) in
            let name = index < coachNames.count ? coachNames[index] : "Coach"
            let rate = rates[coachId]
            return (id: coachId, name: name, rate: rate)
        }
    }

    // Calculate total cost for all coaches combined
    private var totalCombinedCost: Double? {
        guard durationHours > 0 else { return nil }
        let rates = booking.coachRates ?? [:]
        guard !rates.isEmpty else { return nil }
        let totalRate = rates.values.reduce(0, +)
        return totalRate * durationHours
    }

    private var totalCombinedCostDisplayText: String {
        if let total = totalCombinedCost {
            return String(format: "$%.2f", total)
        }
        return "—"
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Review Booking")
                    .font(.largeTitle)
                    .bold()

                if isMultiCoachBooking {
                    // Multi-coach group booking: show each coach with their rate
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Coaches & Rates")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        ForEach(coachRatesForDisplay, id: \.id) { coach in
                            HStack {
                                Text(coach.name)
                                    .font(.headline)
                                Spacer()
                                if let rate = coach.rate {
                                    Text(String(format: "$%.2f/hr", rate))
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("Rate pending")
                                        .font(.subheadline)
                                        .foregroundColor(.orange)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    // Total Combined Booking Cost
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Total Booking Cost")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if durationHours > 0 {
                                Text("(\(String(format: "%.1f", durationHours)) hrs)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Text(totalCombinedCostDisplayText)
                            .font(.headline)
                    }
                } else {
                    // Single coach booking: show original layout
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Coach")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(coachDisplayName)
                            .font(.headline)
                    }

                    // Hourly Rate
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hourly Rate")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(rateDisplayText)
                            .font(.headline)
                    }

                    // Total Booking Cost
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Total Booking Cost")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if durationHours > 0 {
                                Text("(\(String(format: "%.1f", durationHours)) hrs)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Text(totalCostDisplayText)
                            .font(.headline)
                    }
                }

                if let start = booking.startAt {
                    Text("Start: \(DateFormatter.localizedString(from: start, dateStyle: .medium, timeStyle: .short))")
                }
                if let end = booking.endAt {
                    Text("End: \(DateFormatter.localizedString(from: end, dateStyle: .medium, timeStyle: .short))")
                }

                if let note = booking.coachNote, !note.isEmpty {
                    Text("Note from coach:")
                        .font(.subheadline).bold()
                    Text(note)
                        .font(.body)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Action buttons: Decline (left) and Confirm (right)
                HStack {
                    Button {
                        confirmOrDecline(status: "declined_by_client")
                    } label: {
                        Text("Decline")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color("LogoBlue"))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }

                    Button {
                        confirmOrDecline(status: "confirmed")
                    } label: {
                        Text("Confirm Booking")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color("LogoGreen"))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
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
            .navigationBarTitleDisplayMode(.inline)
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
        if booking.isGroupBooking == true && status == "confirmed" {
            // Group booking: call group confirmation logic
            guard let clientId = auth.user?.uid else {
                firestore.showToast("No authenticated user")
                return
            }
            firestore.confirmGroupBookingAsClient(bookingId: booking.id, clientId: clientId) { err in
                DispatchQueue.main.async {
                    if let err = err {
                        firestore.showToast("Failed to update booking: \(err.localizedDescription)")
                    } else {
                        firestore.showToast("Group booking confirmation updated")
                        // Fetch will auto-add to calendar if enabled
                        firestore.fetchBookingsForCurrentClientSubcollection()
                        dismiss()
                    }
                }
            }
        } else {
            // Non-group booking or decline
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
                                "type": "booking_confirmed",
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
                        // Fetch will auto-add to calendar if enabled
                        firestore.fetchBookingsForCurrentClientSubcollection()
                        dismiss()
                    }
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
