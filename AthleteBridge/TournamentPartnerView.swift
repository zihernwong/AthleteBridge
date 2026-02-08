import SwiftUI

struct TournamentPartnerView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel
    @State private var tournamentFilter: String = ""
    @State private var selectedTournament: Tournament? = nil
    @State private var presentedChat: ChatSheetId? = nil
    @State private var showTournamentInput: Bool = false

    // Partner search preferences
    @State private var selectedGender: String = "Male"
    @State private var selectedEvents: Set<String> = []
    @State private var selectedSkillLevels: Set<String> = []

    private let genderOptions = ["Male", "Female"]
    private let eventOptions = ["Men's Doubles", "Women's Doubles", "Mixed Doubles"]
    private let skillLevelOptions = ["A", "B", "C", "D"]

    private struct ChatSheetId: Identifiable { let id: String }

    private var tournamentSuggestions: [Tournament] {
        let typed = tournamentFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard typed.count >= 1 else { return [] }
        return firestore.tournaments.filter { $0.name.lowercased().contains(typed) }
    }

    private var currentUid: String { auth.user?.uid ?? "" }

    private var isParticipant: Bool {
        guard let t = selectedTournament else { return false }
        return t.participants.keys.contains(currentUid)
    }

    private var partners: [FirestoreManager.UserSummary] {
        guard let tournament = selectedTournament else { return [] }
        let participantIds = Set(tournament.participants.keys).subtracting([currentUid])
        let myGender = selectedGender
        let myEvents = selectedEvents
        return firestore.clients.filter { client in
            guard participantIds.contains(client.id),
                  let info = tournament.participants[client.id] else { return false }
            let partnerGender = info.gender
            // Check if at least one overlapping event passes the gender rules
            let sharedEvents = myEvents.intersection(info.events)
            if sharedEvents.isEmpty { return false }
            for event in sharedEvents {
                switch event {
                case "Men's Doubles":
                    // Both must be Male
                    if myGender == "Male" && partnerGender == "Male" { return true }
                case "Women's Doubles":
                    // Both must be Female
                    if myGender == "Female" && partnerGender == "Female" { return true }
                case "Mixed Doubles":
                    // Must be opposite genders
                    if myGender != partnerGender { return true }
                default:
                    return true
                }
            }
            return false
        }
    }

    private var canJoin: Bool {
        !selectedEvents.isEmpty &&
        !selectedSkillLevels.isEmpty
    }

    var body: some View {
        Form {
            Section(header: Text("Tournament")) {
                VStack(spacing: 6) {
                    TextField("Search by tournament name", text: $tournamentFilter)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: tournamentFilter) { _, newValue in
                            if let selected = selectedTournament, newValue.lowercased() != selected.name.lowercased() {
                                selectedTournament = nil
                            }
                        }

                    if selectedTournament == nil && !tournamentSuggestions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(tournamentSuggestions) { t in
                                    Button(action: {
                                        tournamentFilter = t.name
                                        selectedTournament = t
                                        // Pre-fill fields if already a participant
                                        if let info = t.participants[currentUid] {
                                            selectedGender = info.gender.isEmpty ? "Male" : info.gender
                                            selectedEvents = Set(info.events)
                                            selectedSkillLevels = Set(info.skillLevels)
                                        }
                                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                    }) {
                                        Text(t.name)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(Color(UIColor.secondarySystemBackground))
                                            .cornerRadius(16)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Button(action: {
                    showTournamentInput = true
                }) {
                    Label("Input Tournament Info", systemImage: "plus.circle.fill")
                }
            }

            if let tournament = selectedTournament {
                Section(header: Text("Looking for a Partner")) {
                    VStack(alignment: .leading) {
                        Text("Your Gender").font(.subheadline).foregroundColor(.secondary)
                        Picker("Your Gender", selection: $selectedGender) {
                            ForEach(genderOptions, id: \.self) { Text($0) }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }

                    VStack(alignment: .leading) {
                        Text("Event").font(.subheadline).foregroundColor(.secondary)
                        AvailabilityChipSelect(items: eventOptions, selection: $selectedEvents)
                    }

                    VStack(alignment: .leading) {
                        Text("Desired Skill Level").font(.subheadline).foregroundColor(.secondary)
                        AvailabilityChipSelect(items: skillLevelOptions, selection: $selectedSkillLevels)
                    }

                    if isParticipant {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Color("LogoGreen"))
                            Text("You are looking for a partner")
                                .foregroundColor(.secondary)
                        }

                        Button(action: {
                            firestore.joinTournament(
                                tournamentId: tournament.id,
                                gender: selectedGender,
                                events: Array(selectedEvents),
                                skillLevels: Array(selectedSkillLevels)
                            ) { _ in
                                DispatchQueue.main.async {
                                    selectedTournament = firestore.tournaments.first(where: { $0.id == tournament.id })
                                }
                            }
                        }) {
                            Text("Update Preferences")
                        }
                        .disabled(!canJoin)

                        Button(role: .destructive, action: {
                            firestore.leaveTournament(tournamentId: tournament.id) { _ in
                                DispatchQueue.main.async {
                                    selectedTournament = firestore.tournaments.first(where: { $0.id == tournament.id })
                                }
                            }
                        }) {
                            Text("Leave Partner Search")
                        }
                    } else {
                        Button(action: {
                            firestore.joinTournament(
                                tournamentId: tournament.id,
                                gender: selectedGender,
                                events: Array(selectedEvents),
                                skillLevels: Array(selectedSkillLevels)
                            ) { _ in
                                DispatchQueue.main.async {
                                    selectedTournament = firestore.tournaments.first(where: { $0.id == tournament.id })
                                }
                            }
                        }) {
                            Label("I'm Looking for a Partner", systemImage: "person.badge.plus")
                        }
                        .tint(Color("LogoGreen"))
                        .disabled(!canJoin)
                    }
                }

                Section(header: Text("Partners Looking to Play")) {
                    if partners.isEmpty {
                        Text("No one else is looking for a partner yet").foregroundColor(.secondary)
                    } else {
                        ForEach(partners) { partner in
                            let info = tournament.participants[partner.id]
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 12) {
                                    AvatarView(url: partner.photoURL, name: partner.name, size: 44, useCurrentUser: false)
                                        .environmentObject(firestore)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(partner.name).font(.body)
                                        if let info = info {
                                            HStack(spacing: 6) {
                                                if !info.gender.isEmpty {
                                                    Text(info.gender)
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                                if !info.events.isEmpty {
                                                    Text("·").foregroundColor(.secondary)
                                                    Text(info.events.joined(separator: ", "))
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                            if !info.skillLevels.isEmpty {
                                                Text("Skill: \(info.skillLevels.sorted().joined(separator: ", "))")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        if let link = partner.tournamentSoftwareLink, !link.isEmpty, let url = URL(string: link) {
                                            Link(destination: url) {
                                                Label("Match History", systemImage: "trophy")
                                                    .font(.caption)
                                            }
                                        }
                                    }

                                    Spacer()

                                    Button(action: {
                                        guard let uid = auth.user?.uid else { return }
                                        let chatId = [uid, partner.id].sorted().joined(separator: "_")
                                        presentedChat = ChatSheetId(id: chatId)
                                        firestore.createOrGetChat(withCoachId: partner.id) { resolved in
                                            if let resolved = resolved, resolved != chatId {
                                                DispatchQueue.main.async {
                                                    presentedChat = ChatSheetId(id: resolved)
                                                }
                                            }
                                        }
                                    }) {
                                        Image(systemName: "message.fill")
                                            .foregroundColor(.accentColor)
                                    }
                                    .buttonStyle(BorderlessButtonStyle())
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .navigationTitle("Find a Tournament Partner")
        .sheet(item: $presentedChat) { sheet in
            NavigationStack {
                ChatView(chatId: sheet.id)
                    .environmentObject(firestore)
            }
        }
        .sheet(isPresented: $showTournamentInput) {
            TournamentInputView()
                .environmentObject(firestore)
        }
        .onAppear {
            firestore.fetchClients()
            firestore.fetchTournaments()
        }
        .onChange(of: firestore.tournaments) { _, updated in
            if let selected = selectedTournament {
                selectedTournament = updated.first(where: { $0.id == selected.id })
            }
        }
    }
}

struct TournamentInputView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @Environment(\.dismiss) private var dismiss
    @State private var tournamentName: String = ""
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var tournamentLocation: String = ""
    @State private var signupLink: String = ""
    @State private var isSaving: Bool = false

    private var isValid: Bool {
        !tournamentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !tournamentLocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        endDate >= startDate
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Tournament Details")) {
                    TextField("Tournament Name", text: $tournamentName)
                    DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                        .onChange(of: startDate) { _, newStart in
                            if endDate < newStart {
                                endDate = Calendar.current.date(byAdding: .day, value: 1, to: newStart) ?? newStart
                            }
                        }
                    DatePicker("End Date", selection: $endDate, in: startDate..., displayedComponents: .date)
                    TextField("Tournament Location", text: $tournamentLocation)
                }
                Section(header: Text("Optional")) {
                    TextField("Tournament Signup Link", text: $signupLink)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                }
            }
            .navigationTitle("New Tournament")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        isSaving = true
                        let trimmedLink = signupLink.trimmingCharacters(in: .whitespacesAndNewlines)
                        firestore.createTournament(
                            name: tournamentName.trimmingCharacters(in: .whitespacesAndNewlines),
                            startDate: startDate,
                            endDate: endDate,
                            location: tournamentLocation.trimmingCharacters(in: .whitespacesAndNewlines),
                            signupLink: trimmedLink.isEmpty ? nil : trimmedLink
                        ) { err in
                            DispatchQueue.main.async {
                                isSaving = false
                                if err == nil {
                                    dismiss()
                                }
                            }
                        }
                    }
                    .disabled(!isValid || isSaving)
                }
            }
        }
    }
}
