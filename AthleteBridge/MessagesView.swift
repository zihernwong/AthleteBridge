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
                // Empty state when there are no chats
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
                            // compute these here so modifiers (like onAppear) can capture them
                            let other = chat.participants.first(where: { $0 != auth.user?.uid }) ?? ""
                            let displayName = firestore.participantNames[other] ?? other
                            let photoURL = firestore.participantPhotoURL(other)

                            NavigationLink(value: chat.id) {
                                HStack {
                                    AvatarView(url: photoURL, size: 44, useCurrentUser: false)

                                    VStack(alignment: .leading) {
                                        Text(displayName).font(.headline)
                                        // Use centralized preview cache from FirestoreManager if available
                                        if let preview = firestore.previewTexts[chat.id], !preview.isEmpty {
                                            Text(preview).font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                                        } else if let last = chat.lastMessageText, !last.isEmpty {
                                            Text(last).font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                                        } else {
                                            Text("No messages").font(.subheadline).foregroundColor(.secondary)
                                        }
                                    }

                                    Spacer()

                                    if let date = firestore.previewDates[chat.id] ?? chat.lastMessageAt {
                                        Text(DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)).font(.caption).foregroundColor(.secondary)
                                    }
                                }
                                .padding(.vertical, 8)
                                .onAppear {
                                    // If we don't have a cached display name for the other participant, attempt to fetch it now.
                                    if !other.isEmpty && firestore.participantNames[other] == nil {
                                        firestore.ensureParticipantNames([other])
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Messages")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingNewConversation = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .onAppear {
                firestore.listenForChatsForCurrentUser()
                let ids = firestore.chats.map { $0.id }
                if !ids.isEmpty { firestore.loadPreviewsForChats(chatIds: ids) }
            }
            .onChange(of: firestore.chats.map { $0.id }) { _ , newIds in
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

                        // Determine role: treat unknown as client by default
                        let roleIsClient = (firestore.currentUserType ?? "CLIENT").uppercased() != "COACH"

                        if roleIsClient {
                            // Show coaches list
                            List {
                                ForEach(firestore.coaches.filter { newConvSearch.isEmpty ? true : $0.name.lowercased().contains(newConvSearch.lowercased()) }) { coach in
                                    Button(action: {
                                        createAndOpenChat(with: coach.id)
                                    }) {
                                        HStack {
                                            AvatarView(url: firestore.coachPhotoURLs[coach.id] ?? nil, size: 36, useCurrentUser: false)
                                            Text(coach.name)
                                            Spacer()
                                        }
                                    }
                                }
                            }
                        } else {
                            // Show clients list
                            List {
                                ForEach(firestore.clients.filter { newConvSearch.isEmpty ? true : $0.name.lowercased().contains(newConvSearch.lowercased()) }) { client in
                                    Button(action: {
                                        createAndOpenChat(with: client.id)
                                    }) {
                                        HStack {
                                            AvatarView(url: client.photoURL, size: 36, useCurrentUser: false)
                                            Text(client.name)
                                            Spacer()
                                        }
                                    }
                                }
                            }
                        }

                        if isCreatingChat {
                            ProgressView("Creating chat...")
                                .padding()
                        }
                    }
                    .navigationTitle("New Conversation")
                }
                .onAppear {
                    // refresh lists
                    firestore.fetchCoaches()
                    firestore.fetchClients()
                }
            }
        }
    }

    private func createAndOpenChat(with otherId: String) {
        guard let _ = auth.user?.uid else { return }
        isCreatingChat = true
        // Use createOrGetChat - FirestoreManager will resolve roles and create participantRefs appropriately
        firestore.createOrGetChat(withCoachId: otherId) { chatId in
            DispatchQueue.main.async {
                self.isCreatingChat = false
                self.showingNewConversation = false
                if let cid = chatId {
                    // navigate into the chat
                    self.navPath.append(cid)
                }
            }
        }
    }
}

struct MessagesView_Previews: PreviewProvider {
    static var previews: some View {
        MessagesView().environmentObject(FirestoreManager()).environmentObject(AuthViewModel())
    }
}
