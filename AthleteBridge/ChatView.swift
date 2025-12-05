import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct ChatView: View {
    let chatId: String
    @EnvironmentObject var firestore: FirestoreManager
    @State private var messageText: String = ""
    @State private var messages: [Message] = []
    @State private var listener: ListenerRegistration? = nil
    @State private var sending: Bool = false

    private var messagesColl: CollectionReference {
        return Firestore.firestore().collection("chats").document(chatId).collection("messages")
    }
    private var chatDoc: DocumentReference {
        return Firestore.firestore().collection("chats").document(chatId)
    }

    var body: some View {
        VStack(spacing: 0) {
            // header area
            VStack(alignment: .leading, spacing: 4) {
                Text("Messages")
                    .font(.headline)
                Text("Conversation id: \(chatId)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(messages) { m in
                            MessageRow(message: m, isMe: m.senderId == Auth.auth().currentUser?.uid)
                                .id(m.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in
                    // scroll to bottom when messages change
                    if let last = messages.last {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
            }

            Divider()

            // Composer
            HStack(spacing: 8) {
                TextField("Write a message...", text: $messageText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .disabled(sending)

                Button(action: sendMessage) {
                    if sending {
                        ProgressView()
                            .scaleEffect(0.8, anchor: .center)
                            .frame(width: 56)
                    } else {
                        Text("Send")
                            .bold()
                            .frame(minWidth: 56)
                    }
                }
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
            }
            .padding()
            .background(Color(UIColor.systemBackground))
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: startListening)
        .onDisappear(perform: stopListening)
    }

    // MARK: - Firestore
    private func startListening() {
        // Attach listener ordered by createdAt asc (server timestamps may be nil initially)
        stopListening()
        let q = messagesColl.order(by: "createdAt", descending: false)
        listener = q.addSnapshotListener { snap, err in
            if let err = err {
                print("ChatView: messages listener error: \(err)")
                return
            }
            guard let docs = snap?.documents else { return }
            var mapped: [Message] = []
            for d in docs {
                let data = d.data()
                let id = d.documentID
                let sender = data["senderId"] as? String ?? ""
                let text = data["text"] as? String ?? ""
                var createdAt: Date? = nil
                if let ts = data["createdAt"] as? Timestamp { createdAt = ts.dateValue() }
                var readByMap: [String: Date]? = nil
                if let rb = data["readBy"] as? [String: Timestamp] {
                    var tmp: [String: Date] = [:]
                    for (k,v) in rb { tmp[k] = v.dateValue() }
                    readByMap = tmp
                }
                mapped.append(Message(id: id, senderId: sender, text: text, createdAt: createdAt, readBy: readByMap))
            }
            // sort by createdAt (nil -> older)
            mapped.sort { (a,b) in
                let ad = a.createdAt ?? Date.distantPast
                let bd = b.createdAt ?? Date.distantPast
                return ad < bd
            }
            DispatchQueue.main.async {
                self.messages = mapped
            }
        }
    }

    private func stopListening() {
        listener?.remove()
        listener = nil
    }

    private func sendMessage() {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let uid = Auth.auth().currentUser?.uid else { return }
        sending = true

        let newDoc = messagesColl.document()
        let nowField: FieldValue = FieldValue.serverTimestamp()
        // include initial readBy for the sender so sent messages show as read by the sender
        let payload: [String: Any] = [
            "senderId": uid,
            "text": trimmed,
            "createdAt": nowField,
            "readBy": [uid: nowField]
        ]

        // Use batch to write message and update parent chat's last message metadata
        let batch = Firestore.firestore().batch()
        batch.setData(payload, forDocument: newDoc)
        batch.updateData(["lastMessageText": trimmed, "lastMessageAt": nowField], forDocument: chatDoc)

        batch.commit { err in
            DispatchQueue.main.async {
                self.sending = false
                if let err = err {
                    print("ChatView: failed to send message: \(err)")
                    firestore.showToast("Failed to send message")
                } else {
                    self.messageText = ""
                    // Optionally append a local optimistic message until server timestamp arrives
                    // The listener will pick up the new message and refresh the list
                }
            }
        }
    }
}

// MARK: - Models & Cells
fileprivate struct Message: Identifiable, Equatable {
    let id: String
    let senderId: String
    let text: String
    let createdAt: Date?
    let readBy: [String: Date]?
}

fileprivate struct MessageRow: View {
    let message: Message
    let isMe: Bool

    var body: some View {
        HStack {
            if isMe { Spacer() }
            VStack(alignment: .leading, spacing: 4) {
                Text(message.text)
                    .foregroundColor(isMe ? .white : .primary)
                    .padding(10)
                    .background(isMe ? Color.blue : Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
                if let date = message.createdAt {
                    Text(DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                // Show read receipt info for messages sent by me: display count of other users who have read
                if isMe, let rb = message.readBy {
                    let otherReaders = rb.keys.filter { $0 != Auth.auth().currentUser?.uid }
                    if !otherReaders.isEmpty {
                        Text("Read by: \(otherReaders.count)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            if !isMe { Spacer() }
        }
        .padding(.horizontal, 8)
    }
}

struct ChatView_Previews: PreviewProvider {
    static var previews: some View {
        ChatView(chatId: "demo_chat_123")
            .environmentObject(FirestoreManager())
    }
}
