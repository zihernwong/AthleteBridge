import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import PhotosUI

struct ChatView: View {
    let chatId: String
    @EnvironmentObject var firestore: FirestoreManager
    @State private var messageText: String = ""
    @State private var messages: [Message] = []
    @State private var listener: ListenerRegistration? = nil
    @State private var sending: Bool = false
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var isUploadingImage: Bool = false
    // locally track which message IDs we've already marked as read to avoid repeated writes
    @State private var locallyMarkedRead: Set<String> = []
    @State private var otherParticipantUID: String? = nil

    // Presence / online status
    @State private var otherLastSeen: Date? = nil
    @State private var presenceListenerCoach: ListenerRegistration? = nil
    @State private var presenceListenerClient: ListenerRegistration? = nil

    // Typing indicator
    @State private var otherIsTyping: Bool = false
    @State private var typingListener: ListenerRegistration? = nil
    @State private var typingDebounceTimer: Timer? = nil

    private var isOtherOnline: Bool {
        guard let lastSeen = otherLastSeen else { return false }
        return lastSeen.timeIntervalSinceNow > -120 // within 2 minutes
    }

    private var presenceStatusText: String {
        guard let lastSeen = otherLastSeen else { return "" }
        let interval = -lastSeen.timeIntervalSinceNow
        if interval < 120 { return "Online" }
        if interval < 3600 { return "Last seen \(Int(interval / 60))m ago" }
        if interval < 86400 { return "Last seen \(Int(interval / 3600))h ago" }
        return "Last seen \(DateFormatter.localizedString(from: lastSeen, dateStyle: .short, timeStyle: .short))"
    }

