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
    // locally track which message IDs we've already marked as read to avoid repeated writes
    @State private var locallyMarkedRead: Set<String> = []
    // Resolved other participant for header display
    @State private var otherParticipantUID: String? = nil

    private var messagesColl: CollectionReference {
        return Firestore.firestore().collection("chats").document(chatId).collection("messages")
    }
    private var chatDoc: DocumentReference {
        return Firestore.firestore().collection("chats").document(chatId)
    }

    private func resolveOtherParticipant() {
        chatDoc.getDocument { snap, err in
            if let err = err {
                print("ChatView: failed to fetch chat doc for header: \(err)")
                return
            }
            guard let data = snap?.data() else { return }
            var participantsArr: [String] = []
            if let refs = data["participantRefs"] as? [DocumentReference] {
                participantsArr = refs.map { $0.documentID }
            } else if let strs = data["participants"] as? [String] {
                participantsArr = strs
            }
            guard !participantsArr.isEmpty else { return }
            let current = Auth.auth().currentUser?.uid
            // choose the first participant that is not the current user
            let other = participantsArr.first(where: { $0 != current }) ?? participantsArr.first
            DispatchQueue.main.async {
                self.otherParticipantUID = other
                if let o = other { self.firestore.ensureParticipantNames([o]) }
            }
        }
    }

    // Mark messages as read for the current user by adding readBy.<uid> = serverTimestamp()
    private func markUnreadMessagesAsRead(_ msgs: [Message]) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        var idsToMark: [String] = []
        for m in msgs {
            // skip messages sent by me
            if m.senderId == uid { continue }
            // skip if Firestore already shows this uid
            if let rb = m.readBy, rb[uid] != nil { continue }
            // skip if we've already marked this id locally to avoid re-writing
            if locallyMarkedRead.contains(m.id) { continue }
            idsToMark.append(m.id)
        }
        guard !idsToMark.isEmpty else { return }

        // chunk writes to stay under Firestore batch limits
        let chunkSize = 400
        var start = 0
        while start < idsToMark.count {
            let end = min(start + chunkSize, idsToMark.count)
            let slice = Array(idsToMark[start..<end])
            let batch = Firestore.firestore().batch()
            for id in slice {
                let ref = messagesColl.document(id)
                batch.updateData(["readBy.\(uid)": FieldValue.serverTimestamp()], forDocument: ref)
            }
            batch.commit { err in
                if let err = err {
                    print("ChatView: markUnreadMessagesAsRead commit error: \(err)")
                } else {
                    DispatchQueue.main.async {
                        for id in slice { self.locallyMarkedRead.insert(id) }
                    }
                }
            }
            start += chunkSize
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // header area - show other participant's avatar + name when available
            HStack(spacing: 12) {
                if let other = otherParticipantUID {
                    // Try to obtain photo URL from cached maps
                    if let url = firestore.participantPhotoURL(other) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                Circle().fill(Color.gray.opacity(0.3)).frame(width: 40, height: 40)
                            case .success(let img):
                                img.resizable().scaledToFill().frame(width: 40, height: 40).clipShape(Circle())
                            case .failure(_):
                                let name = firestore.participantNames[other] ?? other
                                Text(String(name.prefix(1))).font(.headline).foregroundColor(.white).frame(width: 40, height: 40).background(Circle().fill(Color.gray))
                            @unknown default:
                                Circle().fill(Color.gray.opacity(0.3)).frame(width: 40, height: 40)
                            }
                        }
                    } else {
                        // no photo, show initials from cached name (or UID)
                        let name = firestore.participantNames[other] ?? other
                        Text(initials(from: name)).font(.headline).foregroundColor(.white).frame(width: 40, height: 40).background(Circle().fill(Color.gray))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(firestore.participantNames[other] ?? other)
                            .font(.headline)
                        Text("Online")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Messages").font(.headline)
                }

                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 8)

            Divider()

            // Message list or empty state
            if messages.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Text("No messages, start a conversation today!")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 40)
                    Text("Be the first to send a message in this conversation.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
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
        .onAppear {
            startListening()
            resolveOtherParticipant()
        }
        .onDisappear(perform: stopListening)
    }

    // Helper to compute initials for header fallback
    private func initials(from name: String) -> String {
        let parts = name.split(separator: " ").map { String($0) }
        if parts.count == 0 { return "?" }
        if parts.count == 1 { return String(parts[0].prefix(1)).uppercased() }
        return (String(parts[0].prefix(1)) + String(parts[1].prefix(1))).uppercased()
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
                // Prefer DocumentReference senderRef, fall back to legacy senderId/string
                var sender = ""
                if let sRef = data["senderRef"] as? DocumentReference {
                    sender = sRef.documentID
                } else if let s = data["senderId"] as? String {
                    sender = s
                } else if let s = data["sender"] as? String {
                    sender = s
                }
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
                // mark unread incoming messages as read for the current user (only once per message)
                self.markUnreadMessagesAsRead(mapped)
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
        // Build a senderRef DocumentReference based on current user type (coach/client)
        let userTypeUpper = (firestore.currentUserType ?? "").uppercased()
        let userColl = (userTypeUpper == "COACH") ? Firestore.firestore().collection("coaches") : Firestore.firestore().collection("clients")
        let senderRef = userColl.document(uid)
        // Do NOT pre-populate readBy for the sender. Recipients are marked when they view the message.
        let payload: [String: Any] = [
            "senderRef": senderRef,
            "senderId": uid, // keep legacy field for compatibility
            "text": trimmed,
            "createdAt": nowField
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
    @EnvironmentObject var firestore: FirestoreManager

    func initials(from name: String) -> String {
        let parts = name.split(separator: " ").map { String($0) }
        if parts.count == 0 { return "?" }
        if parts.count == 1 { return String(parts[0].prefix(1)).uppercased() }
        return (String(parts[0].prefix(1)) + String(parts[1].prefix(1))).uppercased()
    }

    // Compute latest reader info outside the ViewBuilder to avoid using let/var inside the body
    private var latestReaderInfo: (uid: String, name: String, photoURL: URL?, date: Date)? {
        guard let rb = message.readBy else { return nil }
        let currentUid = Auth.auth().currentUser?.uid
        let otherEntries = rb.filter { $0.key != currentUid }
        guard let latestEntry = otherEntries.max(by: { $0.value < $1.value }) else { return nil }
        let readerUid = latestEntry.key
        let readDate = latestEntry.value
        let readerName = firestore.participantNames[readerUid] ?? readerUid
        var photoURL: URL? = nil
        if let u = firestore.coachPhotoURLs[readerUid] { photoURL = u }
        else if let u2 = firestore.clientPhotoURLs[readerUid] { photoURL = u2 }
        return (readerUid, readerName, photoURL, readDate)
    }

    var body: some View {
        HStack(alignment: .bottom) {
            if isMe { Spacer() }

            VStack(alignment: .leading, spacing: 6) {
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

                // Show read receipt info for messages sent by me: display reader name and time with avatar
                if isMe, let info = latestReaderInfo {
                    HStack(spacing: 8) {
                        if let url = info.photoURL {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .empty:
                                    Circle().fill(Color.gray.opacity(0.3)).frame(width: 18, height: 18)
                                case .success(let img):
                                    img.resizable().scaledToFill().frame(width: 18, height: 18).clipShape(Circle())
                                case .failure(_):
                                    Text(initials(from: info.name)).font(.caption2).foregroundColor(.white).frame(width: 18, height: 18).background(Circle().fill(Color.gray))
                                @unknown default:
                                    Circle().fill(Color.gray.opacity(0.3)).frame(width: 18, height: 18)
                                }
                            }
                        } else {
                            Text(initials(from: info.name)).font(.caption2).foregroundColor(.white).frame(width: 18, height: 18).background(Circle().fill(Color.gray))
                        }

                        let timeStr = DateFormatter.localizedString(from: info.date, dateStyle: .none, timeStyle: .short)
                        Text("Read by \(info.name) at \(timeStr)")
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
