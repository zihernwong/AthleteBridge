import SwiftUI

struct MessagesView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel
    @State private var showingNewConversation = false
    @State private var navPath = NavigationPath()
    @State private var newConvSearch: String = ""
    @State private var isCreatingChat: Bool = false
    @State private var lastKnownChatIds: [String] = []
    @State private var refreshTask: Task<Void, Never>? = nil

    var body: some View {
        NavigationStack(path: $navPath) {
            mainContent
                .navigationTitle("Messages")
                .toolbar { toolbarContent }
                .onAppear(perform: handleOnAppear)
                .onDisappear { refreshTask?.cancel() }
                .onChange(of: firestore.userTypeLoaded) { _, loaded in
                    if loaded { firestore.listenForChatsForCurrentUser() }
                }
                .onChange(of: firestore.chats.count) { _, _ in handleChatsCountChange() }
                .onChange(of: firestore.chats) { _, _ in refreshUIDNames() }
                .navigationDestination(for: String.self) { chatId in
                    ChatView(chatId: chatId).environmentObject(firestore)
                }
                .sheet(isPresented: $showingNewConversation) { newConversationSheet }
        }
    }

    // MARK: - Extracted Views

    @ViewBuilder
    private var mainContent: some View {
        if firestore.chats.isEmpty {
            emptyStateView
        } else {
            chatListView
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 18) {
            Spacer()
            Text("No messages, start a conversation today!")
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 32)

            Button(action: { showingNewConversation = true }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("New Conversation")
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor))
                .foregroundColor(.white)
            }

            Spacer()
        }
    }

    private var chatListView: some View {
        List {
            ForEach(firestore.chats) { chat in
                NavigationLink(value: chat.id) {
                    ChatRow(chat: chat)
                        .environmentObject(firestore)
                        .environmentObject(auth)
                }
            }
        }
        .refreshable {
            firestore.listenForChatsForCurrentUser()
            firestore.refreshAllParticipantNames()
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button(action: { showingNewConversation = true }) {
                let isCoach = (firestore.currentUserType ?? "CLIENT").trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "COACH"
                Text(isCoach ? "Message Clients" : "Message Nearby Coaches")
            }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Button(action: { showingNewConversation = true }) {
                Image(systemName: "plus")
            }
        }
    }

    private var newConversationSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchHeader
                conversationList
                if isCreatingChat {
                    ProgressView("Creating chat...").padding()
                }
            }
            .navigationTitle("New Conversation")
        }
        .onAppear {
            firestore.fetchCoaches()
            firestore.fetchClients()
        }
    }

    private var searchHeader: some View {
        HStack {
            TextField("Search", text: $newConvSearch)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            Button("Close") { showingNewConversation = false }
        }
        .padding()
    }

    @ViewBuilder
    private var conversationList: some View {
        let roleIsClient = (firestore.currentUserType ?? "CLIENT").uppercased() != "COACH"
        if roleIsClient {
            coachList
        } else {
            clientList
        }
    }

    private var coachList: some View {
        List {
            ForEach(filteredCoaches) { coach in
                Button(action: { createAndOpenChat(with: coach.id) }) {
                    HStack {
                        AvatarView(url: firestore.coachPhotoURLs[coach.id] ?? nil, size: 36, useCurrentUser: false)
                        Text(coach.name)
                        Spacer()
                    }
                }
            }
        }
    }

    private var clientList: some View {
        List {
            ForEach(filteredClients) { client in
                Button(action: { createAndOpenChat(with: client.id) }) {
                    HStack {
                        AvatarView(url: client.photoURL, size: 36, useCurrentUser: false)
                        Text(client.name)
                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var filteredCoaches: [Coach] {
        firestore.coaches.filter { coach in
            newConvSearch.isEmpty || coach.name.lowercased().contains(newConvSearch.lowercased())
        }
    }

    private var filteredClients: [FirestoreManager.UserSummary] {
        firestore.clients.filter { client in
            newConvSearch.isEmpty || client.name.lowercased().contains(newConvSearch.lowercased())
        }
    }

    // MARK: - Actions

    private func handleOnAppear() {
        firestore.listenForChatsForCurrentUser()
        let ids = firestore.chats.map { $0.id }
        if !ids.isEmpty {
            firestore.loadPreviewsForChats(chatIds: ids)
        }
        lastKnownChatIds = ids

        // Start periodic refresh task for UID-looking names
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                await MainActor.run { refreshUIDNames() }
            }
        }
    }

    private func handleChatsCountChange() {
        let ids = firestore.chats.map { $0.id }
        if ids != lastKnownChatIds {
            lastKnownChatIds = ids
            if !ids.isEmpty {
                firestore.loadPreviewsForChats(chatIds: ids)
                firestore.refreshAllParticipantNames()
            }
        }
    }

    private func createAndOpenChat(with otherId: String) {
        guard auth.user?.uid != nil else { return }
        isCreatingChat = true
        firestore.createOrGetChat(withCoachId: otherId) { chatId in
            DispatchQueue.main.async {
                self.isCreatingChat = false
                self.showingNewConversation = false
                if let cid = chatId {
                    self.navPath.append(cid)
                }
            }
        }
    }

    private func refreshUIDNames() {
        guard let currentUid = auth.user?.uid else { return }
        var uidsToRefresh: [String] = []
        for chat in firestore.chats {
            for p in chat.participants where p != currentUid {
                if let name = firestore.participantNames[p], looksLikeUID(name) {
                    uidsToRefresh.append(p)
                }
            }
        }
        if !uidsToRefresh.isEmpty {
            firestore.forceRefreshParticipantNames(for: uidsToRefresh)
        }
    }

    private func looksLikeUID(_ str: String) -> Bool {
        str.count >= 20 && !str.contains(" ") && str.allSatisfy { $0.isLetter || $0.isNumber }
    }
}

// MARK: - ChatRow

fileprivate struct ChatRow: View {
    let chat: FirestoreManager.ChatItem
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel

    private var otherParticipant: String {
        chat.participants.first(where: { $0 != auth.user?.uid }) ?? ""
    }

    var body: some View {
        HStack(alignment: .center) {
            AvatarView(url: firestore.participantPhotoURL(otherParticipant), size: 44, useCurrentUser: false)

            VStack(alignment: .leading) {
                Text(displayName).font(.headline)
                previewTextView
            }

            Spacer()

            if let date = firestore.previewDates[chat.id] ?? chat.lastMessageAt {
                Text(DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
        .onAppear(perform: handleOnAppear)
    }

    private var displayName: String {
        if let name = firestore.participantNames[otherParticipant], !name.isEmpty {
            return name
        }
        return otherParticipant
    }

    @ViewBuilder
    private var previewTextView: some View {
        let previewText = (firestore.previewTexts[chat.id]?.isEmpty == false)
            ? firestore.previewTexts[chat.id]!
            : (chat.lastMessageText ?? "")

        if previewText.isEmpty {
            Text("No messages")
                .font(.subheadline)
                .foregroundColor(.secondary)
        } else if firestore.unreadChatIds.contains(chat.id) {
            HStack(alignment: .center, spacing: 8) {
                Text(previewText)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 10, height: 10)
            }
        } else {
            Text(previewText)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }

    private func handleOnAppear() {
        guard !otherParticipant.isEmpty else { return }
        if firestore.participantNames[otherParticipant] == nil {
            firestore.ensureParticipantNames([otherParticipant])
        } else if looksLikeUID(firestore.participantNames[otherParticipant] ?? "") {
            firestore.forceRefreshParticipantNames(for: [otherParticipant])
        }
    }

    private func looksLikeUID(_ str: String) -> Bool {
        str.count >= 20 && !str.contains(" ") && str.allSatisfy { $0.isLetter || $0.isNumber }
    }
}

struct MessagesView_Previews: PreviewProvider {
    static var previews: some View {
        MessagesView()
            .environmentObject(FirestoreManager())
            .environmentObject(AuthViewModel())
    }
}
