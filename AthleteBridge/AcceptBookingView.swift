import SwiftUI
import Firebase
import FirebaseFirestore

struct AcceptBookingView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel
    @Environment(\.dismiss) var dismiss

    let booking: FirestoreManager.BookingItem

    @State private var rateText: String = ""
    @State private var note: String = ""
    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showRejectOptions: Bool = false
    @State private var selectedRejectReason: String = "Not Qualified"

    // Agreed-rate quick flow: the client requested at a pre-agreed price, so
    // accepting confirms the booking immediately (no client confirmation step).
    @State private var isAgreedRateRequest: Bool = false
    @State private var agreedRateLabel: String? = nil
    @State private var agreedRateUSD: Double? = nil
    @State private var showProposeDifferentRate: Bool = false
    // Client typed their own rate at request time (classic review flow)
    @State private var isClientProposedRate: Bool = false

    // Weekly series support: sibling "requested" bookings sharing recurrenceGroupId
    @State private var seriesBookingIds: [String] = []
    @State private var applyToSeries: Bool = true

    // Classic flow: remember this rate for future one-tap bookings
    @State private var saveAsAgreedRate: Bool = true
    @State private var agreedRateSaveLabel: String = "1-on-1"

    private let rejectReasons = ["Not Qualified", "Coach Unavailable", "Other"]

    // Whether the classic rate/note entry UI should be shown
    private var showClassicSections: Bool {
        !isAgreedRateRequest || showProposeDifferentRate
    }

    private var quickAcceptRate: Double? {
        agreedRateUSD ?? booking.RateUSD
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
        guard let rate = Double(rateText.replacingOccurrences(of: ",", with: ".")),
              durationHours > 0 else { return nil }
        return rate * durationHours
    }

    // Check if this is a group booking
    private var isGroupBooking: Bool {
        booking.isGroupBooking ?? false ||
        (booking.coachIDs?.count ?? 0) > 1 ||
        (booking.clientIDs?.count ?? 0) > 1
    }

    private func statusColor(for status: String) -> Color {
        switch status.lowercased() {
        case "confirmed":
            return Color("LogoGreen")
        case "requested":
            return Color("LogoBlue")
        default:
            return .primary
        }
    }

    // Resolve client display name: prefer booking.clientName, else lookup by clientID from firestore.clients
    private var clientDisplayName: String {
        if isGroupBooking {
            return booking.allClientNames.joined(separator: ", ")
        }
        if let name = booking.clientName, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            return name
        }
        if let client = firestore.clients.first(where: { $0.id == booking.clientID }), !client.name.trimmingCharacters(in: .whitespaces).isEmpty {
            return client.name
        }
        return "Client"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(isGroupBooking ? "Group Booking" : "Booking")) {
                    if isGroupBooking {
                        HStack {
                            Image(systemName: "person.3.fill")
                                .foregroundColor(.blue)
                            Text("Group Session")
                                .font(.subheadline)
                                .foregroundColor(.blue)
                        }
                    }

                    // Show clients - use list format for multiple clients
                    if isGroupBooking && booking.allClientNames.count > 1 {
                        HStack(alignment: .top) {
                            Text("Clients").bold()
                            Spacer()
                            VStack(alignment: .trailing) {
                                ForEach(booking.allClientNames, id: \.self) { name in
                                    Text(name).font(.subheadline)
                                }
                            }
                        }
                    } else {
                        HStack { Text("Client").bold(); Spacer(); Text(clientDisplayName) }
                    }

                    // Show all coaches for group bookings
                    if isGroupBooking && booking.allCoachNames.count > 1 {
                        HStack(alignment: .top) {
                            Text("Coaches").bold()
                            Spacer()
                            VStack(alignment: .trailing) {
                                ForEach(booking.allCoachNames, id: \.self) { name in
                                    Text(name).font(.subheadline)
                                }
                            }
                        }
                    }

                    if let status = booking.status, !status.isEmpty {
                        HStack {
                            Text("Status").bold()
                            Spacer()
                            Text(status.replacingOccurrences(of: "_", with: " ").capitalized)
                                .foregroundColor(statusColor(for: status))
                        }
                    }
                    if let start = booking.startAt {
                        HStack { Text("Starts").bold(); Spacer(); Text(DateFormatter.localizedString(from: start, dateStyle: .medium, timeStyle: .short)) }
                    }
                    if let end = booking.endAt {
                        HStack { Text("Ends").bold(); Spacer(); Text(DateFormatter.localizedString(from: end, dateStyle: .medium, timeStyle: .short)) }
                    }
                    if let start = booking.startAt, let end = booking.endAt {
                        let mins = Int(end.timeIntervalSince(start) / 60)
                        HStack { Text("Duration").bold(); Spacer(); Text("\(mins) min") }
                    }
                }

                // Show coach acceptance status for group bookings
                if isGroupBooking {
                    Section(header: Text("Coach Acceptances")) {
                        ForEach(booking.allCoachIDs, id: \.self) { coachId in
                            let coachName = booking.coachNames?.first(where: { name in
                                booking.coachIDs?.firstIndex(where: { $0 == coachId }).map { idx in
                                    booking.coachNames?.indices.contains(idx) == true && booking.coachNames?[idx] == name
                                } ?? false
                            }) ?? coachId
                            let accepted = booking.coachAcceptances?[coachId] ?? false
                            let isRejector = booking.rejectedBy == coachId
                            let bookingRejected = (booking.status ?? "").lowercased() == "rejected"
                            HStack {
                                Text(coachName)
                                Spacer()
                                if isRejector || (bookingRejected && !accepted) {
                                    Label("Rejected", systemImage: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                        .font(.caption)
                                } else if accepted {
                                    Label("Accepted", systemImage: "checkmark.circle.fill")
                                        .foregroundColor(Color("LogoGreen"))
                                        .font(.caption)
                                } else {
                                    Label("Pending", systemImage: "clock")
                                        .foregroundColor(.orange)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                }

                // Weekly series: offer to handle every requested session at once
                if !seriesBookingIds.isEmpty {
                    Section(header: Text("Weekly Series")) {
                        Toggle("Apply to all \(seriesBookingIds.count + 1) requested sessions", isOn: $applyToSeries)
                        Text("This booking is part of a weekly series. Accepting with this on handles every requested week in one tap.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Agreed-rate quick accept: rate was pre-agreed, one tap confirms
                if isAgreedRateRequest && !isGroupBooking {
                    Section(header: Text("Agreed Rate")) {
                        HStack {
                            Text(agreedRateLabel ?? "Agreed rate").bold()
                            Spacer()
                            if let rate = quickAcceptRate {
                                Text(String(format: "$%.2f / hr", rate))
                            }
                        }
                        if let rate = quickAcceptRate, durationHours > 0 {
                            HStack {
                                Text("Session total")
                                Spacer()
                                Text(String(format: "$%.2f", rate * durationHours)).bold()
                                Text("(\(durationMinutes) mins)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Label("\(clientDisplayName) booked at your agreed rate. Accepting confirms the session immediately — no further steps for either of you.", systemImage: "bolt.fill")
                            .font(.caption)
                            .foregroundColor(Color("LogoGreen"))
                    }

                    Section {
                        Button(action: acceptAndConfirm) {
                            HStack {
                                if isSaving {
                                    ProgressView()
                                } else {
                                    Image(systemName: "checkmark.circle.fill")
                                    Text(firestore.currentCoach?.subscriptionTier == .pro ? "Accept — Awaiting Payment" : "Accept & Confirm")
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color("LogoGreen"))
                        .disabled(isSaving || quickAcceptRate == nil)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)

                        if !showProposeDifferentRate {
                            Button("Propose a different rate instead") {
                                if let rate = quickAcceptRate { rateText = String(format: "%.2f", rate) }
                                showProposeDifferentRate = true
                            }
                            .font(.subheadline)
                        }
                    }
                }

                if showClassicSections {
                    Section {
                        HStack {
                            Text("$")
                            TextField("e.g. 45.00", text: $rateText)
                                .keyboardType(.decimalPad)
                                .disableAutocorrection(true)
                        }
                        if isClientProposedRate {
                            Label("\(clientDisplayName) proposed this rate. Save to accept it, or change it before saving.", systemImage: "person.fill.questionmark")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    } header: {
                        Text("Rate")
                    }

                    Section(header: Text("Total Booking Cost (USD)")) {
                        HStack {
                            Text("$")
                            if let total = totalBookingCost {
                                Text(String(format: "%.2f", total))
                                    .foregroundColor(.secondary)
                            } else {
                                Text("—")
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if durationMinutes > 0 {
                                Text("(\(durationMinutes) mins)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    // Remember this rate so future bookings from this client are one-tap
                    if !isGroupBooking {
                        Section(header: Text("Agreed Rate for Future Bookings")) {
                            Toggle("Save as agreed rate", isOn: $saveAsAgreedRate)
                            if saveAsAgreedRate {
                                TextField("Rate label (e.g. 1-on-1, Joint session)", text: $agreedRateSaveLabel)
                                Text("\(clientDisplayName) will see this rate when requesting future sessions, and your acceptance will confirm them instantly.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Section(header: Text("Optional note to client")) {
                        TextEditor(text: $note)
                            .frame(minHeight: 100)
                    }
                }

                if let err = errorMessage {
                    Section {
                        Text(err).foregroundColor(.red).font(.caption)
                    }
                }

                // Reject booking section
                Section(header: Text("Reject Booking")) {
                    DisclosureGroup("Reject this booking", isExpanded: $showRejectOptions) {
                        Picker("Reason", selection: $selectedRejectReason) {
                            ForEach(rejectReasons, id: \.self) { reason in
                                Text(reason).tag(reason)
                            }
                        }
                        .pickerStyle(.menu)

                        Button(role: .destructive, action: rejectBooking) {
                            HStack {
                                if isSaving {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle())
                                } else {
                                    Image(systemName: "xmark.circle.fill")
                                    Text("Reject Booking")
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .disabled(isSaving)
                    }
                }
            }
            .navigationTitle("Accept Booking")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if showClassicSections {
                        Button(action: save) {
                            if isSaving { ProgressView() } else { Text("Save") }
                        }
                        .disabled(isSaving || !(isValidRate() || note.count > 0))
                    }
                }
            }
            .onAppear {
                // Prefill the rate field: use booking.RateUSD if present; otherwise fallback to coach hourlyRate
                if let r = booking.RateUSD, r > 0 {
                    rateText = String(format: "%.2f", r)
                } else if let hr = firestore.currentCoach?.hourlyRate, hr > 0 {
                    rateText = String(format: "%.2f", hr)
                }
                // Ensure clients list is available for name resolution
                firestore.fetchClients()
                loadRequestDetails()
            }
        }
    }

    private func isValidRate() -> Bool {
        guard !rateText.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return Double(rateText.replacingOccurrences(of: ",", with: ".")) != nil
    }

    /// Load fields not carried on BookingItem: the agreed-rate flag/label and
    /// any sibling bookings in the same weekly series that are still requested.
    private func loadRequestDetails() {
        let db = Firestore.firestore()
        db.collection("bookings").document(booking.id).getDocument { snap, _ in
            guard let data = snap?.data() else { return }
            let docRate = (data["RateUSD"] as? Double) ?? ((data["RateUSD"] as? Int).map { Double($0) })
            DispatchQueue.main.async {
                self.agreedRateUSD = self.booking.RateUSD ?? docRate
                if (data["AgreedRate"] as? Bool) == true, self.agreedRateUSD != nil {
                    self.isAgreedRateRequest = true
                }
                if (data["ProposedRate"] as? Bool) == true {
                    self.isClientProposedRate = true
                }
                if let label = data["RateLabel"] as? String, !label.isEmpty {
                    self.agreedRateLabel = label
                    self.agreedRateSaveLabel = label
                }
            }
            if let groupId = data["recurrenceGroupId"] as? String, !groupId.isEmpty {
                db.collection("bookings")
                    .whereField("recurrenceGroupId", isEqualTo: groupId)
                    .whereField("Status", isEqualTo: "requested")
                    .getDocuments { qsnap, _ in
                        let siblingIds = (qsnap?.documents.map { $0.documentID } ?? []).filter { $0 != self.booking.id }
                        DispatchQueue.main.async { self.seriesBookingIds = siblingIds }
                    }
            }
        }
    }

    /// One-tap accept for agreed-rate requests: the client already committed to
    /// the price, so the coach's acceptance confirms the booking directly
    /// (Pro coaches still collect payment first).
    private func acceptAndConfirm() {
        guard let currentUserId = auth.user?.uid else {
            errorMessage = "Not authenticated"
            return
        }
        guard let rate = quickAcceptRate else {
            errorMessage = "Missing agreed rate"
            return
        }

        isSaving = true
        errorMessage = nil

        let isPro = firestore.currentCoach?.subscriptionTier == .pro
        let newStatus = isPro ? "pending_payment" : "confirmed"

        var updatePayload: [String: Any] = [
            "Status": newStatus,
            "RateUSD": rate,
            "confirmedVia": "agreed_rate"
        ]
        if isPro {
            updatePayload["requiresPaymentUpfront"] = true
            updatePayload["pendingAt"] = FieldValue.serverTimestamp()
        } else {
            updatePayload["confirmedAt"] = FieldValue.serverTimestamp()
        }

        let db = Firestore.firestore()
        let coachId = booking.coachID
        let clientId = booking.clientID
        let targetIds = (applyToSeries && !seriesBookingIds.isEmpty) ? [booking.id] + seriesBookingIds : [booking.id]

        let batch = db.batch()
        for bookingId in targetIds {
            batch.updateData(updatePayload, forDocument: db.collection("bookings").document(bookingId))
            if !coachId.isEmpty {
                batch.updateData(updatePayload, forDocument: db.collection("coaches").document(coachId).collection("bookings").document(bookingId))
                let summary: [String: Any] = ["id": bookingId, "updatedAt": Timestamp(date: Date()), "Status": newStatus, "RateUSD": rate]
                batch.updateData(["calendar": FieldValue.arrayUnion([summary])], forDocument: db.collection("coaches").document(coachId))
            }
            if !clientId.isEmpty {
                batch.updateData(updatePayload, forDocument: db.collection("clients").document(clientId).collection("bookings").document(bookingId))
            }
        }

        batch.commit { err in
            DispatchQueue.main.async {
                self.isSaving = false
                if let err = err {
                    self.errorMessage = err.localizedDescription
                    return
                }
                // Notify the client
                if !clientId.isEmpty {
                    let coachName = self.firestore.currentCoach?.name ?? "Your coach"
                    let sessionText = targetIds.count > 1 ? "your \(targetIds.count) weekly sessions" : "your booking"
                    let notifRef = Firestore.firestore().collection("pendingNotifications").document(clientId).collection("notifications").document()
                    let notifPayload: [String: Any] = isPro ? [
                        "title": "Payment Required to Confirm Booking",
                        "body": "\(coachName) has accepted \(sessionText) at your agreed rate. Please make payment to confirm.",
                        "bookingId": self.booking.id,
                        "senderId": coachId,
                        "type": "payment_required",
                        "createdAt": FieldValue.serverTimestamp(),
                        "delivered": false
                    ] : [
                        "title": "Booking Confirmed 🎉",
                        "body": "\(coachName) confirmed \(sessionText) at \(String(format: "$%.2f", rate))/hr. You're all set!",
                        "bookingId": self.booking.id,
                        "senderId": coachId,
                        "type": "booking_confirmed",
                        "createdAt": FieldValue.serverTimestamp(),
                        "delivered": false
                    ]
                    notifRef.setData(notifPayload) { nerr in
                        if let nerr = nerr {
                            print("[AcceptBookingView] Failed to send confirmation notification: \(nerr)")
                        }
                    }
                }
                self.firestore.fetchBookingsForCurrentCoachSubcollection()
                let toast = isPro
                    ? "Accepted — awaiting client payment"
                    : (targetIds.count > 1 ? "Confirmed \(targetIds.count) sessions" : "Booking confirmed")
                self.firestore.showToast(toast)
                dismiss()
            }
        }
    }

    private func rejectBooking() {
        guard let currentUserId = auth.user?.uid else {
            errorMessage = "Not authenticated"
            return
        }

        isSaving = true
        errorMessage = nil

        let allCoachIds = booking.allCoachIDs
        let allClientIds = booking.allClientIDs

        print("[AcceptBookingView] rejectBooking: bookingId=\(booking.id), rejectedBy=\(currentUserId), coaches=\(allCoachIds), clients=\(allClientIds)")

        var updatePayload: [String: Any] = [
            "Status": "rejected",
            "rejectedBy": currentUserId,
            "rejectionReason": selectedRejectReason,
            "rejectedAt": FieldValue.serverTimestamp()
        ]

        // For group bookings, also update the CoachAcceptances map so the rejecting coach shows as rejected
        if isGroupBooking {
            updatePayload["CoachAcceptances.\(currentUserId)"] = false
        }

        let batch = Firestore.firestore().batch()

        // Update main bookings collection
        let bookingRef = Firestore.firestore().collection("bookings").document(booking.id)
        batch.updateData(updatePayload, forDocument: bookingRef)
        print("[AcceptBookingView] rejectBooking: updating bookings/\(booking.id)")

        // Update ALL coaches' bookings subcollections
        for coachId in allCoachIds where !coachId.isEmpty {
            let coachBookingRef = Firestore.firestore().collection("coaches").document(coachId).collection("bookings").document(booking.id)
            batch.updateData(updatePayload, forDocument: coachBookingRef)
            print("[AcceptBookingView] rejectBooking: updating coaches/\(coachId)/bookings/\(booking.id)")
        }

        // Update ALL clients' bookings subcollections
        for clientId in allClientIds where !clientId.isEmpty {
            let clientBookingRef = Firestore.firestore().collection("clients").document(clientId).collection("bookings").document(booking.id)
            batch.updateData(updatePayload, forDocument: clientBookingRef)
            print("[AcceptBookingView] rejectBooking: updating clients/\(clientId)/bookings/\(booking.id)")
        }

        batch.commit { err in
            DispatchQueue.main.async {
                self.isSaving = false
                if let err = err {
                    self.errorMessage = err.localizedDescription
                } else {
                    // Send notification to ALL clients about rejection
                    let coachName = self.firestore.currentCoach?.name ?? "The coach"
                    for clientId in allClientIds where !clientId.isEmpty {
                        let notifRef = Firestore.firestore().collection("pendingNotifications").document(clientId).collection("notifications").document()
                        let notifPayload: [String: Any] = [
                            "title": "Booking Declined",
                            "body": "\(coachName) has declined your booking request. Reason: \(self.selectedRejectReason)",
                            "bookingId": self.booking.id,
                            "type": "booking_rejected",
                            "senderId": currentUserId,
                            "isGroupBooking": self.isGroupBooking,
                            "createdAt": FieldValue.serverTimestamp(),
                            "delivered": false
                        ]
                        notifRef.setData(notifPayload) { nerr in
                            if let nerr = nerr {
                                print("[AcceptBookingView] Failed to send rejection notification to \(clientId): \(nerr)")
                            }
                        }
                    }
                    self.firestore.fetchBookingsForCurrentCoachSubcollection()
                    self.firestore.showToast("Booking rejected")
                    dismiss()
                }
            }
        }
    }

    private func save() {
        // Use AuthViewModel's user property for auth state rather than calling Firebase directly
        guard let currentUserId = auth.user?.uid else {
            errorMessage = "Not authenticated"
            return
        }

        isSaving = true
        errorMessage = nil

        let rateVal = Double(rateText.replacingOccurrences(of: ",", with: "."))

        // Use group booking acceptance for group bookings
        if isGroupBooking {
            firestore.acceptGroupBookingAsCoach(
                bookingId: booking.id,
                coachId: currentUserId,
                rateUSD: rateVal,
                coachNote: note.isEmpty ? nil : note
            ) { err in
                DispatchQueue.main.async {
                    self.isSaving = false
                    if let err = err {
                        self.errorMessage = err.localizedDescription
                    } else {
                        self.firestore.fetchBookingsForCurrentCoachSubcollection()
                        self.firestore.showToast("Accepted group booking")
                        dismiss()
                    }
                }
            }
            return
        }

        // Original single-coach booking flow
        let db = Firestore.firestore()
        let coachId = booking.coachID
        let clientId = booking.clientID

        let isPro = firestore.currentCoach?.subscriptionTier == .pro
        let newStatus = isPro ? "pending_payment" : "Pending Acceptance"

        var updatePayload: [String: Any] = ["Status": newStatus]
        if let r = rateVal { updatePayload["RateUSD"] = r }
        if !note.isEmpty { updatePayload["CoachNote"] = note }
        updatePayload["pendingAt"] = FieldValue.serverTimestamp()
        if isPro { updatePayload["requiresPaymentUpfront"] = true }

        // Apply to the whole weekly series when requested
        let targetIds = (applyToSeries && !seriesBookingIds.isEmpty) ? [booking.id] + seriesBookingIds : [booking.id]

        let batch = db.batch()
        for bookingId in targetIds {
            batch.updateData(updatePayload, forDocument: db.collection("bookings").document(bookingId))
            if !coachId.isEmpty {
                batch.updateData(updatePayload, forDocument: db.collection("coaches").document(coachId).collection("bookings").document(bookingId))
                // append small summary to coach.calendar
                var bookingSummary: [String: Any] = ["id": bookingId, "updatedAt": Timestamp(date: Date()), "Status": newStatus]
                if let r = rateVal { bookingSummary["RateUSD"] = r }
                if !note.isEmpty { bookingSummary["CoachNote"] = note }
                batch.updateData(["calendar": FieldValue.arrayUnion([bookingSummary])], forDocument: db.collection("coaches").document(coachId))
            }
            if !clientId.isEmpty {
                batch.updateData(updatePayload, forDocument: db.collection("clients").document(clientId).collection("bookings").document(bookingId))
            }
        }

        // Remember this rate for future one-tap bookings with this client
        if saveAsAgreedRate, !isGroupBooking, let r = rateVal, r > 0, !clientId.isEmpty {
            firestore.saveAgreedRate(coachId: currentUserId, clientId: clientId, label: agreedRateSaveLabel, rateUSD: r)
        }

        batch.commit { err in
            DispatchQueue.main.async {
                self.isSaving = false
                if let err = err {
                    self.errorMessage = err.localizedDescription
                } else {
                    // Send notification to client
                    if !clientId.isEmpty {
                        let coachName = self.firestore.currentCoach?.name ?? "Your coach"
                        let notifRef = Firestore.firestore().collection("pendingNotifications").document(clientId).collection("notifications").document()
                        let notifPayload: [String: Any]
                        if isPro {
                            notifPayload = [
                                "title": "Payment Required to Confirm Booking",
                                "body": "\(coachName) has accepted your booking. Please make payment to confirm.",
                                "bookingId": self.booking.id,
                                "senderId": coachId,
                                "type": "payment_required",
                                "createdAt": FieldValue.serverTimestamp(),
                                "delivered": false
                            ]
                        } else {
                            notifPayload = [
                                "title": "Action Required: Confirm Booking",
                                "body": "\(coachName) has accepted your booking. Please confirm.",
                                "bookingId": self.booking.id,
                                "senderId": coachId,
                                "createdAt": FieldValue.serverTimestamp(),
                                "delivered": false
                            ]
                        }
                        notifRef.setData(notifPayload) { nerr in
                            if let nerr = nerr {
                                print("[AcceptBookingView] Failed to send notification to client: \(nerr)")
                            }
                        }
                    }
                    // refresh using environment object's convenience method
                    self.firestore.fetchBookingsForCurrentCoachSubcollection()
                    let toastMessage = isPro ? "Awaiting client payment" : "Booking pending acceptance"
                    self.firestore.showToast(toastMessage)
                    dismiss()
                }
            }
        }
    }
}

struct AcceptBookingView_Previews: PreviewProvider {
    static var previews: some View {
        AcceptBookingView(booking: FirestoreManager.BookingItem(id: "1", clientID: "c1", clientName: "Alice", coachID: "s1", coachName: "Coach Sam", startAt: Date(), endAt: Date().addingTimeInterval(1800), location: "Court 1", notes: "Bring racket", status: "requested", paymentStatus: "unpaid", RateUSD: 45.0))
            .environmentObject(FirestoreManager())
            .environmentObject(AuthViewModel())
    }
}
