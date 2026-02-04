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
                            Text(status.capitalized)
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
                if isGroupBooking, let acceptances = booking.coachAcceptances {
                    Section(header: Text("Coach Acceptances")) {
                        ForEach(booking.allCoachIDs, id: \.self) { coachId in
                            let coachName = booking.coachNames?.first(where: { name in
                                booking.coachIDs?.firstIndex(where: { $0 == coachId }).map { idx in
                                    booking.coachNames?.indices.contains(idx) == true && booking.coachNames?[idx] == name
                                } ?? false
                            }) ?? coachId
                            let accepted = acceptances[coachId] ?? false
                            HStack {
                                Text(coachName)
                                Spacer()
                                if accepted {
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

                Section(header: Text("Hourly Rate")) {
                    HStack {
                        Text("$")
                        TextField("e.g. 45.00", text: $rateText)
                            .keyboardType(.decimalPad)
                            .disableAutocorrection(true)
                    }
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
                        if durationHours > 0 {
                            Text("(\(String(format: "%.1f", durationHours)) hrs)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section(header: Text("Optional note to client")) {
                    TextEditor(text: $note)
                        .frame(minHeight: 100)
                }

                if let err = errorMessage {
                    Section {
                        Text(err).foregroundColor(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Accept Booking")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: save) {
                        if isSaving { ProgressView() } else { Text("Save") }
                    }
                    .disabled(isSaving || !(isValidRate() || note.count > 0))
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
            }
        }
    }

    private func isValidRate() -> Bool {
        guard !rateText.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return Double(rateText.replacingOccurrences(of: ",", with: ".")) != nil
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
        let bookingRef = Firestore.firestore().collection("bookings").document(booking.id)
        let coachId = booking.coachID
        let clientId = booking.clientID

        var updatePayload: [String: Any] = ["Status": "Pending Acceptance"]
        if let r = rateVal { updatePayload["RateUSD"] = r }
        if !note.isEmpty { updatePayload["CoachNote"] = note }
        updatePayload["pendingAt"] = FieldValue.serverTimestamp()

        let batch = Firestore.firestore().batch()
        batch.updateData(updatePayload, forDocument: bookingRef)

        if !coachId.isEmpty {
            let coachBookingRef = Firestore.firestore().collection("coaches").document(coachId).collection("bookings").document(booking.id)
            batch.updateData(updatePayload, forDocument: coachBookingRef)
            // append small summary to coach.calendar
            var bookingSummary: [String: Any] = ["id": booking.id, "updatedAt": Timestamp(date: Date()), "Status": "Pending Acceptance"]
            if let r = rateVal { bookingSummary["RateUSD"] = r }
            if !note.isEmpty { bookingSummary["CoachNote"] = note }
            let coachDocRef = Firestore.firestore().collection("coaches").document(coachId)
            batch.updateData(["calendar": FieldValue.arrayUnion([bookingSummary])], forDocument: coachDocRef)
        }

        if !clientId.isEmpty {
            let clientBookingRef = Firestore.firestore().collection("clients").document(clientId).collection("bookings").document(booking.id)
            batch.updateData(updatePayload, forDocument: clientBookingRef)
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
                        let notifPayload: [String: Any] = [
                            "title": "Action Required: Confirm Booking",
                            "body": "\(coachName) has accepted your booking. Please confirm.",
                            "bookingId": self.booking.id,
                            "senderId": coachId,
                            "createdAt": FieldValue.serverTimestamp(),
                            "delivered": false
                        ]
                        notifRef.setData(notifPayload) { nerr in
                            if let nerr = nerr {
                                print("[AcceptBookingView] Failed to send notification to client: \(nerr)")
                            }
                        }
                    }
                    // refresh using environment object's convenience method
                    self.firestore.fetchBookingsForCurrentCoachSubcollection()
                    self.firestore.showToast("Booking pending acceptance")
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
