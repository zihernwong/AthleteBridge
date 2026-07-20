import SwiftUI

struct TournamentDetailView: View {
    let tournament: Tournament
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel

    @State private var calendarAdded: Bool = false
    @State private var isAddingToCalendar: Bool = false
    @State private var showRecommendConfirm: Bool = false
    @State private var showResultAlert: Bool = false
    @State private var resultMessage: String = ""
    @State private var showUpgradeAlert: Bool = false
    @State private var showManageSubscription: Bool = false
    // Names resolved with targeted reads — fetching the global clients/coaches
    // lists from here republishes them and pops this screen off the stack
    @State private var resolvedNames: [String: String] = [:]

    // Web tournament manager integration (per-view store; see WebTournamentStore)
    @StateObject private var webStore = WebTournamentStore()

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }()

    /// Live copy of the tournament so the seeker list refreshes after join/leave.
    private var current: Tournament {
        firestore.tournaments.first(where: { $0.id == tournament.id }) ?? tournament
    }

    private var currentUid: String { auth.user?.uid ?? "" }

    private var isCoach: Bool {
        (firestore.currentUserType ?? "").uppercased() == "COACH"
    }

    private var isOrganizer: Bool {
        firestore.currentAdditionalTypes.contains(AdditionalUserType.tournamentOrganizer.rawValue)
    }

    private var dateRangeText: String {
        "\(Self.dateFormatter.string(from: current.startDate)) – \(Self.dateFormatter.string(from: current.endDate))"
    }

    private var shareText: String {
        var lines = [current.name, dateRangeText, current.location]
        if let link = current.signupLink, !link.isEmpty {
            lines.append("Sign up: \(link)")
        }
        return lines.joined(separator: "\n")
    }

    private var directionsURL: URL? {
        let query = current.location.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://maps.apple.com/?q=\(query)")
    }

    private var partnerSeekers: [(id: String, info: TournamentParticipantInfo)] {
        current.participants
            .map { (id: $0.key, info: $0.value) }
            .sorted { seekerName(for: $0.id) < seekerName(for: $1.id) }
    }

    private func seekerName(for uid: String) -> String {
        if uid == currentUid { return "You" }
        // Ignore placeholder client docs, which are named by their document id
        return resolvedNames[uid]
            ?? firestore.clients.first(where: { $0.id == uid && $0.name != uid })?.name
            ?? firestore.coaches.first(where: { $0.id == uid })?.name
            ?? firestore.participantNames[uid]
            ?? "Player"
    }

    private func resolveMissingNames() {
        for uid in current.participants.keys where uid != currentUid && resolvedNames[uid] == nil {
            firestore.fetchUserDisplayName(uid: uid) { name in
                if let name = name { resolvedNames[uid] = name }
            }
        }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(current.name)
                        .font(.title2)
                        .fontWeight(.semibold)
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(dateRangeText)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(current.location)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section(header: Text("Actions")) {
                if let link = current.signupLink, !link.isEmpty, let url = URL(string: link) {
                    Link(destination: url) {
                        Label("Tournament Signup", systemImage: "link")
                    }
                }

                Button(action: addToCalendar) {
                    HStack {
                        Label(calendarAdded ? "Added to Calendar" : "Add to Calendar", systemImage: calendarAdded ? "checkmark.circle.fill" : "calendar.badge.plus")
                        if isAddingToCalendar {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(calendarAdded || isAddingToCalendar)

                if let url = directionsURL {
                    Link(destination: url) {
                        Label("Directions", systemImage: "car")
                    }
                }

                ShareLink(item: shareText, subject: Text(current.name)) {
                    Label("Share Tournament", systemImage: "square.and.arrow.up")
                }
            }

            Section(header: Text("Partner Search")) {
                if partnerSeekers.isEmpty {
                    Text("No one is looking for a partner yet")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(partnerSeekers, id: \.id) { seeker in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(seekerName(for: seeker.id))
                                .font(.body)
                            HStack(spacing: 6) {
                                if !seeker.info.gender.isEmpty {
                                    Text(seeker.info.gender)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                if !seeker.info.events.isEmpty {
                                    Text("·").foregroundColor(.secondary)
                                    Text(seeker.info.events.joined(separator: ", "))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                if !seeker.info.skillLevels.isEmpty {
                                    Text("·").foregroundColor(.secondary)
                                    Text("Skill: \(seeker.info.skillLevels.sorted().joined(separator: ", "))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                NavigationLink {
                    TournamentPartnerView(initialTournament: current)
                        .environmentObject(firestore)
                        .environmentObject(auth)
                } label: {
                    Label(current.participants.keys.contains(currentUid) ? "Manage Partner Search" : "Find a Partner", systemImage: "person.2")
                        .foregroundColor(Color("LogoBlue"))
                }
            }

            webTournamentSection

            if isCoach {
                Section(header: Text("Coaching")) {
                    let canRecommend = (firestore.currentCoach?.subscriptionTier ?? .free).hasAccess(to: "recommendToClients")
                    Button(action: {
                        if canRecommend {
                            showRecommendConfirm = true
                        } else {
                            showUpgradeAlert = true
                        }
                    }) {
                        HStack {
                            Label("Recommend to My Clients", systemImage: canRecommend ? "megaphone" : "lock.fill")
                                .foregroundColor(canRecommend ? Color("LogoGreen") : .secondary)
                            if !canRecommend {
                                Spacer()
                                Text("Plus / Pro").font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Tournament")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Recommend this tournament?", isPresented: $showRecommendConfirm) {
            Button("Send", role: .none) { recommendToClients() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your clients will get a notification recommending \(current.name).")
        }
        .alert(resultMessage, isPresented: $showResultAlert) {
            Button("OK", role: .cancel) {}
        }
        .alert("Upgrade Required", isPresented: $showUpgradeAlert) {
            Button("Manage Subscription") { showManageSubscription = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Recommending tournaments to your clients is a Coach Plus feature. Upgrade to unlock.")
        }
        .sheet(isPresented: $showManageSubscription) {
            ManageSubscriptionView()
        }
        .onAppear {
            resolveMissingNames()
            syncWebTournament()
        }
        .onChange(of: firestore.tournaments) { _, _ in
            resolveMissingNames()
            syncWebTournament()
        }
        .onChange(of: firestore.currentAdditionalTypes) { _, _ in
            syncWebTournament()
        }
    }

    // MARK: - Web tournament manager

    @ViewBuilder
    private var webTournamentSection: some View {
        if let wt = webStore.webTournament {
            Section(header: Text("Live Results")) {
                HStack(spacing: 8) {
                    Text(wt.isComplete ? "Complete" : wt.status == "active" ? "Live" : "Setting Up")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background((wt.isComplete ? Color("LogoGreen") : wt.status == "active" ? .red : .secondary).opacity(0.15))
                        .foregroundColor(wt.isComplete ? Color("LogoGreen") : wt.status == "active" ? .red : .secondary)
                        .cornerRadius(10)
                    if !wt.events.isEmpty {
                        Text("\(wt.events.count) event\(wt.events.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }

                ForEach(wt.events.filter { wt.eventData[$0]?.status == "complete" }, id: \.self) { ev in
                    if let champ = wt.eventData[ev]?.playerName(wt.eventData[ev]?.champion) {
                        HStack {
                            Text(WebTournamentEvents.displayName(ev))
                                .font(.subheadline)
                            Spacer()
                            Label(champ, systemImage: "crown.fill")
                                .font(.subheadline)
                                .foregroundColor(.orange)
                        }
                    }
                }

                NavigationLink {
                    WebBracketView(store: webStore, isOrganizer: isOrganizer)
                } label: {
                    Label("Bracket & Results", systemImage: "list.bullet.indent")
                        .foregroundColor(Color("LogoBlue"))
                }

                if !wt.isComplete, let reg = wt.registerURL {
                    Link(destination: reg) {
                        Label("Register on Tournament Manager", systemImage: "person.crop.circle.badge.plus")
                    }
                }

                if let url = wt.webURL {
                    Link(destination: url) {
                        Label("Open Tournament Manager", systemImage: "safari")
                    }
                }

                if isOrganizer {
                    Button(role: .destructive) {
                        webStore.unlink(appTournamentId: current.id) { _ in
                            firestore.fetchTournaments()
                            webStore.fetchSuggestions(for: current)
                        }
                    } label: {
                        Label("Unlink Web Tournament", systemImage: "link.badge.plus")
                    }
                }
            }
        } else if current.webTournamentId != nil {
            Section(header: Text("Live Results")) {
                HStack {
                    ProgressView()
                    Text("Loading tournament manager data…")
                        .foregroundColor(.secondary)
                }
            }
        } else if isOrganizer {
            Section(header: Text("Tournament Manager"), footer: Text("Link this tournament to the web tournament manager to run brackets and show live results in the app.")) {
                ForEach(webStore.suggestions) { suggestion in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.name)
                                .font(.subheadline)
                                .lineLimit(1)
                            Text([suggestion.date, suggestion.location].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Link") {
                            webStore.link(appTournamentId: current.id, webId: suggestion.id) { err in
                                if err == nil {
                                    webStore.listen(webId: suggestion.id)
                                    firestore.fetchTournaments()
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color("LogoBlue"))
                    }
                }

                Button {
                    webStore.createWebTournament(from: current) { webId in
                        if webId != nil {
                            firestore.fetchTournaments()
                        } else {
                            resultMessage = "Couldn't create the web tournament."
                            showResultAlert = true
                        }
                    }
                } label: {
                    HStack {
                        Label("Create on Tournament Manager", systemImage: "plus.rectangle.on.rectangle")
                            .foregroundColor(Color("LogoGreen"))
                        if webStore.isWorking {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(webStore.isWorking)
            }
        }
    }

    private func syncWebTournament() {
        if let webId = current.webTournamentId {
            if webStore.webTournament?.id != webId {
                webStore.listen(webId: webId)
            }
        } else if isOrganizer && webStore.webTournament == nil && webStore.suggestions.isEmpty {
            webStore.fetchSuggestions(for: current)
        }
    }

    private func addToCalendar() {
        isAddingToCalendar = true
        firestore.addTournamentToAppleCalendar(current) { result in
            DispatchQueue.main.async {
                isAddingToCalendar = false
                switch result {
                case .success:
                    calendarAdded = true
                case .failure(let err):
                    resultMessage = "Couldn't add to calendar: \(err.localizedDescription)"
                    showResultAlert = true
                }
            }
        }
    }

    private func recommendToClients() {
        firestore.recommendTournamentToClients(current) { count in
            DispatchQueue.main.async {
                resultMessage = count > 0
                    ? "Recommended \(current.name) to \(count) client\(count == 1 ? "" : "s")."
                    : "No clients found to notify yet — clients appear here once they book with you."
                showResultAlert = true
            }
        }
    }
}
