import SwiftUI

struct MessagesView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel
    @State private var showingNewConversation = false
    @State private var navPath = NavigationPath()
    @State private var newConvSearch: String = ""
    @State private var isCreatingChat: Bool = false

    var body: some View {
        NavigationStack(path: $navPath) {
            Group {
                if firestore.chats.isEmpty {
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
                } else {
                    List {
                        ForEach(firestore.chats) { chat in
                            NavigationLink(value: chat.id) {
                                ChatRow(chat: chat)
                                    .environmentObject(firestore)
                                    .environmentObject(auth)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Messages")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showingNewConversation = true }) {
                        let isCoach = (firestore.currentUserType ?? "CLIENT").trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "COACH"
                        Text(isCoach ? "Message Clients" : "Message Nearby Coaches")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingNewConversation = true }) { Image(systemName: "plus") }
                }
            }
            .onAppear {
                firestore.listenForChatsForCurrentUser()
                let ids = firestore.chats.map { $0.id }
                if !ids.isEmpty { firestore.loadPreviewsForChats(chatIds: ids) }
            }
            .onChange(of: firestore.chats.map { $0.id }) { oldIds, newIds in
                if !newIds.isEmpty { firestore.loadPreviewsForChats(chatIds: newIds) }
            }
            .navigationDestination(for: String.self) { chatId in
                ChatView(chatId: chatId).environmentObject(firestore)
            }
            .sheet(isPresented: $showingNewConversation) {
                NavigationStack {
                    VStack(spacing: 0) {
                        HStack {
                            TextField("Search", text: $newConvSearch)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            Button("Close") { showingNewConversation = false }
                        }
                        .padding()

                        let roleIsClient = (firestore.currentUserType ?? "CLIENT").uppercased() != "COACH"

                        if roleIsClient {
                            List {
                                ForEach(firestore.coaches.filter { newConvSearch.isEmpty ? true : $0.name.lowercased().contains(newConvSearch.lowercased()) }) { coach in
                                    Button(action: { createAndOpenChat(with: coach.id) }) {
                                        HStack {
                                            AvatarView(url: firestore.coachPhotoURLs[coach.id] ?? nil, size: 36, useCurrentUser: false)
                                            Text(coach.name)
                                            Spacer()
                                        }
                                    }
                                }
                            }
                        } else {
                            List {
                                ForEach(firestore.clients.filter { newConvSearch.isEmpty ? true : $0.name.lowercased().contains(newConvSearch.lowercased()) }) { client in
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

                        if isCreatingChat { ProgressView("Creating chat...").padding() }
                    }
                    .navigationTitle("New Conversation")
                }
                .onAppear {
                    firestore.fetchCoaches()
                    firestore.fetchClients()
                }
            }
        }
    }

    private func createAndOpenChat(with otherId: String) {
        guard let _ = auth.user?.uid else { return }
        isCreatingChat = true
        firestore.createOrGetChat(withCoachId: otherId) { chatId in
            DispatchQueue.main.async {
                self.isCreatingChat = false
                self.showingNewConversation = false
                if let cid = chatId { self.navPath.append(cid) }
            }
        }
    }
}

fileprivate struct ChatRow: View {
    let chat: FirestoreManager.ChatItem
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel

    var body: some View {
        HStack(alignment: .center) {
            let other = chat.participants.first(where: { $0 != auth.user?.uid }) ?? ""
            let photoURL = firestore.participantPhotoURL(other)
            AvatarView(url: photoURL, size: 44, useCurrentUser: false)

            VStack(alignment: .leading) {
                Text(displayName(for: other)).font(.headline)
                let previewText = (firestore.previewTexts[chat.id]?.isEmpty == false) ? firestore.previewTexts[chat.id]! : (chat.lastMessageText ?? "")
                if previewText.isEmpty { Text("No messages").font(.subheadline).foregroundColor(.secondary) }
                else if firestore.unreadChatIds.contains(chat.id) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(previewText).font(.subheadline).fontWeight(.semibold).foregroundColor(.primary).lineLimit(1)
                        Circle().fill(Color.accentColor).frame(width: 10, height: 10)
                    }
                } else { Text(previewText).font(.subheadline).foregroundColor(.secondary).lineLimit(1) }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let date = firestore.previewDates[chat.id] ?? chat.lastMessageAt {
                    Text(DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)).font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
        .onAppear { let other = chat.participants.first(where: { $0 != auth.user?.uid }) ?? ""; if !other.isEmpty && firestore.participantNames[other] == nil { firestore.ensureParticipantNames([other]) } }
    }

    private func displayName(for uid: String) -> String {
        if let name = firestore.participantNames[uid], !name.isEmpty { return name }
        if let c = firestore.coaches.first(where: { $0.id == uid }) { return c.name }
        if let cl = firestore.clients.first(where: { $0.id == uid }) { return cl.name }
        return uid
    }
}

struct MessagesView_Previews: PreviewProvider {
    static var previews: some View {
        MessagesView().environmentObject(FirestoreManager()).environmentObject(AuthViewModel())
    }
}
