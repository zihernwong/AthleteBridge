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
    @State private var otherParticipantUID: String? = nil

    private var messagesColl: CollectionReference {
        return Firestore.firestore().collection("chats").document(chatId).collection("messages")
    }
    private var chatDoc: DocumentReference {
        return Firestore.firestore().collection("chats").document(chatId)
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
                    if let url = firestore.participantPhotoURL(other) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                Circle().fill(Color.gray.opacity(0.3)).frame(width: 44, height: 44)
                            case .success(let img):
                                img.resizable().scaledToFill().frame(width: 44, height: 44).clipShape(Circle())
                            case .failure(_):
                                let name = firestore.participantNames[other] ?? other
                                Text(String(name.prefix(1))).font(.headline).foregroundColor(.white).frame(width: 44, height: 44).background(Circle().fill(Color.gray))
                            @unknown default:
                                Circle().fill(Color.gray.opacity(0.3)).frame(width: 44, height: 44)
                            }
                        }
                    } else {
                        let name = firestore.participantNames[other] ?? other
                        Text(initials(from: name)).font(.headline).foregroundColor(.white).frame(width: 44, height: 44).background(Circle().fill(Color.gray))
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
                                    .environmentObject(firestore)
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
            let other = participantsArr.first(where: { $0 != current }) ?? participantsArr.first
            DispatchQueue.main.async {
                self.otherParticipantUID = other
                if let o = other {
                    self.firestore.ensureParticipantNames([o])
                    if self.firestore.participantNames[o] == nil {
                        self.fetchAndCacheParticipant(o)
                    }
                }
            }
        }
    }

    /// Fetch a single participant document (coach then client) and populate FirestoreManager's caches
    private func fetchAndCacheParticipant(_ uid: String) {
        let db = Firestore.firestore()
        let coachRef = db.collection("coaches").document(uid)
        coachRef.getDocument { snap, err in
            if let err = err { print("ChatView: fetchAndCacheParticipant coach error: \(err)") }
            if let data = snap?.data(), snap?.exists == true {
                let first = (data["FirstName"] as? String) ?? (data["firstName"] as? String) ?? ""
                let last = (data["LastName"] as? String) ?? (data["lastName"] as? String) ?? ""
                let name = [first, last].filter { !$0.isEmpty }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
                DispatchQueue.main.async { self.firestore.participantNames[uid] = name.isEmpty ? uid : name }
                let photoStr = (data["PhotoURL"] as? String) ?? (data["photoURL"] as? String) ?? (data["photoUrl"] as? String)
                if let ps = photoStr, !ps.isEmpty {
                    self.firestore.resolvePhotoURL(ps) { url in DispatchQueue.main.async { self.firestore.coachPhotoURLs[uid] = url } }
                }
                return
            }
            let clientRef = db.collection("clients").document(uid)
            clientRef.getDocument { csnap, cerr in
                if let cerr = cerr { print("ChatView: fetchAndCacheParticipant client error: \(cerr)") }
                if let cdata = csnap?.data(), csnap?.exists == true {
                    let name = (cdata["name"] as? String) ?? (cdata["Name"] as? String) ?? uid
                    DispatchQueue.main.async { self.firestore.participantNames[uid] = name }
                    let photoStr = (cdata["photoURL"] as? String) ?? (cdata["PhotoURL"] as? String) ?? (cdata["photoUrl"] as? String)
                    if let ps = photoStr, !ps.isEmpty {
                        self.firestore.resolvePhotoURL(ps) { url in DispatchQueue.main.async { self.firestore.clientPhotoURLs[uid] = url } }
                    }
                } else {
                    DispatchQueue.main.async { self.firestore.participantNames[uid] = uid }
                }
            }
        }
    }

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
            // Ensure we have display names/photos for all senders to avoid showing raw UIDs.
            let senderIds = Array(Set(mapped.map { $0.senderId }).filter { !$0.isEmpty })
            if !senderIds.isEmpty {
                // Ask FirestoreManager to batch-resolve names/photos; it's asynchronous and updates @Published caches.
                self.firestore.ensureParticipantNames(senderIds)
                // As a fast fallback, directly fetch any participants not yet resolved.
                for uid in senderIds where self.firestore.participantNames[uid] == nil {
                    self.fetchAndCacheParticipant(uid)
                }
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
        // Use a full-width HStack and place content left/right using Spacers
        HStack(alignment: .top) {
            if isMe {
                Spacer(minLength: 8)

                // Outgoing message: right aligned bubble
                VStack(alignment: .trailing, spacing: 6) {
                    Text(message.text)
                        .foregroundColor(.white)
                        .padding(12)
                        .background(Color.blue)
                        .cornerRadius(12)
                        .frame(maxWidth: UIScreen.main.bounds.width * 0.72, alignment: .trailing)

                    if let date = message.createdAt {
                        Text(DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    if let info = latestReaderInfo {
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
            } else {
                // Incoming message: avatar + left-aligned bubble
                if let url = firestore.participantPhotoURL(message.senderId) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            Circle().fill(Color.gray.opacity(0.3)).frame(width: 36, height: 36)
                        case .success(let img):
                            img.resizable().scaledToFill().frame(width: 36, height: 36).clipShape(Circle())
                        case .failure(_):
                            Text(initials(from: firestore.participantNames[message.senderId] ?? message.senderId)).font(.caption2).foregroundColor(.white).frame(width: 36, height: 36).background(Circle().fill(Color.gray))
                        @unknown default:
                            Circle().fill(Color.gray.opacity(0.3)).frame(width: 36, height: 36)
                        }
                    }
                } else {
                    Text(initials(from: firestore.participantNames[message.senderId] ?? message.senderId)).font(.caption2).foregroundColor(.white).frame(width: 36, height: 36).background(Circle().fill(Color.gray))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(firestore.participantNames[message.senderId] ?? message.senderId)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(message.text)
                        .foregroundColor(.primary)
                        .padding(12)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(12)
                        .frame(maxWidth: UIScreen.main.bounds.width * 0.72, alignment: .leading)

                    if let date = message.createdAt {
                        Text(DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer(minLength: 8)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

struct ChatView_Previews: PreviewProvider {
    static var previews: some View {
        ChatView(chatId: "demo_chat_123")
            .environmentObject(FirestoreManager())
    }
}
