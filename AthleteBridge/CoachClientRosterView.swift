import SwiftUI

// MARK: - Client Summary Model

private struct ClientSummary: Identifiable {
    let id: String             // clientID
    let name: String
    let photoURL: String?
    let totalSessions: Int
    let totalPaid: Double      // sum of price for confirmed bookings
    let lastSessionDate: Date?
}

// MARK: - CoachClientRosterView

struct CoachClientRosterView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel

    @State private var searchText: String = ""
    @State private var isCreatingChat: Bool = false
    @State private var chatToOpen: String? = nil

    // Aggregate unique clients from coachBookings
    private var allClients: [ClientSummary] {
        guard let myUID = auth.user?.uid else { return [] }
        var map: [String: (name: String, photoURL: String?, sessions: Int, paid: Double, lastDate: Date?)] = [:]

        for booking in firestore.coachBookings {
            // Collect all client IDs from this booking (single or group)
            var clientIds: [(id: String, name: String)] = []
            if !booking.clientID.isEmpty {
                clientIds.append((booking.clientID, booking.clientName ?? booking.clientID))
            }
            if let ids = booking.clientIDs, let names = booking.clientNames {
                for (id, name) in zip(ids, names) where !id.isEmpty && id != booking.clientID {
                    clientIds.append((id, name))
                }
            }

            let isConfirmed = (booking.status ?? "").lowercased() == "confirmed"
            let sessionPrice = booking.RateUSD ?? 0.0

            for (clientId, clientName) in clientIds {
                if clientId == myUID { continue }  // skip self
                var entry = map[clientId] ?? (name: clientName, photoURL: nil, sessions: 0, paid: 0.0, lastDate: nil)
                entry.sessions += 1
                if isConfirmed { entry.paid += sessionPrice }
                if let start = booking.startAt {
                    if entry.lastDate == nil || start > entry.lastDate! { entry.lastDate = start }
                }
                // Prefer a non-empty name
                if entry.name.isEmpty || entry.name == clientId { entry.name = clientName }
                map[clientId] = entry
            }
        }

        return map.map { (id, val) in
            ClientSummary(id: id, name: val.name, photoURL: val.photoURL,
                          totalSessions: val.sessions, totalPaid: val.paid,
                          lastSessionDate: val.lastDate)
        }
        .sorted { ($0.lastSessionDate ?? .distantPast) > ($1.lastSessionDate ?? .distantPast) }
    }

    private var filteredClients: [ClientSummary] {
        if searchText.isEmpty { return allClients }
        return allClients.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        Group {
            if allClients.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "person.2")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No clients present within the last 7 days")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Spacer()
                }
            } else {
                List {
                    ForEach(filteredClients) { client in
                        NavigationLink(destination: CoachClientDetailView(clientId: client.id, clientName: client.name)
                            .environmentObject(firestore)
                            .environmentObject(auth)
                        ) {
                            ClientRosterRow(client: client, onMessage: {
                                messageClient(clientId: client.id)
                            })
                            .environmentObject(firestore)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .searchable(text: $searchText, prompt: "Search clients")
            }
        }
        .navigationTitle("My Clients")
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
            firestore.fetchBookingsForCurrentCoachSubcollection()
            if !allClients.isEmpty {
                firestore.fetchLastSeen(for: allClients.map { $0.id })
            }
        }
    }

    private func messageClient(clientId: String) {
        isCreatingChat = true
        // createOrGetChat sorts both UIDs to form a deterministic chat ID, so passing
        // clientId here produces the same result as the client calling it with the coachId.
        firestore.createOrGetChat(withCoachId: clientId) { chatId in
            DispatchQueue.main.async {
                self.isCreatingChat = false
                if let cid = chatId {
                    self.chatToOpen = cid
                }
            }
        }
    }
}

// MARK: - Client Roster Row

private struct ClientRosterRow: View {
    let client: ClientSummary
    let onMessage: () -> Void
    @EnvironmentObject var firestore: FirestoreManager

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            AvatarView(url: resolvedPhotoURL, size: 44, useCurrentUser: false)

            VStack(alignment: .leading, spacing: 3) {
                Text(client.name)
                    .font(.headline)
                HStack(spacing: 6) {
                    Text("\(client.totalSessions) session\(client.totalSessions == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if client.totalPaid > 0 {
                        Text("·")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(String(format: "$%.0f", client.totalPaid))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if let date = client.lastSessionDate {
                        Text("·")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(relativeDateString(date))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                presenceView
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
        (firestore.clientPhotoURLs[client.id] ?? nil) ?? (firestore.coachPhotoURLs[client.id] ?? nil)
    }

    @ViewBuilder
    private var presenceView: some View {
        if let lastSeen = firestore.clientLastSeen[client.id] {
            let secondsAgo = Date().timeIntervalSince(lastSeen)
            if secondsAgo < 300 {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)
                    Text("Online")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            } else {
                Text("Last seen \(lastSeenString(lastSeen))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func lastSeenString(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        if seconds < 86400 { return "\(seconds / 3600)h ago" }
        let days = seconds / 86400
        if days == 1 { return "yesterday" }
        if days < 7 { return "\(days)d ago" }
        return DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .none)
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

// MARK: - Coach Client Detail View

struct CoachClientDetailView: View {
    let clientId: String
    let clientName: String
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel

    private var clientBookings: [FirestoreManager.BookingItem] {
        firestore.coachBookings
            .filter { $0.clientID == clientId || ($0.clientIDs?.contains(clientId) ?? false) }
            .sorted { ($0.startAt ?? .distantPast) > ($1.startAt ?? .distantPast) }
    }

    private var clientSessionLogs: [FirestoreManager.SessionLog] {
        firestore.coachSessionLogs.filter { $0.clientID == clientId }
    }

    var body: some View {
        List {
            // Metric progress across all logged sessions (e.g. 8:00 → 7:45 → 7:30)
            MetricProgressSection(logs: clientSessionLogs)

            // Session logs — tap to edit
            if !clientSessionLogs.isEmpty {
                Section(header: Text("Session Logs")) {
                    ForEach(clientSessionLogs) { log in
                        if let booking = clientBookings.first(where: { $0.id == log.id }) {
                            NavigationLink {
                                SessionLogEditorView(booking: booking)
                                    .environmentObject(firestore)
                            } label: {
                                SessionLogCard(log: log)
                            }
                        } else {
                            SessionLogCard(log: log)
                        }
                    }
                }
            }

            Section(header: Text("Bookings")) {
                if clientBookings.isEmpty {
                    Text("No bookings found")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(clientBookings) { booking in
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
        .navigationTitle(clientName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let uid = auth.user?.uid {
                firestore.listenSessionLogsForCoach(coachId: uid)
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

struct CoachClientRosterView_Previews: PreviewProvider {
    static var previews: some View {
        CoachClientRosterView()
            .environmentObject(FirestoreManager())
            .environmentObject(AuthViewModel())
    }
}