    // The ID of the last outgoing message that has been read by the other participant.
    // Only this message shows the "Read by" receipt.
    private var lastReadOutgoingMessageId: String? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        return messages.last(where: { msg in
            msg.senderId == uid &&
            (msg.readBy?.keys.contains(where: { $0 != uid }) ?? false)
        })?.id
    }

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
                        if !presenceStatusText.isEmpty {
                            HStack(spacing: 4) {
                                if isOtherOnline {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 8, height: 8)
                                }
                                Text(presenceStatusText)
                                    .font(.caption)
                                    .foregroundColor(isOtherOnline ? .green : .secondary)
                            }
                        }
                    }
                } else {
                    Text("Messages").font(.headline)
                }

                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 8)

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
                                MessageRow(
                                    message: m,
                                    isMe: m.senderId == Auth.auth().currentUser?.uid,
                                    showReadReceipt: m.id == lastReadOutgoingMessageId
                                )
                                .environmentObject(firestore)
                                .id(m.id)
                            }
                        }
                        .padding()
                    }
                    .onAppear {
                        // scroll to bottom on initial load
                        if let last = messages.last {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: messages.count) { _, _ in
                        // scroll to bottom when new messages arrive
                        if let last = messages.last {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                            }
                        }
                    }
                }
            }

            // Typing indicator
            if otherIsTyping {
                HStack {
                    TypingIndicatorView()
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Divider()

            // Composer
            HStack(spacing: 8) {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    if isUploadingImage {
                        ProgressView().frame(width: 28)
                    } else {
                        Image(systemName: "photo")
                            .font(.title3)
                            .foregroundColor(Color("LogoBlue"))
                    }
                }
                .disabled(isUploadingImage)
                .onChange(of: selectedPhotoItem) { _, item in
                    guard let item = item else { return }
                    Task {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            await MainActor.run { sendImage(data) }
                        }
                        await MainActor.run { selectedPhotoItem = nil }
                    }
                }

                TextField("Write a message...", text: $messageText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .disabled(sending)
                    .onChange(of: messageText) { _, text in
                        typingDebounceTimer?.invalidate()
                        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            setMyTypingState(true)
                            typingDebounceTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
                                setMyTypingState(false)
                            }
                        } else {
                            setMyTypingState(false)
                        }
                    }

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
            updateMyPresence()
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

            // Seed name/photo caches from the chat doc's denormalized maps
            self.firestore.seedParticipantInfo(fromChatData: data)

            // Keep my own denormalized entry fresh so the other side always has
            // an up-to-date name and photo to display (self-heals legacy chats)
            if let me = current {
                self.firestore.updateChatParticipantInfo(chatId: self.chatId, uid: me)
            }

            let other = participantsArr.first(where: { $0 != current }) ?? participantsArr.first

            // Backfill the other participant's entry too when the doc doesn't
            // have it yet — heals legacy chats even if that user never opens
            // the app again, so the list renders instantly next launch.
            if let o = other {
                let storedNames = data["participantNames"] as? [String: String] ?? [:]
                if (storedNames[o] ?? "").isEmpty {
                    self.firestore.updateChatParticipantInfo(chatId: self.chatId, uid: o)
                }
            }
            DispatchQueue.main.async {
                self.otherParticipantUID = other
                if let o = other {
                    self.firestore.ensureParticipantNames([o])
                    if self.firestore.participantNames[o] == nil {
                        self.fetchAndCacheParticipant(o)
                    }
                    self.startPresenceListeners(uid: o)
                    self.startTypingListener(otherUID: o)
                }
            }
        }
    }

    /// Fetch a single participant document (coach then client) and populate FirestoreManager's caches.
    /// Falls through to the clients doc when the coaches doc exists but has no usable name.
    private func fetchAndCacheParticipant(_ uid: String) {
        let db = Firestore.firestore()
        let coachRef = db.collection("coaches").document(uid)
        coachRef.getDocument { snap, err in
            if let err = err { print("ChatView: fetchAndCacheParticipant coach error: \(err)") }
            if let data = snap?.data(), snap?.exists == true {
                let name = FirestoreManager.profileDisplayName(from: data)
                if !name.isEmpty {
                    DispatchQueue.main.async { self.firestore.participantNames[uid] = name }
                    if let ps = FirestoreManager.profilePhotoString(from: data) {
                        self.firestore.resolvePhotoURL(ps) { url in DispatchQueue.main.async { self.firestore.coachPhotoURLs[uid] = url } }
                    }
                    return
                }
            }
            let clientRef = db.collection("clients").document(uid)
            clientRef.getDocument { csnap, cerr in
                if let cerr = cerr { print("ChatView: fetchAndCacheParticipant client error: \(cerr)") }
                if let cdata = csnap?.data(), csnap?.exists == true {
                    let name = FirestoreManager.profileDisplayName(from: cdata)
                    DispatchQueue.main.async { self.firestore.participantNames[uid] = name.isEmpty ? uid : name }
                    if let ps = FirestoreManager.profilePhotoString(from: cdata) {
                        self.firestore.resolvePhotoURL(ps) { url in DispatchQueue.main.async { self.firestore.clientPhotoURLs[uid] = url } }
                    }
                } else {
                    DispatchQueue.main.async { self.firestore.participantNames[uid] = uid }
                }
            }
        }
    }

    private func startListening() {
        // No server-side orderBy: Firestore's orderBy silently excludes documents that
        // are missing the field, which would drop messages written by older Android
        // builds that used "timestamp" instead of "createdAt". We sort client-side.
        stopListening()
        let q = messagesColl
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
                else if let ts = data["timestamp"] as? Timestamp { createdAt = ts.dateValue() }
                var readByMap: [String: Date]? = nil
                if let rb = data["readBy"] as? [String: Timestamp] {
                    var tmp: [String: Date] = [:]
                    for (k,v) in rb { tmp[k] = v.dateValue() }
                    readByMap = tmp
                }
                mapped.append(Message(id: id, senderId: sender, text: text, createdAt: createdAt, readBy: readByMap, imageURL: data["imageURL"] as? String))
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
        presenceListenerCoach?.remove()
        presenceListenerCoach = nil
        presenceListenerClient?.remove()
        presenceListenerClient = nil
        typingListener?.remove()
        typingListener = nil
        typingDebounceTimer?.invalidate()
        typingDebounceTimer = nil
        setMyTypingState(false)
    }

    // Listen to both coach and client collections for the other participant's lastSeenAt.
    // Whichever collection they belong to will fire with data.
    private func startPresenceListeners(uid: String) {
        presenceListenerCoach?.remove()
        presenceListenerClient?.remove()
        let db = Firestore.firestore()
        presenceListenerCoach = db.collection("coaches").document(uid).addSnapshotListener { snap, _ in
            guard let data = snap?.data(), snap?.exists == true else { return }
            if let ts = data["lastSeenAt"] as? Timestamp {
                DispatchQueue.main.async { self.otherLastSeen = ts.dateValue() }
            }
        }
        presenceListenerClient = db.collection("clients").document(uid).addSnapshotListener { snap, _ in
            guard let data = snap?.data(), snap?.exists == true else { return }
            if let ts = data["lastSeenAt"] as? Timestamp {
                DispatchQueue.main.async { self.otherLastSeen = ts.dateValue() }
            }
        }
    }

    // Listen to the other participant's typing state in chats/{chatId}/typing/{otherUID}.
    private func startTypingListener(otherUID: String) {
        typingListener?.remove()
        typingListener = Firestore.firestore()
            .collection("chats").document(chatId)
            .collection("typing").document(otherUID)
            .addSnapshotListener { snap, _ in
                guard let data = snap?.data() else {
                    DispatchQueue.main.async { self.otherIsTyping = false }
                    return
                }
                var isTyping = data["isTyping"] as? Bool ?? false
                // Treat stale typing state (>10 seconds old) as false
                if isTyping, let ts = data["updatedAt"] as? Timestamp {
                    if ts.dateValue().timeIntervalSinceNow < -10 { isTyping = false }
                }
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.2)) { self.otherIsTyping = isTyping }
                }
            }
    }

    // Write isTyping state to chats/{chatId}/typing/{myUID}.
    private func setMyTypingState(_ isTyping: Bool) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Firestore.firestore()
            .collection("chats").document(chatId)
            .collection("typing").document(uid)
            .setData(["isTyping": isTyping, "updatedAt": FieldValue.serverTimestamp()]) { _ in }
    }

    // Write the current user's lastSeenAt to their profile document.
    private func updateMyPresence() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let userType = (firestore.currentUserType ?? "").uppercased()
        let coll = userType == "COACH" ? "coaches" : "clients"
        Firestore.firestore().collection(coll).document(uid).updateData([
            "lastSeenAt": FieldValue.serverTimestamp()
        ]) { _ in }
    }

    /// Upload a picked photo to Storage and send it as an image message.
    private func sendImage(_ data: Data) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isUploadingImage = true

        // Downscale to keep uploads fast; fall back to original data if decoding fails
        let uploadData: Data = {
            guard let ui = UIImage(data: data) else { return data }
            let resized = ui.resizeMaintainingAspectRatio(targetSize: CGSize(width: 1280, height: 1280))
            return resized.jpegData(compressionQuality: 0.75) ?? data
        }()

        let ref = Storage.storage().reference().child("chat_images/\(chatId)/\(UUID().uuidString).jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        ref.putData(uploadData, metadata: metadata) { _, err in
            if let err = err {
                DispatchQueue.main.async {
                    self.isUploadingImage = false
                    firestore.showToast("Failed to upload photo: \(err.localizedDescription)")
                }
                return
            }
            ref.downloadURL { url, _ in
                guard let url = url else {
                    DispatchQueue.main.async { self.isUploadingImage = false }
                    return
                }
                let newDoc = messagesColl.document()
                let userTypeUpper = (firestore.currentUserType ?? "").uppercased()
                let userColl = (userTypeUpper == "COACH") ? Firestore.firestore().collection("coaches") : Firestore.firestore().collection("clients")
                let payload: [String: Any] = [
                    "senderRef": userColl.document(uid),
                    "senderId": uid,
                    "text": "",
                    "imageURL": url.absoluteString,
                    "createdAt": FieldValue.serverTimestamp()
                ]
                let batch = Firestore.firestore().batch()
                batch.setData(payload, forDocument: newDoc)
                batch.updateData(["lastMessageText": "📷 Photo", "lastMessageAt": FieldValue.serverTimestamp()], forDocument: chatDoc)
                batch.commit { err in
                    DispatchQueue.main.async {
                        self.isUploadingImage = false
                        if let err = err {
                            firestore.showToast("Failed to send photo: \(err.localizedDescription)")
                        } else {
                            self.updateMyPresence()
                        }
                    }
                }
            }
        }
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
                    self.updateMyPresence()
                }
            }
        }
    }
}

