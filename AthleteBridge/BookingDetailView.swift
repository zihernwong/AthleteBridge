import SwiftUI

struct BookingDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel

    let booking: FirestoreManager.BookingItem

    private var currentUserRole: String? {
        firestore.currentUserType?.uppercased()
    }

    private var isGroupBooking: Bool {
        booking.isGroupBooking ?? false ||
        (booking.coachIDs?.count ?? 0) > 1 ||
        (booking.clientIDs?.count ?? 0) > 1
    }

    private var coachDisplayName: String {
        if isGroupBooking && !booking.allCoachNames.isEmpty {
            return booking.allCoachNames.joined(separator: ", ")
        }
        return booking.coachName ?? "Coach"
    }

    private var clientDisplayName: String {
        if isGroupBooking && !booking.allClientNames.isEmpty {
            return booking.allClientNames.joined(separator: ", ")
        }
        return booking.clientName ?? "Client"
    }

    private func statusColor(for status: String?) -> Color {
        switch (status ?? "").lowercased() {
        case "confirmed", "fully_confirmed":
            return Color("LogoGreen")
        case "requested":
            return Color("LogoBlue")
        case "pending acceptance":
            return .orange
        case "rejected", "declined", "declined_by_client":
            return .red
        case "partially_accepted", "partially_confirmed":
            return .orange
        default:
            return .secondary
        }
    }

    // Calculate duration in 0.5 hour increments
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

    // Calculate total booking cost
    private var totalBookingCost: Double? {
        if isGroupBooking {
            guard durationHours > 0 else { return nil }
            let rates = booking.coachRates ?? [:]
            guard !rates.isEmpty else { return nil }
            let totalRate = rates.values.reduce(0, +)
            return totalRate * durationHours
        } else {
            guard let rate = booking.RateUSD, durationHours > 0 else { return nil }
            return rate * durationHours
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Status Header
                    statusSection

                    // Booking Type
                    if isGroupBooking {
                        groupBadge
                    }

                    // Participants Section
                    participantsSection

                    // Date & Time Section
                    dateTimeSection

                    // Location Section
                    if let location = booking.location, !location.isEmpty {
                        locationSection(location)
                    }

                    // Rate & Cost Section
                    rateSection

                    // Notes Section
                    notesSection

                    // Rejection Reason (if applicable)
                    if let reason = booking.rejectionReason, !reason.isEmpty {
                        rejectionSection(reason)
                    }

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Booking Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - View Components

    private var statusSection: some View {
        HStack {
            Text("Status")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(booking.status?.capitalized ?? "Unknown")
                .font(.headline)
                .foregroundColor(statusColor(for: booking.status))
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(UIColor.secondarySystemBackground)))
    }

    private var groupBadge: some View {
        HStack {
            Image(systemName: "person.3.fill")
                .foregroundColor(.blue)
            Text("Group Session")
                .font(.subheadline)
                .foregroundColor(.blue)
            Spacer()
            Text(booking.participantSummary)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.blue.opacity(0.1)))
    }

    private var participantsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Participants")
                .font(.headline)

            // Coach(es)
            VStack(alignment: .leading, spacing: 8) {
                Text(isGroupBooking && booking.allCoachIDs.count > 1 ? "Coaches" : "Coach")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if isGroupBooking && booking.allCoachIDs.count > 1 {
                    ForEach(Array(zip(booking.allCoachIDs, booking.allCoachNames)), id: \.0) { coachId, coachName in
                        HStack {
                            Text(coachName)
                                .font(.body)
                            Spacer()
                            if let acceptances = booking.coachAcceptances {
                                let accepted = acceptances[coachId] ?? false
                                Label(accepted ? "Accepted" : "Pending", systemImage: accepted ? "checkmark.circle.fill" : "clock")
                                    .font(.caption)
                                    .foregroundColor(accepted ? Color("LogoGreen") : .orange)
                            }
                            if let rates = booking.coachRates, let rate = rates[coachId] {
                                Text(String(format: "$%.2f/hr", rate))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } else {
                    Text(coachDisplayName)
                        .font(.body)
                }
            }

            Divider()

            // Client(s)
            VStack(alignment: .leading, spacing: 8) {
                Text(isGroupBooking && booking.allClientIDs.count > 1 ? "Clients" : "Client")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if isGroupBooking && booking.allClientIDs.count > 1 {
                    ForEach(Array(zip(booking.allClientIDs, booking.allClientNames)), id: \.0) { clientId, clientName in
                        HStack {
                            Text(clientName)
                                .font(.body)
                            Spacer()
                            if let confirmations = booking.clientConfirmations {
                                let confirmed = confirmations[clientId] ?? false
                                Label(confirmed ? "Confirmed" : "Pending", systemImage: confirmed ? "checkmark.circle.fill" : "clock")
                                    .font(.caption)
                                    .foregroundColor(confirmed ? Color("LogoGreen") : .orange)
                            }
                        }
                    }
                } else {
                    Text(clientDisplayName)
                        .font(.body)
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(UIColor.secondarySystemBackground)))
    }

    private var dateTimeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Date & Time")
                .font(.headline)

            if let start = booking.startAt {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(.secondary)
                    Text(DateFormatter.localizedString(from: start, dateStyle: .full, timeStyle: .none))
                }
            }

            if let start = booking.startAt, let end = booking.endAt {
                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(.secondary)
                    Text("\(DateFormatter.localizedString(from: start, dateStyle: .none, timeStyle: .short)) - \(DateFormatter.localizedString(from: end, dateStyle: .none, timeStyle: .short))")
                }

                HStack {
                    Image(systemName: "hourglass")
                        .foregroundColor(.secondary)
                    Text("\(durationMinutes) minutes (\(String(format: "%.1f", durationHours)) hours)")
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(UIColor.secondarySystemBackground)))
    }

    private func locationSection(_ location: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Location")
                .font(.headline)

            HStack {
                Image(systemName: "mappin.circle")
                    .foregroundColor(.secondary)
                Text(location)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(UIColor.secondarySystemBackground)))
    }

    private var rateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pricing")
                .font(.headline)

            if isGroupBooking {
                if let rates = booking.coachRates, !rates.isEmpty {
                    ForEach(Array(zip(booking.allCoachIDs, booking.allCoachNames)), id: \.0) { coachId, coachName in
                        if let rate = rates[coachId] {
                            HStack {
                                Text(coachName)
                                    .font(.body)
                                Spacer()
                                Text(String(format: "$%.2f/hr", rate))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } else {
                    Text("Rates pending")
                        .foregroundColor(.orange)
                }
            } else {
                HStack {
                    Text("Hourly Rate")
                    Spacer()
                    if let rate = booking.RateUSD {
                        Text(String(format: "$%.2f", rate))
                    } else {
                        Text("—")
                            .foregroundColor(.secondary)
                    }
                }
            }

            Divider()

            HStack {
                Text("Total Cost")
                    .font(.headline)
                Spacer()
                if let total = totalBookingCost {
                    Text(String(format: "$%.2f", total))
                        .font(.headline)
                        .foregroundColor(Color("LogoGreen"))
                } else {
                    Text("—")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(UIColor.secondarySystemBackground)))
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let notes = booking.notes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notes")
                        .font(.headline)
                    Text(notes)
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }

            if let coachNote = booking.coachNote, !coachNote.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Coach Note")
                        .font(.headline)
                    Text(coachNote)
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(UIColor.secondarySystemBackground)))
    }

    private func rejectionSection(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                Text("Rejection Reason")
                    .font(.headline)
            }
            Text(reason)
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.red.opacity(0.1)))
    }
}

struct BookingDetailView_Previews: PreviewProvider {
    static var previews: some View {
        BookingDetailView(booking: FirestoreManager.BookingItem(
            id: "sample",
            clientID: "c1",
            clientName: "John Doe",
            coachID: "coach1",
            coachName: "Coach Smith",
            startAt: Date(),
            endAt: Date().addingTimeInterval(3600),
            location: "Tennis Court 1",
            notes: "Bring your own racket",
            status: "confirmed",
            paymentStatus: "paid",
            RateUSD: 50.0
        ))
        .environmentObject(FirestoreManager())
        .environmentObject(AuthViewModel())
    }
}
