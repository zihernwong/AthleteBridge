import SwiftUI
import FirebaseFirestore

struct ReviewBookingView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    let booking: FirestoreManager.BookingItem

    // Payment upfront flow (pro coaches)
    @State private var coachPayments: [String: String] = [:]
    @State private var isSubmittingPayment: Bool = false
    @State private var showPaymentMethodsSheet: Bool = false

    private var requiresPaymentUpfront: Bool {
        booking.requiresPaymentUpfront == true
    }

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
            ZStack {
                // Subtle background logo watermark
                if let bg = appLogoImageSwiftUI() {
                    bg
                        .resizable()
                        .scaledToFit()
                        .opacity(0.04)
                        .frame(maxWidth: 400)
                        .allowsHitTesting(false)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header with icon
                        HStack(spacing: 12) {
                            Image(systemName: "calendar.badge.checkmark")
                                .font(.system(size: 32))
                                .foregroundColor(Color("LogoGreen"))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Review Booking")
                                    .font(.title2)
                                    .bold()
                                Text("Please review and confirm the details below")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.bottom, 4)

                        // Coach & Rate Card
                        VStack(alignment: .leading, spacing: 12) {
                            if isMultiCoachBooking {
                                Label("Coaches & Rates", systemImage: "person.2.fill")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(Color("LogoBlue"))

                                ForEach(coachRatesForDisplay, id: \.id) { coach in
                                    HStack {
                                        Image(systemName: "person.circle.fill")
                                            .foregroundColor(Color("LogoGreen"))
                                        Text(coach.name)
                                            .font(.body)
                                            .fontWeight(.medium)
                                        Spacer()
                                        if let rate = coach.rate {
                                            Text(String(format: "$%.2f/hr", rate))
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                                .foregroundColor(Color("LogoGreen"))
                                        } else {
                                            Text("Rate pending")
                                                .font(.subheadline)
                                                .foregroundColor(.orange)
                                        }
                                    }
                                }

                                Divider()

                                HStack {
                                    Text("Total")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    if durationMinutes > 0 {
                                        Text("(\(durationMinutes) mins)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Text(totalCombinedCostDisplayText)
                                        .font(.title3)
                                        .fontWeight(.bold)
                                        .foregroundColor(Color("LogoGreen"))
                                }
                            } else {
                                Label("Coach", systemImage: "person.fill")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(Color("LogoBlue"))

                                HStack {
                                    Image(systemName: "person.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(Color("LogoGreen"))
                                    Text(coachDisplayName)
                                        .font(.body)
                                        .fontWeight(.medium)
                                    Spacer()
                                    Text(rateDisplayText + "/hr")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(Color("LogoGreen"))
                                }

                                Divider()

                                HStack {
                                    Text("Total")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    if durationMinutes > 0 {
                                        Text("(\(durationMinutes) mins)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Text(totalCostDisplayText)
                                        .font(.title3)
                                        .fontWeight(.bold)
                                        .foregroundColor(Color("LogoGreen"))
                                }
                            }
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(12)

                        // Schedule Card
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Schedule", systemImage: "clock.fill")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(Color("LogoBlue"))

                            if let start = booking.startAt {
                                HStack(spacing: 8) {
                                    Image(systemName: "play.circle.fill")
                                        .foregroundColor(Color("LogoGreen"))
                                    Text(DateFormatter.localizedString(from: start, dateStyle: .medium, timeStyle: .short))
                                        .font(.body)
                                }
                            }
                            if let end = booking.endAt {
                                HStack(spacing: 8) {
                                    Image(systemName: "stop.circle.fill")
                                        .foregroundColor(.red.opacity(0.7))
                                    Text(DateFormatter.localizedString(from: end, dateStyle: .medium, timeStyle: .short))
                                        .font(.body)
                                }
                            }
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(12)

                        // Notes Card (if any)
                        if (booking.notes != nil && !booking.notes!.isEmpty) || (booking.coachNote != nil && !booking.coachNote!.isEmpty) {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("Notes", systemImage: "note.text")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(Color("LogoBlue"))

                                if let notes = booking.notes, !notes.isEmpty {
                                    Text(notes)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                }

                                if let note = booking.coachNote, !note.isEmpty {
                                    Divider()
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("From Coach")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(note)
                                            .font(.body)
                                            .foregroundColor(.primary)
                                    }
                                }
                            }
                            .padding()
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(12)
                        }

                        // Payment upfront section (pro coaches only)
                        if requiresPaymentUpfront {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("Payment Required", systemImage: "creditcard.fill")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(Color("LogoBlue"))

                                Text("This coach requires payment before your booking is confirmed. Please pay using one of their methods below, then tap \"I've Paid\".")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                if coachPayments.isEmpty {
                                    Text("No payment methods on file — contact your coach directly.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    ForEach(coachPayments.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                                        HStack {
                                            Text(key.capitalized)
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                            Spacer()
                                            Text(value)
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color(UIColor.tertiarySystemBackground))
                                        .cornerRadius(8)
                                    }
                                }

                                Button(action: { showPaymentMethodsSheet = true }) {
                                    Text("Open Payment App")
                                        .font(.subheadline)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(Color("LogoBlue").opacity(0.15))
                                        .foregroundColor(Color("LogoBlue"))
                                        .cornerRadius(10)
                                }
                            }
                            .padding()
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(12)
                        }

                        // Action buttons
                        HStack(spacing: 12) {
                            Button {
                                showDeclineSheet = true
                            } label: {
                                HStack {
                                    Image(systemName: "xmark")
                                    Text("Decline")
                                }
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color("LogoBlue"))
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }

                            if requiresPaymentUpfront {
                                Button {
                                    submitPayment()
                                } label: {
                                    HStack {
                                        if isSubmittingPayment {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        } else {
                                            Image(systemName: "checkmark.seal.fill")
                                            Text("I've Paid")
                                        }
                                    }
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color("LogoGreen"))
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                                }
                                .disabled(isSubmittingPayment)
                            } else {
                                Button {
                                    confirmOrDecline(status: "confirmed")
                                } label: {
                                    HStack {
                                        Image(systemName: "checkmark")
                                        Text("Confirm")
                                    }
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color("LogoGreen"))
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                                }
                            }
                        }
                        .padding(.top, 8)
                    }
                    .padding()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                if requiresPaymentUpfront && !booking.coachID.isEmpty {
                    FirestoreManager.shared.fetchCoachPayments(coachIdOrPath: booking.coachID) { map in
                        DispatchQueue.main.async { self.coachPayments = map }
                    }
                }
            }
            .sheet(isPresented: $showPaymentMethodsSheet) {
                CoachPaymentMethodsSheet(
                    coachName: booking.coachName ?? "Coach",
                    payments: coachPayments
                )
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
                                "type": "booking_declined",
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
                                    "type": "booking_declined",
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

    private func submitPayment() {
        guard let clientId = auth.user?.uid else {
            firestore.showToast("Not authenticated")
            return
        }
        isSubmittingPayment = true
        let db = Firestore.firestore()
        let updatePayload: [String: Any] = [
            "Status": "payment_submitted",
            "paymentSubmittedAt": FieldValue.serverTimestamp(),
            "paymentSubmittedByClient": clientId
        ]
        let batch = db.batch()
        batch.updateData(updatePayload, forDocument: db.collection("bookings").document(booking.id))
        if !booking.coachID.isEmpty {
            batch.updateData(updatePayload, forDocument: db.collection("coaches").document(booking.coachID).collection("bookings").document(booking.id))
        }
        batch.updateData(updatePayload, forDocument: db.collection("clients").document(clientId).collection("bookings").document(booking.id))
        batch.commit { err in
            DispatchQueue.main.async {
                self.isSubmittingPayment = false
                if let err = err {
                    self.firestore.showToast("Failed: \(err.localizedDescription)")
                } else {
                    if !self.booking.coachID.isEmpty {
                        let clientName = self.firestore.currentClient?.name ?? "Client"
                        let notifRef = db.collection("pendingNotifications").document(self.booking.coachID).collection("notifications").document()
                        let notifPayload: [String: Any] = [
                            "title": "Payment Submitted",
                            "body": "\(clientName) has submitted payment. Please confirm receipt to finalize the booking.",
                            "bookingId": self.booking.id,
                            "senderId": clientId,
                            "type": "payment_submitted",
                            "createdAt": FieldValue.serverTimestamp(),
                            "delivered": false
                        ]
                        notifRef.setData(notifPayload) { _ in }
                    }
                    self.firestore.fetchBookingsForCurrentClientSubcollection()
                    self.firestore.showToast("Payment submitted. Awaiting coach confirmation.")
                    self.dismiss()
                }
            }
        }
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