// MARK: - Models & Cells

/// Image message bubble with progressive loading.
// Cached, retrying image loader for chat photos.
// AsyncImage was unreliable here: chat rows are recreated constantly (new
// snapshots, typing indicators, read receipts), and AsyncImage cancels its
// download when the row is recreated mid-load, then sticks in the grey
// failure state and never retries — recipients saw a grey box while senders
// (whose URL cache was primed by the upload) saw the photo fine.
fileprivate struct ChatImageBubble: View {
    let url: URL
    @State private var image: UIImage? = nil
    @State private var failed = false

    var body: some View {
        Group {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: UIScreen.main.bounds.width * 0.6, maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if failed {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 200, height: 120)
                    .overlay(
                        VStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(.secondary)
                            Text("Tap to retry")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    )
                    .onTapGesture {
                        failed = false
                        Task { await load() }
                    }
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 200, height: 200)
                    .overlay(ProgressView())
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        if let cached = AvatarImageCache.shared.image(for: url) {
            image = cached
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let ui = UIImage(data: data) else {
                await MainActor.run { failed = true }
                return
            }
            AvatarImageCache.shared.set(ui, for: url)
            await MainActor.run { image = ui }
        } catch is CancellationError {
            // Row was recreated mid-download — the new instance's .task retries
        } catch {
            let nsError = error as NSError
            if nsError.code == NSURLErrorCancelled { return } // same: retried by new instance
            await MainActor.run { failed = true }
        }
    }
}

