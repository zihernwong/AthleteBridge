import SwiftUI
import FirebaseAuth

struct PlayersToPlayWithView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel

    private struct ChatSheetId: Identifiable { let id: String }
    @State private var presentedChat: ChatSheetId? = nil
    @State private var isPosting = false
    @State private var showEditSheet = false

    private var currentUid: String { auth.user?.uid ?? "" }

    private var myPosting: PlayerToPlayWith? {
        firestore.playersToPlayWith.first(where: { $0.id == currentUid })
    }

    var body: some View {
        List {
            if firestore.playersToPlayWith.isEmpty {
                Text("No players yet. Be the first to post!")
                    .foregroundColor(.secondary)
            } else {
                ForEach(firestore.playersToPlayWith) { player in
                    PlayerRow(
                        player: player,
                        currentUid: currentUid,
                        venues: firestore.placesToPlay,
                        onMessage: { openChat(withUid: player.id) }
                    )
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let player = firestore.playersToPlayWith[index]
                        if player.id == currentUid {
                            firestore.deletePlayerToPlayWith()
                        }
                    }
                }
            }
        }
        .navigationTitle("Players to Play With")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if myPosting != nil {
                    Button(action: { showEditSheet = true }) {
                        Image(systemName: "pencil.circle")
                    }
                } else {
                    Button(action: postSelf) {
                        if isPosting {
                            ProgressView()
                        } else {
                            Image(systemName: "plus")
                        }
                    }
                    .disabled(isPosting)
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            if let player = myPosting {
                EditPlayerProfileSheet(player: player)
                    .environmentObject(firestore)
            }
        }
        .sheet(item: $presentedChat) { sheet in
            NavigationStack {
                ChatView(chatId: sheet.id)
                    .environmentObject(firestore)
            }
        }
        .onAppear {
            firestore.fetchPlayersToPlayWith()
            if firestore.placesToPlay.isEmpty {
                firestore.fetchPlacesToPlay()
            }
        }
    }

    private func postSelf() {
        isPosting = true
        firestore.addPlayerToPlayWith { _ in
            DispatchQueue.main.async {
                isPosting = false
            }
        }
    }

    private func openChat(withUid otherUid: String) {
        guard !currentUid.isEmpty else {
            firestore.showToast("Please sign in to message")
            return
        }
        let expectedChatId = [currentUid, otherUid].sorted().joined(separator: "_")
        presentedChat = ChatSheetId(id: expectedChatId)
        firestore.createOrGetChat(withCoachId: otherUid) { chatId in
            DispatchQueue.main.async {
                let target = chatId ?? expectedChatId
                if target != expectedChatId {
                    presentedChat = ChatSheetId(id: target)
                }
            }
        }
    }
}

// MARK: - Player Row

private struct PlayerRow: View {
    let player: PlayerToPlayWith
    let currentUid: String
    let venues: [PlaceToPlay]
    let onMessage: () -> Void

    private var connectedVenueNames: [String] {
        player.connectedVenueIds.compactMap { vid in
            venues.first(where: { $0.id == vid })?.name
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(player.name)
                    .font(.headline)
                Spacer()
                if !player.skillLevel.isEmpty {
                    Text(player.skillLevel)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color("LogoGreen").opacity(0.15))
                        .foregroundColor(Color("LogoGreen"))
                        .cornerRadius(6)
                }
            }

            if !player.city.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text(player.city)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            if !player.availability.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    ForEach(player.availability, id: \.self) { slot in
                        Text(slot)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color("LogoBlue").opacity(0.1))
                            .foregroundColor(Color("LogoBlue"))
                            .cornerRadius(4)
                    }
                }
            }

            if !connectedVenueNames.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "building.2")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text(connectedVenueNames.joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            if player.id != currentUid {
                HStack(spacing: 8) {
                    Spacer()
                    Button(action: onMessage) {
                        HStack(spacing: 4) {
                            Image(systemName: "message.fill")
                            Text("Message")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(Color("LogoBlue"))
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Edit Player Profile Sheet

private struct EditPlayerProfileSheet: View {
    @EnvironmentObject var firestore: FirestoreManager
    @Environment(\.dismiss) private var dismiss
    let player: PlayerToPlayWith

    @State private var skillLevel: String = ""
    @State private var city: String = ""
    @State private var selectedAvailability: Set<String> = []
    @State private var selectedVenueIds: Set<String> = []
    @State private var isSaving = false

    private let skillLevels = ["Beginner", "Intermediate", "Advanced", "Professional"]
    private let availabilityOptions = ["Morning", "Afternoon", "Evening", "Weekend"]

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Skill Level")) {
                    Picker("Skill Level", selection: $skillLevel) {
                        Text("Not Set").tag("")
                        ForEach(skillLevels, id: \.self) { level in
                            Text(level).tag(level)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section(header: Text("City")) {
                    TextField("City", text: $city)
                }

                Section(header: Text("Availability")) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
                        ForEach(availabilityOptions, id: \.self) { option in
                            let isSelected = selectedAvailability.contains(option)
                            Button(action: {
                                if isSelected {
                                    selectedAvailability.remove(option)
                                } else {
                                    selectedAvailability.insert(option)
                                }
                            }) {
                                Text(option)
                                    .font(.callout)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(isSelected ? Color("LogoGreen") : Color(UIColor.secondarySystemBackground))
                                    )
                                    .foregroundColor(isSelected ? .white : .primary)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }

                Section(header: Text("Connected Venues")) {
                    if firestore.placesToPlay.isEmpty {
                        Text("No venues available yet.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(firestore.placesToPlay) { place in
                            let isSelected = selectedVenueIds.contains(place.id)
                            Button(action: {
                                if isSelected {
                                    selectedVenueIds.remove(place.id)
                                } else {
                                    selectedVenueIds.insert(place.id)
                                }
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(place.name)
                                            .font(.subheadline)
                                            .foregroundColor(.primary)
                                        if !place.address.isEmpty {
                                            Text(place.address)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(Color("LogoGreen"))
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }

                Section {
                    Button(role: .destructive, action: {
                        firestore.deletePlayerToPlayWith()
                        dismiss()
                    }) {
                        HStack {
                            Spacer()
                            Text("Remove My Listing")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Edit Player Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(isSaving)
                }
            }
            .onAppear {
                skillLevel = player.skillLevel
                city = player.city
                selectedAvailability = Set(player.availability)
                selectedVenueIds = Set(player.connectedVenueIds)
                if firestore.placesToPlay.isEmpty {
                    firestore.fetchPlacesToPlay()
                }
            }
        }
    }

    private func save() {
        isSaving = true
        firestore.updatePlayerToPlayWith(
            skillLevel: skillLevel,
            city: city.trimmingCharacters(in: .whitespacesAndNewlines),
            availability: availabilityOptions.filter { selectedAvailability.contains($0) },
            connectedVenueIds: Array(selectedVenueIds)
        ) { _ in
            DispatchQueue.main.async {
                isSaving = false
                dismiss()
            }
        }
    }
}
