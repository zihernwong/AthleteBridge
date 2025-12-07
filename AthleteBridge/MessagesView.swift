import SwiftUI

struct MessagesView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel

    var body: some View {
        NavigationStack {
            List {
                ForEach(firestore.chats) { chat in
                    NavigationLink(value: chat.id) {
                        HStack {
                            let other = chat.participants.first(where: { $0 != auth.user?.uid }) ?? ""
                            let displayName = firestore.participantNames[other] ?? other
                            let photoURL = firestore.participantPhotoURL(other)

                            AvatarView(url: photoURL, size: 44, useCurrentUser: false)

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
                }
            }
            .navigationTitle("Messages")
            .onAppear { firestore.listenForChatsForCurrentUser() }
            .navigationDestination(for: String.self) { chatId in
                ChatView(chatId: chatId).environmentObject(firestore)
            }
        }
    }
}

struct MessagesView_Previews: PreviewProvider {
    static var previews: some View {
        MessagesView().environmentObject(FirestoreManager()).environmentObject(AuthViewModel())
    }
}