fileprivate struct Message: Identifiable, Equatable {
    let id: String
    let senderId: String
    let text: String
    let createdAt: Date?
    let readBy: [String: Date]?
    var imageURL: String? = nil
}

fileprivate struct MessageRow: View {
    let message: Message
    let isMe: Bool
    let showReadReceipt: Bool
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
                    if let imageURL = message.imageURL, let url = URL(string: imageURL) {
                        ChatImageBubble(url: url)
                    } else {
                        Text(message.text)
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.blue)
                            .cornerRadius(12)
                            .frame(maxWidth: UIScreen.main.bounds.width * 0.72, alignment: .trailing)
                    }

                    if let date = message.createdAt {
                        Text(DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    if showReadReceipt, let info = latestReaderInfo {
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

                    if let imageURL = message.imageURL, let url = URL(string: imageURL) {
                        ChatImageBubble(url: url)
                    } else {
                        Text(message.text)
                            .foregroundColor(.primary)
                            .padding(12)
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(12)
                            .frame(maxWidth: UIScreen.main.bounds.width * 0.72, alignment: .leading)
                    }

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

// MARK: - Typing Indicator

fileprivate struct TypingIndicatorView: View {
    @State private var animate = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary.opacity(0.6))
                    .frame(width: 8, height: 8)
                    .offset(y: animate ? -4 : 0)
                    .animation(
                        .easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.15),
                        value: animate
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(14)
        .onAppear { animate = true }
    }
}

struct ChatView_Previews: PreviewProvider {
    static var previews: some View {
        ChatView(chatId: "demo_chat_123")
            .environmentObject(FirestoreManager())
    }
}
