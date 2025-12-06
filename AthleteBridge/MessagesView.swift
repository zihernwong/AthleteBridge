import SwiftUI

struct MessagesView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel
    @State private var selectedChatId: String? = nil

    var body: some View {
        NavigationStack {
            List {
                ForEach(firestore.chats) { chat in
                    Button(action: { selectedChatId = chat.id }) {
                        HStack {
                            // show first other participant's avatar if available
                            let other = chat.participants.first(where: { $0 != auth.user?.uid }) ?? ""
                            // display name (resolved by FirestoreManager) or fallback to uid
                            let displayName = firestore.participantNames[other] ?? other
                            AvatarView(url: firestore.coachPhotoURLs[other] ?? nil, size: 44, useCurrentUser: false)
                            VStack(alignment: .leading) {
                                Text(displayName).font(.headline)
                                if let last = chat.lastMessageText {
                                    Text(last).font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                                } else {
                                    Text("No messages").font(.subheadline).foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            if let date = chat.lastMessageAt {
                                Text(DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)).font(.caption).foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .background(NavigationLink(destination: ChatView(chatId: chat.id).environmentObject(firestore), tag: chat.id, selection: $selectedChatId) { EmptyView() })
                }
            }
            .navigationTitle("Messages")
            .onAppear {
                // ensure chats listener is active
                firestore.listenForChatsForCurrentUser()
            }
        }
    }
}

struct MessagesView_Previews: PreviewProvider {
    static var previews: some View {
        MessagesView().environmentObject(FirestoreManager()).environmentObject(AuthViewModel())
    }
}
