import SwiftUI
import FirebaseFirestore

struct CoachConfirmedBookingsView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel

    var initialBookingId: String? = nil

    @State private var bookingToCancel: FirestoreManager.BookingItem? = nil
    @State private var showCancelAlert: Bool = false
    @State private var selectedBookingForDetail: FirestoreManager.BookingItem? = nil
    @State private var hasOpenedInitialBooking: Bool = false

    @State private var bookingToReschedule: FirestoreManager.BookingItem? = nil
    // Tab selection: 0 = Upcoming, 1 = Past
    @State private var selectedTab: Int = 0

    private func isUpcoming(_ booking: FirestoreManager.BookingItem) -> Bool {
        guard let endAt = booking.endAt else { return false }
        return endAt > Date()
    }
    private func isPast(_ booking: FirestoreManager.BookingItem) -> Bool {
        guard let endAt = booking.endAt else { return false }
        return endAt <= Date()
    }

    var body: some View {
        VStack {
            Picker("Tab", selection: $selectedTab) {
                Text("Upcoming").tag(0)
                Text("Past").tag(1)
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .top])

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(selectedTab == 0 ? "Upcoming Bookings" : "Past Bookings")
                        .font(.largeTitle).bold()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)

                    let confirmedBookings = firestore.coachBookings.filter { ($0.status ?? "").lowercased() == "confirmed" }
                    let filtered = selectedTab == 0 ? confirmedBookings.filter(isUpcoming) : confirmedBookings.filter(isPast)
                    if filtered.isEmpty {
                        Text("No \(selectedTab == 0 ? "upcoming" : "past") confirmed bookings")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                    } else {
                        ForEach(filtered, id: \.id) { b in
                            VStack(alignment: .leading, spacing: 8) {
                                Button(action: { selectedBookingForDetail = b }) {
                                    BookingRowView(item: b)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(PlainButtonStyle())

                                if (b.paymentStatus ?? "").lowercased() != "paid" {
                                    Button(action: {
                                        // Use appropriate function for group vs regular bookings
                                        if b.isGroupBooking == true {
                                            firestore.acknowledgeGroupBookingPayment(bookingId: b.id, paymentStatus: "paid") { err in
                                                DispatchQueue.main.async {
                                                    if let err = err {
                                                        firestore.showToast("Failed: \(err.localizedDescription)")
                                                    } else {
                                                        firestore.fetchBookingsForCurrentCoachSubcollection()
                                                        firestore.showToast("Payment acknowledged")
                                                        // Send notification to all clients
                                                        sendPaymentConfirmedNotifications(booking: b)
                                                    }
                                                }
                                            }
                                        } else {
                                            firestore.updateBookingPaymentStatus(bookingId: b.id, paymentStatus: "paid") { err in
                                                DispatchQueue.main.async {
                                                    if let err = err {
                                                        firestore.showToast("Failed: \(err.localizedDescription)")
                                                    } else {
                                                        firestore.fetchBookingsForCurrentCoachSubcollection()
                                                        firestore.showToast("Payment acknowledged")
                                                        // Send notification to client
                                                        sendPaymentConfirmedNotifications(booking: b)
                                                    }
                                                }
                                            }
                                        }
                                    }) {
                                        Text("Acknowledge Payment")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(Color("LogoBlue"))
                                } else {
                                    Text("Payment: Paid")
                                        .font(.caption)
                                        .foregroundColor(Color("LogoGreen"))
                                }

                                // Hide Cancel and Reschedule buttons for past bookings or once payment is acknowledged
                                if (b.paymentStatus ?? "").lowercased() != "paid" && isUpcoming(b) {
                                    // Reschedule booking button
                                    Button {
                                        bookingToReschedule = b
                                    } label: {
                                        Text("Reschedule Booking")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.blue)

                                    // Cancel booking button
                                    Button {
                                        bookingToCancel = b
                                        showCancelAlert = true
                                    } label: {
                                        Text("Cancel Booking")
                                            .foregroundColor(.red)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 8)
                                            .background(.ultraThinMaterial)
                                            .cornerRadius(8)
                                    }
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
        }
        .navigationTitle("Confirmed Bookings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            firestore.fetchBookingsForCurrentCoachSubcollection()
        }
        .onChange(of: firestore.coachBookings) { _, _ in
            openInitialBookingIfNeeded()
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
        .sheet(item: $selectedBookingForDetail) { booking in
            BookingDetailView(booking: booking)
                .environmentObject(firestore)
                .environmentObject(auth)
        }
        .onReceive(NotificationCenter.default.publisher(for: NotificationManager.didReceiveForegroundNotification)) { _ in
            firestore.fetchBookingsForCurrentCoachSubcollection()
        }
    }

    private func openInitialBookingIfNeeded() {
        guard let targetId = initialBookingId, !hasOpenedInitialBooking else { return }
        if let booking = firestore.coachBookings.first(where: { $0.id == targetId }) {
            hasOpenedInitialBooking = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.selectedBookingForDetail = booking
            }
        }
    }

    private func cancelBooking(_ booking: FirestoreManager.BookingItem) {
        firestore.updateBookingStatus(bookingId: booking.id, status: "cancelled") { err in
            DispatchQueue.main.async {
                if let err = err {
                    firestore.showToast("Failed to cancel: \(err.localizedDescription)")
                } else {
                    // Remove Apple Calendar entry for the cancelling coach
                    self.firestore.removeBookingFromAppleCalendar(bookingId: booking.id) { _ in }

                    // Send notification to client
                    if !booking.clientID.isEmpty {
                        let coachName = self.firestore.currentCoach?.name ?? "Coach"
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
                    self.firestore.showToast("Booking cancelled")
                    self.firestore.fetchBookingsForCurrentCoachSubcollection()
                }
            }
        }
    }

    private func sendPaymentConfirmedNotifications(booking: FirestoreManager.BookingItem) {
        let coachName = firestore.currentCoach?.name ?? "Coach"
        let coachId = booking.coachID

        // Get all client IDs to notify
        var clientIdsToNotify: [String] = []
        if let clientIDs = booking.clientIDs, !clientIDs.isEmpty {
            clientIdsToNotify = clientIDs
        } else if !booking.clientID.isEmpty {
            clientIdsToNotify = [booking.clientID]
        }

        // Send notification to each client
        for clientId in clientIdsToNotify {
            let notifRef = Firestore.firestore().collection("pendingNotifications").document(clientId).collection("notifications").document()
            let notifPayload: [String: Any] = [
                "title": "Payment Confirmed",
                "body": "\(coachName) has confirmed your payment.",
                "bookingId": booking.id,
                "senderId": coachId,
                "type": "payment_confirmed",
                "isGroupBooking": booking.isGroupBooking ?? false,
                "createdAt": FieldValue.serverTimestamp(),
                "delivered": false
            ]
            notifRef.setData(notifPayload) { err in
                if let err = err {
                    print("Failed to send payment confirmation notification to \(clientId): \(err)")
                }
            }
        }
    }
}

// MARK: - Coach Reschedule View (propose new time with date/time picker)
struct CoachRescheduleView: View {
    let booking: FirestoreManager.BookingItem
    let onComplete: () -> Void

    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var newStart: Date = Date()
    @State private var newEnd: Date = Date().addingTimeInterval(3600)
    @State private var isSaving: Bool = false
    @State private var showMinDurationAlert: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Start")
                        MinuteIntervalDatePicker(date: $newStart, minuteInterval: 30)
                            .frame(height: 150)
                            .padding(.bottom, 12)
                            .onChange(of: newStart) { _, val in
                                let intervalSeconds = 30 * 60
                                let t = val.timeIntervalSinceReferenceDate
                                let snapped = TimeInterval(Int((t + Double(intervalSeconds)/2.0) / Double(intervalSeconds))) * Double(intervalSeconds)
                                let snappedDate = Date(timeIntervalSinceReferenceDate: snapped)
                                if abs(snappedDate.timeIntervalSince(val)) > 0.1 { newStart = snappedDate }
                                if newEnd.timeIntervalSince(newStart) < 3600 {
                                    newEnd = Calendar.current.date(byAdding: .hour, value: 1, to: newStart) ?? newStart.addingTimeInterval(3600)
                                }
                            }
                        Text("End")
                        MinuteIntervalDatePicker(date: $newEnd, minuteInterval: 30)
                            .frame(height: 150)
                            .onChange(of: newEnd) { _, val in
                                let intervalSeconds = 30 * 60
                                let t = val.timeIntervalSinceReferenceDate
                                let snapped = TimeInterval(Int((t + Double(intervalSeconds)/2.0) / Double(intervalSeconds))) * Double(intervalSeconds)
                                let snappedDate = Date(timeIntervalSinceReferenceDate: snapped)
                                if abs(snappedDate.timeIntervalSince(val)) > 0.1 { newEnd = snappedDate }
                                if newEnd.timeIntervalSince(newStart) < 3600 {
                                    newStart = Calendar.current.date(byAdding: .hour, value: -1, to: newEnd) ?? newEnd.addingTimeInterval(-3600)
                                }
                            }
                    }
                } header: {
                    Text("Propose New Time")
                }

                if isSaving {
                    Section {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    }
                }
            }
            .navigationTitle("Reschedule Booking")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Propose") {
                        confirmReschedule()
                    }
                    .disabled(isSaving || !(newStart < newEnd) || newEnd.timeIntervalSince(newStart) < 3600)
                }
            }
            .onAppear {
                // Initialize pickers with the booking's current times
                newStart = booking.startAt ?? Date()
                newEnd = booking.endAt ?? Date().addingTimeInterval(3600)
            }
            .alert("Minimum Duration", isPresented: $showMinDurationAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Minimum booking length is 1 hour. Please select a longer time range.")
            }
        }
    }

    private func confirmReschedule() {
        if newEnd.timeIntervalSince(newStart) < 3600 {
            showMinDurationAlert = true
            return
        }
        isSaving = true
        firestore.rescheduleBooking(bookingId: booking.id, newStart: newStart, newEnd: newEnd, newStatus: "Pending Acceptance") { err in
            DispatchQueue.main.async {
                isSaving = false
                if let err = err {
                    firestore.showToast("Failed to reschedule: \(err.localizedDescription)")
                } else {
                    // Send notification to client
                    if !booking.clientID.isEmpty {
                        let coachName = firestore.currentCoach?.name ?? "Coach"
                        let notifRef = Firestore.firestore().collection("pendingNotifications").document(booking.clientID).collection("notifications").document()
                        let notifPayload: [String: Any] = [
                            "title": "Booking Reschedule Proposed",
                            "body": "\(coachName) has proposed a new time for your booking.",
                            "bookingId": booking.id,
                            "senderId": booking.coachID,
                            "createdAt": FieldValue.serverTimestamp(),
                            "delivered": false
                        ]
                        notifRef.setData(notifPayload) { _ in }
                    }
                    firestore.showToast("Reschedule proposed")
                    onComplete()
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
