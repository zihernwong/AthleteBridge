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

    // Resolve rate: prefer booking.RateUSD, fall back to coach's profile hourly rate
    private var resolvedRate: Double? {
        if let rate = booking.RateUSD { return rate }
        if let coach = firestore.coaches.first(where: { $0.id == booking.coachID }),
           let rate = coach.hourlyRate {
            return rate
        }
        return nil
    }

    private var rateDisplayText: String {
        if let rate = resolvedRate {
            return String(format: "$%.2f", rate)
        }
        return "—"
    }

    // Calculate duration in 0.5 hour increments (used for cost calculation)
    private var durationHours: Double {
        guard let start = booking.startAt, let end = booking.endAt else { return 0 }
        let totalMinutes = end.timeIntervalSince(start) / 60
        let halfHours = (totalMinutes / 30).rounded()
        return halfHours * 0.5
    }

    private var durationMinutes: Int {
        guard let start = booking.startAt, let end = booking.endAt else { return 0 }
        return Int(end.timeIntervalSince(start) / 60)
    }

    // Calculate total booking cost based on hourly rate and duration
    private var totalBookingCost: Double? {
        guard let rate = resolvedRate, durationHours > 0 else { return nil }
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
                                    Text(String(format: "$%.2f", rate))
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
                            if durationMinutes > 0 {
                                Text("(\(durationMinutes) mins)")
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

                    // Rate
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Rate")
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
                            if durationMinutes > 0 {
                                Text("(\(durationMinutes) mins)")
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

                if let notes = booking.notes, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notes")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(notes)
                            .font(.body)
                    }
                }

                if let note = booking.coachNote, !note.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Coach Note")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(note)
                            .font(.body)
                    }
                }

                Spacer()

                // Action buttons: Decline (left) and Confirm (right)
                HStack {
                    Button {
                        showDeclineSheet = true
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
        .sheet(isPresented: $showDeclineSheet) {
            NavigationStack {
                Form {
                    Section(header: Text("Reason for Declining")) {
                        Picker("Reason", selection: $selectedDeclineReason) {
                            ForEach(declineReasons, id: \.self) { reason in
                                Text(reason).tag(reason)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()

                        if selectedDeclineReason == "Other" {
                            TextField("Please specify...", text: $customDeclineReason)
                        }
                    }

                    Section {
                        Button(role: .destructive) {
                            showDeclineSheet = false
                            confirmOrDecline(status: "declined_by_client")
                        } label: {
                            Text("Confirm Decline")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(selectedDeclineReason == "Other" && customDeclineReason.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .navigationTitle("Decline Booking")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") { showDeclineSheet = false }
                    }
                }
            }
            .presentationDetents([.medium])
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
        } else if booking.isGroupBooking == true && status == "declined_by_client" {
            // Group booking decline: write reason to all mirrors, then update status
            let reason = declineReasonText
            let clientId = auth.user?.uid ?? ""
            let reasonPayload: [String: Any] = ["clientDeclineReason": reason, "declinedByClient": clientId, "declinedAt": FieldValue.serverTimestamp()]
            let batch = Firestore.firestore().batch()
            let bookingRef = Firestore.firestore().collection("bookings").document(booking.id)
            batch.updateData(reasonPayload, forDocument: bookingRef)
            for coachId in booking.allCoachIDs where !coachId.isEmpty {
                batch.updateData(reasonPayload, forDocument: Firestore.firestore().collection("coaches").document(coachId).collection("bookings").document(booking.id))
            }
            for cId in booking.allClientIDs where !cId.isEmpty {
                batch.updateData(reasonPayload, forDocument: Firestore.firestore().collection("clients").document(cId).collection("bookings").document(booking.id))
            }
            batch.commit { _ in }

            firestore.updateGroupBookingStatus(bookingId: booking.id, status: "declined_by_client") { err in
                DispatchQueue.main.async {
                    if let err = err {
                        firestore.showToast("Failed to update booking: \(err.localizedDescription)")
                    } else {
                        // Notify coaches
                        let clientName = self.firestore.currentClient?.name ?? "Client"
                        for coachId in self.booking.allCoachIDs where !coachId.isEmpty {
                            let notifRef = Firestore.firestore().collection("pendingNotifications").document(coachId).collection("notifications").document()
                            let notifPayload: [String: Any] = [
                                "title": "Group Booking Declined",
                                "body": "\(clientName) has declined the group booking. Reason: \(reason)",
                                "bookingId": self.booking.id,
                                "senderId": clientId,
                                "isGroupBooking": true,
                                "createdAt": FieldValue.serverTimestamp(),
                                "delivered": false
                            ]
                            notifRef.setData(notifPayload) { _ in }
                        }
                        firestore.showToast("Group booking declined")
                        firestore.fetchBookingsForCurrentClientSubcollection()
                        dismiss()
                    }
                }
            }
        } else {
            // Non-group booking
            if status == "declined_by_client" {
                // Write decline reason to all mirrors
                let reason = declineReasonText
                let clientId = auth.user?.uid ?? ""
                let updatePayload: [String: Any] = [
                    "Status": "declined_by_client",
                    "declinedAt": FieldValue.serverTimestamp(),
                    "declinedByClient": clientId,
                    "clientDeclineReason": reason
                ]
                let batch = Firestore.firestore().batch()
                let bookingRef = Firestore.firestore().collection("bookings").document(booking.id)
                batch.updateData(updatePayload, forDocument: bookingRef)
                if !booking.coachID.isEmpty {
                    batch.updateData(updatePayload, forDocument: Firestore.firestore().collection("coaches").document(booking.coachID).collection("bookings").document(booking.id))
                }
                if !clientId.isEmpty {
                    batch.updateData(updatePayload, forDocument: Firestore.firestore().collection("clients").document(clientId).collection("bookings").document(booking.id))
                }
                batch.commit { err in
                    DispatchQueue.main.async {
                        if let err = err {
                            firestore.showToast("Failed to decline: \(err.localizedDescription)")
                        } else {
                            // Notify coach with reason
                            if !self.booking.coachID.isEmpty {
                                let clientName = self.firestore.currentClient?.name ?? "Client"
                                let notifRef = Firestore.firestore().collection("pendingNotifications").document(self.booking.coachID).collection("notifications").document()
                                let notifPayload: [String: Any] = [
                                    "title": "Booking Declined",
                                    "body": "\(clientName) has declined your booking offer. Reason: \(reason)",
                                    "bookingId": self.booking.id,
                                    "senderId": clientId,
                                    "createdAt": FieldValue.serverTimestamp(),
                                    "delivered": false
                                ]
                                notifRef.setData(notifPayload) { _ in }
                            }
                            firestore.showToast("Booking declined")
                            firestore.fetchBookingsForCurrentClientSubcollection()
                            dismiss()
                        }
                    }
                }
            } else {
                // Confirm flow (unchanged)
                firestore.updateBookingStatus(bookingId: booking.id, status: status) { err in
                    DispatchQueue.main.async {
                        if let err = err {
                            firestore.showToast("Failed to update booking: \(err.localizedDescription)")
                        } else {
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
                            firestore.showToast("Booking confirmed")
                            firestore.fetchBookingsForCurrentClientSubcollection()
                            dismiss()
                        }
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
    @State private var showDeclineSheet: Bool = false
    @State private var selectedDeclineReason: String = "Too Expensive"
    @State private var customDeclineReason: String = ""
    private let declineReasons = ["Too Expensive", "Schedule Conflict", "Found Another Coach", "No Longer Needed", "Other"]

    private var declineReasonText: String {
        if selectedDeclineReason == "Other" {
            return customDeclineReason.trimmingCharacters(in: .whitespaces)
        }
        return selectedDeclineReason
    }

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
