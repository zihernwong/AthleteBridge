import SwiftUI

// MARK: - Coach Summary Model

private struct CoachSummary: Identifiable {
    let id: String          // coachID
    let name: String
    let totalSessions: Int
    let lastSessionDate: Date?
}

// MARK: - ClientCoachRosterView

struct ClientCoachRosterView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel

    @State private var searchText: String = ""
    @State private var isCreatingChat: Bool = false
    @State private var chatToOpen: String? = nil

    // Aggregate unique coaches from bookings
    private var allCoaches: [CoachSummary] {
        guard let myUID = auth.user?.uid else { return [] }
        var map: [String: (name: String, sessions: Int, lastDate: Date?)] = [:]

        for booking in firestore.bookings {
            let coachId = booking.coachID
            guard !coachId.isEmpty, coachId != myUID else { continue }
            let coachName = booking.coachName ?? coachId
            var entry = map[coachId] ?? (name: coachName, sessions: 0, lastDate: nil)
            entry.sessions += 1
            if let start = booking.startAt {
                if entry.lastDate == nil || start > entry.lastDate! { entry.lastDate = start }
            }
            if entry.name.isEmpty || entry.name == coachId { entry.name = coachName }
            map[coachId] = entry
        }

        return map.map { (id, val) in
            CoachSummary(id: id, name: val.name, totalSessions: val.sessions, lastSessionDate: val.lastDate)
        }
        .sorted { ($0.lastSessionDate ?? .distantPast) > ($1.lastSessionDate ?? .distantPast) }
    }

    private var filteredCoaches: [CoachSummary] {
        if searchText.isEmpty { return allCoaches }
        return allCoaches.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        Group {
            if allCoaches.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "person.2")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No coaches present within the last 7 days")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Spacer()
                }
            } else {
                List {
                    ForEach(filteredCoaches) { coach in
                        NavigationLink(destination: ClientCoachDetailView(coachId: coach.id, coachName: coach.name)
                            .environmentObject(firestore)
                            .environmentObject(auth)
                        ) {
                            CoachRosterRow(coach: coach, onMessage: {
                                messageCoach(coachId: coach.id)
                            })
                            .environmentObject(firestore)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .searchable(text: $searchText, prompt: "Search coaches")
            }
        }
        .navigationTitle("My Coaches")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $chatToOpen) { chatId in
            ChatView(chatId: chatId)
                .environmentObject(firestore)
                .environmentObject(auth)
        }
        .overlay {
            if isCreatingChat {
                Color.black.opacity(0.2).ignoresSafeArea()
                ProgressView("Opening chat...")
                    .padding()
                    .background(.regularMaterial)
                    .cornerRadius(12)
            }
        }
        .onAppear {
            // Always fetch regardless of whether the list is currently empty
            firestore.fetchBookingsForCurrentClientSubcollection()
        }
    }

    private func messageCoach(coachId: String) {
        isCreatingChat = true
        firestore.createOrGetChat(withCoachId: coachId) { chatId in
            DispatchQueue.main.async {
                self.isCreatingChat = false
                if let cid = chatId {
                    self.chatToOpen = cid
                }
            }
        }
    }
}

// MARK: - Coach Roster Row

private struct CoachRosterRow: View {
    let coach: CoachSummary
    let onMessage: () -> Void
    @EnvironmentObject var firestore: FirestoreManager

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(url: resolvedPhotoURL, size: 44, useCurrentUser: false)

            VStack(alignment: .leading, spacing: 3) {
                Text(coach.name)
                    .font(.headline)
                HStack(spacing: 6) {
                    Text("\(coach.totalSessions) session\(coach.totalSessions == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let date = coach.lastSessionDate {
                        Text("·")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(relativeDateString(date))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            Button {
                onMessage()
            } label: {
                Image(systemName: "message.fill")
                    .foregroundColor(Color("LogoBlue"))
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .onTapGesture { onMessage() }
        }
        .padding(.vertical, 4)
    }

    private var resolvedPhotoURL: URL? {
        (firestore.coachPhotoURLs[coach.id] ?? nil) ?? (firestore.clientPhotoURLs[coach.id] ?? nil)
    }

    private func relativeDateString(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days == 0 { return "today" }
        if days == 1 { return "yesterday" }
        if days < 7 { return "\(days)d ago" }
        if days < 30 { return "\(days / 7)w ago" }
        return DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .none)
    }
}

// MARK: - Client Coach Detail View

struct ClientCoachDetailView: View {
    let coachId: String
    let coachName: String
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel

    private var coachBookings: [FirestoreManager.BookingItem] {
        firestore.bookings
            .filter { $0.coachID == coachId }
            .sorted { ($0.startAt ?? .distantPast) > ($1.startAt ?? .distantPast) }
    }

    private var coachSessionLogs: [FirestoreManager.SessionLog] {
        firestore.clientSessionLogs.filter { $0.coachID == coachId }
    }

    var body: some View {
        List {
            // Metric progress across all logged sessions with this coach
            MetricProgressSection(logs: coachSessionLogs)

            // Session logs written by the coach (read-only for the client)
            if !coachSessionLogs.isEmpty {
                Section(header: Text("Session Logs")) {
                    ForEach(coachSessionLogs) { log in
                        SessionLogCard(log: log)
                    }
                }
            }

            Section(header: Text("Bookings")) {
                if coachBookings.isEmpty {
                    Text("No bookings found")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(coachBookings) { booking in
                        NavigationLink(destination: BookingDetailView(booking: booking)
                            .environmentObject(firestore)
                            .environmentObject(auth)
                        ) {
                            ClientBookingRow(booking: booking)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(coachName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let uid = auth.user?.uid {
                firestore.listenSessionLogsForClient(clientId: uid)
            }
        }
    }
}

private struct ClientBookingRow: View {
    let booking: FirestoreManager.BookingItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let start = booking.startAt {
                    Text(DateFormatter.localizedString(from: start, dateStyle: .medium, timeStyle: .short))
                        .font(.subheadline)
                } else {
                    Text("Date TBD")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text((booking.status ?? "Unknown").replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption)
                    .foregroundColor(statusColor)
            }
            if let location = booking.location, !location.isEmpty {
                Text(location)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if let rate = booking.RateUSD {
                Text(String(format: "$%.2f/hr", rate))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var statusColor: Color {
        switch (booking.status ?? "").lowercased() {
        case "confirmed": return Color("LogoGreen")
        case "requested": return Color("LogoBlue")
        case "pending acceptance", "pending_payment", "payment_submitted": return .orange
        case "rejected", "declined", "cancelled": return .red
        default: return .secondary
        }
    }
}

struct ClientCoachRosterView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ClientCoachRosterView()
                .environmentObject(FirestoreManager())
                .environmentObject(AuthViewModel())
        }
    }
}
