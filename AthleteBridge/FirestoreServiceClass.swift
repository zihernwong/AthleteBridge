import Foundation
@preconcurrency import Firebase
@preconcurrency import FirebaseFirestore
@preconcurrency import FirebaseAuth
@preconcurrency import FirebaseStorage
import SwiftUI
import CoreLocation
@preconcurrency import EventKit

@MainActor
class FirestoreManager: ObservableObject {
    // Shared singleton fallback
    static let shared = FirestoreManager()

    // Delay creating Firestore until after Firebase is configured in init
    private var db: Firestore!
    private var authStateListenerHandle: AuthStateDidChangeListenerHandle?

    @Published var coaches: [Coach] = []
    @Published var coachPhotoURLs: [String: URL?] = [:]
    private var isFetchingCoaches: Bool = false
    private var lastCoachesFetchTime: Date? = nil
    // Lightweight client summaries used for new-conversation picker
    struct UserSummary: Identifiable {
        let id: String
        let name: String
        let photoURL: URL?
    }
    @Published var clients: [UserSummary] = []
    @Published var clientPhotoURLs: [String: URL?] = [:]
    @Published var currentClient: Client? = nil
    @Published var currentClientPhotoURL: URL? = nil
    // Small cached UIImage for the tab bar/avatar usage (keeps MainAppView simple and avoids re-downloading)
    @Published var currentUserTabImage: UIImage? = nil
    @Published var currentCoach: Coach? = nil
    @Published var currentCoachPhotoURL: URL? = nil
    // Published user type from `userType/{uid}` (e.g. "COACH" or "CLIENT")
    @Published var currentUserType: String? = nil
    @Published var userTypeLoaded: Bool = false

    // User preference: whether to automatically add confirmed bookings to the device calendar
    @Published var autoAddToCalendar: Bool = false

    /// Fetch user-specific settings stored under `userSettings/{uid}` and populate local published properties.
    func fetchUserSettings(for uid: String) {
        let ref = db.collection("userSettings").document(uid)
        ref.getDocument { snap, err in
            if let err = err {
                print("fetchUserSettings error: \(err)")
                return
            }
            let data = snap?.data() ?? [:]
            let auto = data["autoAddCalendar"] as? Bool ?? false
            DispatchQueue.main.async {
                self.autoAddToCalendar = auto
            }
        }
    }

    /// Persist the auto-add-to-calendar preference for the current user into Firestore.
    func setAutoAddToCalendar(_ value: Bool, completion: ((Error?) -> Void)? = nil) {
        DispatchQueue.main.async { self.autoAddToCalendar = value }
        guard let uid = Auth.auth().currentUser?.uid else { completion?(nil); return }
        let ref = db.collection("userSettings").document(uid)
        ref.setData(["autoAddCalendar": value], merge: true) { err in
            if let err = err { print("setAutoAddToCalendar error: \(err)") }
            completion?(err)
        }
    }

    // MARK: - Subjects
    struct Subject: Identifiable {
        let id: String
        let title: String
        let order: Int
        let active: Bool
    }

    @Published var subjects: [Subject] = []
    @Published var subjectsDebug: String = ""

    /// Fetch all subjects from the `subjects` collection, ordered by the `order` field.
    func fetchSubjects() {
        DispatchQueue.main.async { self.subjectsDebug = "Starting fetchSubjects..." }
        let coll = self.db.collection("subjects").order(by: "order")
        coll.getDocuments { snapshot, error in
            if let error = error {
                let msg = "fetchSubjects error: \(error.localizedDescription)"
                print(msg)
                DispatchQueue.main.async { self.subjectsDebug += "\n\(msg)" }
                return
            }
            let docs = snapshot?.documents ?? []
            let header = "fetchSubjects: total=\(docs.count)"
            print(header)
            DispatchQueue.main.async { self.subjectsDebug += "\n\(header)" }

            let mapped: [Subject] = docs.map { d in
                let data = d.data()
                let id = d.documentID
                let title = (data["title"] as? String) ?? ""
                let order = data["order"] as? Int ?? 0
                let active = data["active"] as? Bool ?? true
                return Subject(id: id, title: title, order: order, active: active)
            }

            DispatchQueue.main.async {
                self.subjects = mapped
                self.subjectsDebug += "\nAssigned \(mapped.count) subjects"
            }
        }
    }

    /// Seed the `subjects` collection with sane defaults if the collection is currently empty.
    /// This is safe to call on app startup; it will do nothing if subjects already exist.
    func seedSubjectsIfEmpty(defaults: [String], completion: @escaping (Error?) -> Void = { _ in }) {
        let coll = self.db.collection("subjects")
        coll.getDocuments { snapshot, error in
            if let error = error {
                print("seedSubjectsIfEmpty: failed to list subjects: \(error)")
                completion(error)
                return
            }
            let docs = snapshot?.documents ?? []
            if !docs.isEmpty {
                print("seedSubjectsIfEmpty: subjects collection already has \(docs.count) documents; skipping seeding")
                completion(nil)
                return
            }

            // Seed defaults
            let batch = self.db.batch()
            for (idx, title) in defaults.enumerated() {
                let docRef = coll.document()
                let data: [String: Any] = [
                    "title": title,
                    "order": idx,
                    "active": true,
                    "createdAt": FieldValue.serverTimestamp()
                ]
                batch.setData(data, forDocument: docRef)
            }
            batch.commit { err in
                if let err = err { print("seedSubjectsIfEmpty: commit error: \(err)"); completion(err); return }
                print("seedSubjectsIfEmpty: seeded \(defaults.count) subjects")
                // refresh local cache
                self.fetchSubjects()
                completion(nil)
            }
        }
    }

    /// Add a new subject into the `subjects` collection (idempotent w.r.t. title, case-insensitive).
    func addSubject(title: String, completion: @escaping (Error?) -> Void = { _ in }) {
        let coll = self.db.collection("subjects")
        // Normalize
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { completion(NSError(domain: "FirestoreManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Empty title"])); return }

        // Check for duplicates (case-insensitive) then add
        coll.getDocuments { snap, err in
            if let err = err { completion(err); return }
            let docs = snap?.documents ?? []
            let lower = trimmed.lowercased()
            if docs.contains(where: { (($0.data()["title"] as? String)?.lowercased() == lower) }) {
                // Already exists - refresh cache and return success
                self.fetchSubjects()
                completion(nil)
                return
            }

            let order = docs.count
            let data: [String: Any] = [
                "title": trimmed,
                "order": order,
                "active": true,
                "createdAt": FieldValue.serverTimestamp()
            ]
            coll.addDocument(data: data) { err in
                if let err = err { completion(err); return }
                // refresh in-memory subjects
                self.fetchSubjects()
                completion(nil)
            }
        }
    }

    // MARK: - Bookings
    struct BookingItem: Identifiable {
        let id: String
        let clientID: String
        let clientName: String?
        let coachID: String
        let coachName: String?
        let startAt: Date?
        let endAt: Date?
        let location: String?
        let notes: String?
        let status: String?
        let paymentStatus: String?
        let RateUSD: Double?

        init(id: String,
             clientID: String,
             clientName: String? = nil,
             coachID: String,
             coachName: String? = nil,
             startAt: Date? = nil,
             endAt: Date? = nil,
             location: String? = nil,
             notes: String? = nil,
             status: String? = nil,
             paymentStatus: String? = nil,
             RateUSD: Double? = nil) {
            self.id = id
            self.clientID = clientID
            self.clientName = clientName
            self.coachID = coachID
            self.coachName = coachName
            self.startAt = startAt
            self.endAt = endAt
            self.location = location
            self.notes = notes
            self.status = status
            self.paymentStatus = paymentStatus
            self.RateUSD = RateUSD
        }
    }

    @Published var bookings: [BookingItem] = []
    @Published var bookingsDebug: String = ""

    // MARK: - Reviews
    struct ReviewItem: Identifiable {
        let id: String
        let clientID: String
        let clientName: String?
        let coachID: String
        let coachName: String?
        let createdAt: Date?
        let rating: String?
        let ratingMessage: String?
    }

    @Published var reviews: [ReviewItem] = []
    @Published var reviewsDebug: String = ""

    // MARK: - Locations
    struct LocationItem: Identifiable, Equatable {
        let id: String
        let name: String?
        let address: String?
        let notes: String?
        let latitude: Double?
        let longitude: Double?

        static func ==(lhs: LocationItem, rhs: LocationItem) -> Bool {
            return lhs.id == rhs.id
                && lhs.name == rhs.name
                && lhs.address == rhs.address
                && lhs.latitude == rhs.latitude
                && lhs.longitude == rhs.longitude
        }
    }

    @Published var locations: [LocationItem] = []
    @Published var locationsDebug: String = ""

    /// Aggregated bookings fetched from each coach's subcollection
    @Published var coachBookings: [BookingItem] = []
    @Published var coachBookingsDebug: String = ""

    // MARK: - Chat / Messaging
    struct ChatMessage: Identifiable {
        let id: String
        let senderId: String
        let text: String
        let createdAt: Date?
    }

    struct ChatItem: Identifiable {
        let id: String
        let participants: [String]
        let lastMessageText: String?
        let lastMessageAt: Date?
    }

    @Published var chats: [ChatItem] = []
    @Published var chatsDebug: String = ""

    // simple cache mapping uid -> display name for participants
    @Published var participantNames: [String: String] = [:]

    // messagesByChat stores messages per chat id
    @Published var messagesByChat: [String: [ChatMessage]] = [:]

    // centralized preview caches (latest message text and date) for chats
    @Published var previewTexts: [String: String] = [:]
    @Published var previewDates: [String: Date] = [:]
    // Set of chat ids that currently have unread messages for the signed-in user
    @Published var unreadChatIds: Set<String> = []

    // Snapshot listeners keyed by chat id for the latest-message preview (limit 1 listener per chat)
    private var previewListeners: [String: ListenerRegistration] = [:]

    /// Load the latest message preview for the given chat IDs.
    /// This fetches the newest message document from chats/{chatId}/messages ordered by createdAt desc limit 1
    /// and stores the text/time in `previewTexts`/`previewDates`.
    func loadPreviewsForChats(chatIds: [String]) {
        guard let collRoot = db else { return }

        // Remove listeners for chats that are no longer in the provided list
        let incomingSet = Set(chatIds)
        for (id, listener) in previewListeners {
            if !incomingSet.contains(id) {
                listener.remove()
                previewListeners.removeValue(forKey: id)
                DispatchQueue.main.async {
                    self.previewTexts.removeValue(forKey: id)
                    self.previewDates.removeValue(forKey: id)
                    self.unreadChatIds.remove(id)
                }
            }
        }

        for chatId in chatIds {
            // if already listening, skip
            if previewListeners[chatId] != nil { continue }

            let coll = collRoot.collection("chats").document(chatId).collection("messages")
            let q = coll.order(by: "createdAt", descending: true).limit(to: 1)
            let listener = q.addSnapshotListener { snap, err in
                if let err = err {
                    print("loadPreviewsForChats listener error for \(chatId): \(err)")
                    return
                }

                guard let doc = snap?.documents.first else {
                    DispatchQueue.main.async {
                        self.previewTexts[chatId] = ""
                        self.previewDates[chatId] = nil
                        self.unreadChatIds.remove(chatId)
                    }
                    return
                }

                let data = doc.data()
                let text = data["text"] as? String ?? ""
                var date: Date? = nil
                if let ts = data["createdAt"] as? Timestamp { date = ts.dateValue() }

                // Determine unread status for current user
                var isUnread = false
                if let uid = Auth.auth().currentUser?.uid {
                    var senderId: String? = nil
                    if let sRef = data["senderRef"] as? DocumentReference { senderId = sRef.documentID }
                    else if let s = data["senderId"] as? String { senderId = s }
                    else if let s = data["sender"] as? String { senderId = s }

                    if let sid = senderId, sid != uid {
                        if let readBy = data["readBy"] as? [String: Any] {
                            if readBy[uid] == nil { isUnread = true }
                        } else {
                            isUnread = true
                        }
                    }
                } else {
                    // If we don't have an authenticated uid yet, conservatively treat it as unread
                    isUnread = true
                }

                DispatchQueue.main.async {
                    self.previewTexts[chatId] = text
                    if let d = date { self.previewDates[chatId] = d }
                    if isUnread { self.unreadChatIds.insert(chatId) } else { self.unreadChatIds.remove(chatId) }
                }
            }

            previewListeners[chatId] = listener
        }
    }

    // Ensure preview listeners are cleaned up when stopping all chat listeners
    func stopAllPreviewListeners() {
        for (_, l) in previewListeners { l.remove() }
        previewListeners.removeAll()
        DispatchQueue.main.async {
            self.previewTexts = [:]
            self.previewDates = [:]
            self.unreadChatIds = []
        }
    }

    // Firestore listener handles
     private var chatsListener: ListenerRegistration? = nil
     private var messageListeners: [String: ListenerRegistration] = [:]

     /// Start listening for all chat documents where the current user is a participant.
     /// Updates `chats` published property whenever chats are created/updated.
     func listenForChatsForCurrentUser() {
        guard let uid = Auth.auth().currentUser?.uid else {
            print("listenForChatsForCurrentUser: no authenticated user")
            DispatchQueue.main.async { self.chats = []; self.chatsDebug = "No user" }
            return
        }

        // If user type hasn't loaded yet, defer until it does
        if !userTypeLoaded {
            print("listenForChatsForCurrentUser: userType not loaded yet, deferring")
            return
        }

        // Stop previous listener if any
        chatsListener?.remove()
        chatsListener = nil

        print("listenForChatsForCurrentUser: registering listener for uid=\(uid) userType=\(self.currentUserType ?? "nil")")

        let userTypeUpper = (self.currentUserType ?? "").uppercased()
        let userCollName = (userTypeUpper == "COACH") ? "coaches" : "clients"
        let userRef = db.collection(userCollName).document(uid)

        // Query the root `chats` collection for any chat containing a participantRef equal to the
        // current user's document reference. This ensures the user will see newly-created chats
        // even if the creator didn't (or couldn't) write the per-user pointer document under
        // coaches/{id}/chats or clients/{id}/chats due to security restrictions.
        let query = db.collection("chats").whereField("participantRefs", arrayContains: userRef).order(by: "lastMessageAt", descending: true)

        chatsListener = query.addSnapshotListener { snap, err in
            if let err = err {
                print("listenForChatsForCurrentUser: snapshot error: \(err)")
                DispatchQueue.main.async { self.chatsDebug = "error: \(err.localizedDescription)" }
                return
            }

            let docs = snap?.documents ?? []
            var mapped: [ChatItem] = []
            var otherUidsToResolve: Set<String> = []
            for d in docs {
                let data = d.data()
                let id = d.documentID
                var participantsArr: [String] = []
                if let refs = data["participantRefs"] as? [DocumentReference] {
                    participantsArr = refs.map { $0.documentID }
                } else if let strArr = data["participants"] as? [String] {
                    participantsArr = strArr
                }
                let lastText = data["lastMessageText"] as? String
                let lastAt = (data["lastMessageAt"] as? Timestamp)?.dateValue()
                mapped.append(ChatItem(id: id, participants: participantsArr, lastMessageText: lastText, lastMessageAt: lastAt))

                // collect other participant uids (exclude current user)
                if let currentUid = Auth.auth().currentUser?.uid {
                    for p in participantsArr where p != currentUid {
                        otherUidsToResolve.insert(p)
                    }
                } else {
                    for p in participantsArr { otherUidsToResolve.insert(p) }
                }
            }

            // Resolve participant names for display (async) - will update published participantNames
            if !otherUidsToResolve.isEmpty {
                self.ensureParticipantNames(Array(otherUidsToResolve))
            }

            DispatchQueue.main.async {
                self.chats = mapped
                self.chatsDebug = "Loaded \(mapped.count) chats"
                // Trigger centralized preview cache population for the loaded chats
                let ids = mapped.map { $0.id }
                if !ids.isEmpty { self.loadPreviewsForChats(chatIds: ids) }
            }
        }
    }

    /// Stop listening for chats for current user
    func stopListeningForChats() {
        if let l = chatsListener { l.remove(); chatsListener = nil }
        DispatchQueue.main.async { self.chats = []; self.chatsDebug = "stopped" }
    }

    /// Start listening for messages in the given chatId. Updates `messagesByChat[chatId]` as messages arrive.
    func listenForMessages(chatId: String) {
        // remove existing listener for this chat if present
        if let existing = messageListeners[chatId] {
            existing.remove()
            messageListeners.removeValue(forKey: chatId)
        }

        let coll = db.collection("chats").document(chatId).collection("messages")
        let q = coll.order(by: "createdAt", descending: false)
        print("listenForMessages: adding listener for chatId=\(chatId)")
        let listener = q.addSnapshotListener { snap, err in
            if let err = err {
                print("listenForMessages(\(chatId)) error: \(err)")
                return
            }
            let docs = snap?.documents ?? []
            var msgs: [ChatMessage] = []
            for d in docs {
                let data = d.data()
                let id = d.documentID
                var sender = ""
                if let sRef = data["senderRef"] as? DocumentReference {
                    sender = sRef.documentID
                } else if let s = data["senderId"] as? String {
                    sender = s
                } else if let s = data["sender"] as? String {
                    sender = s
                }
                let text = data["text"] as? String ?? ""
                let date = (data["createdAt"] as? Timestamp)?.dateValue()
                msgs.append(ChatMessage(id: id, senderId: sender, text: text, createdAt: date))
            }
            DispatchQueue.main.async {
                self.messagesByChat[chatId] = msgs
            }
        }

        messageListeners[chatId] = listener
    }

    /// Ensure the provided participant UIDs have display names cached in `participantNames`.
    /// Uses dictionary lookups from in-memory caches first, then batch-fetches remaining UIDs.
    func ensureParticipantNames(_ uids: [String]) {
        let missing = uids.filter { self.participantNames[$0] == nil }
        guard !missing.isEmpty else { return }

        // Build dictionary for O(1) coach lookups instead of linear search per UID
        let coachDict = Dictionary(uniqueKeysWithValues: self.coaches.map { ($0.id, $0.name) })

        var toFetch = Set<String>()
        for uid in missing {
            if let name = coachDict[uid] {
                DispatchQueue.main.async { self.participantNames[uid] = name }
            } else if let cur = self.currentCoach, cur.id == uid {
                DispatchQueue.main.async { self.participantNames[uid] = cur.name }
            } else if let curc = self.currentClient, curc.id == uid {
                DispatchQueue.main.async { self.participantNames[uid] = curc.name }
            } else {
                toFetch.insert(uid)
            }
        }

        guard !toFetch.isEmpty else { return }

        // Helper to chunk arrays into size-limited arrays (Firestore 'in' supports up to 10)
        func chunks<T>(_ arr: [T], size: Int) -> [[T]] {
            guard size > 0 else { return [] }
            var res: [[T]] = []
            var i = 0
            while i < arr.count {
                let end = Swift.min(i + size, arr.count)
                res.append(Array(arr[i..<end]))
                i = end
            }
            return res
        }

        let uidsToFetch = Array(toFetch)
        let uidChunks = chunks(uidsToFetch, size: 10)

        for chunk in uidChunks {
            // 1) query coaches collection for any of these uids
            let coachQuery = db.collection("coaches").whereField(FieldPath.documentID(), in: chunk)
            coachQuery.getDocuments { snap, _ in
                var found: Set<String> = []
                if let docs = snap?.documents {
                    for doc in docs {
                        let id = doc.documentID
                        let data = doc.data()
                        let first = data["FirstName"] as? String ?? ""
                        let last = data["LastName"] as? String ?? ""
                        let name = [first, last].filter { !$0.isEmpty }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
                        DispatchQueue.main.async { self.participantNames[id] = name.isEmpty ? id : name }

                        // cache photo URL for coach if present
                        let photoStr = (data["PhotoURL"] as? String) ?? (data["photoURL"] as? String) ?? (data["photoUrl"] as? String)
                        if let ps = photoStr, !ps.isEmpty {
                            self.resolvePhotoURL(ps) { url in
                                DispatchQueue.main.async { self.coachPhotoURLs[id] = url }
                            }
                        } else {
                            DispatchQueue.main.async { self.coachPhotoURLs[id] = nil }
                        }

                        found.insert(id)
                    }
                }

                // remaining ids in this chunk not found in coaches -> query clients
                let remaining = chunk.filter { !found.contains($0) }
                if remaining.isEmpty {
                    // set any not-returned ids to their uid (fallback) just in case
                    for id in chunk where self.participantNames[id] == nil {
                        DispatchQueue.main.async { self.participantNames[id] = id }
                    }
                    return
                }

                let clientQuery = self.db.collection("clients").whereField(FieldPath.documentID(), in: remaining)
                clientQuery.getDocuments { csnap, _ in
                    var foundClients: Set<String> = []
                    if let cdocs = csnap?.documents {
                        for cdoc in cdocs {
                            let id = cdoc.documentID
                            let cdata = cdoc.data()
                            let name = (cdata["name"] as? String) ?? (cdata["Name"] as? String) ?? id
                            DispatchQueue.main.async { self.participantNames[id] = name }

                            // cache client photo URL if present
                            let photoStr = (cdata["photoURL"] as? String) ?? (cdata["PhotoURL"] as? String) ?? (cdata["photoUrl"] as? String)
                            if let ps = photoStr, !ps.isEmpty {
                                self.resolvePhotoURL(ps) { url in
                                    DispatchQueue.main.async { self.clientPhotoURLs[id] = url }
                                }
                            } else {
                                DispatchQueue.main.async { self.clientPhotoURLs[id] = nil }
                            }

                            foundClients.insert(id)
                        }
                    }

                    // For any ids still not found, set the participant name to the raw uid as fallback
                    for id in remaining where !foundClients.contains(id) {
                        DispatchQueue.main.async { self.participantNames[id] = id }
                    }
                }
            }
        }
    }

    /// Return the best-known photo URL for a participant (coach first, then client).
    func participantPhotoURL(_ uid: String) -> URL? {
        return coachPhotoURLs[uid] ?? clientPhotoURLs[uid] ?? nil
    }

    func stopListeningForMessages(chatId: String) {
        if let l = messageListeners[chatId] { l.remove(); messageListeners.removeValue(forKey: chatId) }
        DispatchQueue.main.async { self.messagesByChat[chatId] = [] }
    }

    func stopAllChatListeners() {
        if let l = chatsListener { l.remove(); chatsListener = nil }
        for (_, l) in messageListeners { l.remove() }
        messageListeners.removeAll()
        // also remove preview listeners
        self.stopAllPreviewListeners()
        DispatchQueue.main.async { self.chats = []; self.messagesByChat = [:]; self.chatsDebug = "stopped" }
    }

    init() {
        // Ensure Firebase is configured before using Firestore
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
            print("[FirestoreManager] FirebaseApp.configure() called from FirestoreManager.init()")
        }
        self.db = Firestore.firestore()

        // Listen for auth state changes and fetch profiles when a user signs in
        self.authStateListenerHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
             guard let self = self else { return }
             if let uid = user?.uid {
                 print("[FirestoreManager] auth state changed - user signed in: \(uid). Fetching profiles.")
                 self.fetchCurrentProfiles(for: uid)
                 // Load userType first, then start chat listener with correct collection reference
                 self.fetchUserType(for: uid) {
                     self.listenForChatsForCurrentUser()
                 }
                 // Fetch user settings
                 self.fetchUserSettings(for: uid)
              } else {
                  // user signed out - clear cached profiles and photo URLs
                  DispatchQueue.main.async {
                      self.currentClient = nil
                      self.currentClientPhotoURL = nil
                      self.currentUserTabImage = nil
                      self.currentCoach = nil
                      self.currentCoachPhotoURL = nil
                      self.currentUserType = nil
                     // stop and clear chat listeners/state
                     self.stopAllChatListeners()
                  }
              }
         }

        // Optionally start listening to coaches collection
        fetchCoaches()
        // Also fetch a lightweight clients list for messaging lookup
        fetchClients()
        // Optionally fetch current user's profile if already signed in
        if let uid = Auth.auth().currentUser?.uid {
            fetchCurrentProfiles(for: uid)
        }

    }

    deinit {
        if let handle = authStateListenerHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    func fetchCoaches() {
        // Skip if already fetching or fetched recently (within 30s)
        if isFetchingCoaches { return }
        if let last = lastCoachesFetchTime, Date().timeIntervalSince(last) < 30 { return }
        isFetchingCoaches = true
        self.db.collection("coaches").getDocuments { snapshot, error in
            DispatchQueue.main.async { self.isFetchingCoaches = false; self.lastCoachesFetchTime = Date() }
            if let error = error {
                print("FirestoreManager: fetchCoaches error: \(error)")
                return
            }
            guard let docs = snapshot?.documents else { return }
            var mapped: [Coach] = []
            for d in docs {
                let data = d.data()
                let id = d.documentID
                let first = data["FirstName"] as? String ?? ""
                let last = data["LastName"] as? String ?? ""
                let name = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
                let specialties = data["Specialties"] as? [String] ?? []
                let experience = data["ExperienceYears"] as? Int ?? (data["ExperienceYears"] as? Double).flatMap { Int($0) } ?? 0
                let availability = data["Availability"] as? [String] ?? []
                let bio = data["Bio"] as? String
                let hourlyRate = data["HourlyRate"] as? Double
                let rateRange = data["RateRange"] as? [Double]

                mapped.append(Coach(id: id, name: name, specialties: specialties, experienceYears: experience, availability: availability, bio: bio, hourlyRate: hourlyRate, rateRange: rateRange))

                // resolve coach photo if provided and cache into coachPhotoURLs
                let photoStr = (data["PhotoURL"] as? String) ?? (data["photoURL"] as? String) ?? (data["photoUrl"] as? String)
                if let p = photoStr, !p.isEmpty {
                    self.resolvePhotoURL(p) { resolved in
                        DispatchQueue.main.async {
                            self.coachPhotoURLs[id] = resolved
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        self.coachPhotoURLs[id] = nil
                    }
                }
            }

            DispatchQueue.main.async {
                self.coaches = mapped
            }
        }
    }

    func fetchClients() {
        self.db.collection("clients").getDocuments { snap, err in
            if let err = err {
                print("fetchClients error: \(err)")
                return
            }
            let docs = snap?.documents ?? []
            var results: [UserSummary] = []
            for d in docs {
                let data = d.data()
                let id = d.documentID
                // Prefer explicit name field; otherwise build from FirstName/LastName
                var nameVal: String = ""
                if let n = data["name"] as? String { nameVal = n }
                else if let n = data["Name"] as? String { nameVal = n }
                else {
                    let first = (data["FirstName"] as? String) ?? (data["firstName"] as? String) ?? ""
                    let last = (data["LastName"] as? String) ?? (data["lastName"] as? String) ?? ""
                    nameVal = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
                }
                // resolve photo URL if present
                let photoStr = (data["photoURL"] as? String) ?? (data["PhotoURL"] as? String) ?? (data["photoUrl"] as? String)
                if let ps = photoStr, !ps.isEmpty {
                    self.resolvePhotoURL(ps) { url in
                        DispatchQueue.main.async {
                            results.append(UserSummary(id: id, name: nameVal.isEmpty ? id : nameVal, photoURL: url))
                            // after processing all docs we'll assign below; but assign incrementally for responsiveness
                            self.clients = results.sorted { $0.name.lowercased() < $1.name.lowercased() }
                        }
                    }
                } else {
                    results.append(UserSummary(id: id, name: nameVal.isEmpty ? id : nameVal, photoURL: nil))
                    DispatchQueue.main.async {
                        self.clients = results.sorted { $0.name.lowercased() < $1.name.lowercased() }
                    }
                }
            }
        }
    }

    func fetchCurrentProfiles(for uid: String) {
        // Fetch client document and resolve photo URL
        let clientRef = self.db.collection("clients").document(uid)
        clientRef.getDocument { snap, err in
            if let err = err {
                print("fetchCurrentProfiles client err: \(err)")
            }
            guard let data = snap?.data() else {
                DispatchQueue.main.async {
                    self.currentClient = nil
                    self.currentClientPhotoURL = nil
                }
                return
            }

            let id = snap?.documentID ?? uid
            let name = data["name"] as? String ?? ""
            let goals = data["goals"] as? [String] ?? []
            var preferredArr: [String]
            if let arr = data["preferredAvailability"] as? [String] {
                preferredArr = arr
            } else if let s = data["preferredAvailability"] as? String {
                preferredArr = [s]
            } else {
                preferredArr = ["Morning"]
            }

            // Read meeting preference and location if present
            let meetingPref = data["meetingPreference"] as? String
            let zip = data["zipCode"] as? String ?? data["ZipCode"] as? String
            let city = data["city"] as? String ?? data["City"] as? String
            let bio = data["bio"] as? String

            let photoStr = (data["photoURL"] as? String) ?? (data["PhotoURL"] as? String)
            self.resolvePhotoURL(photoStr) { resolved in
                DispatchQueue.main.async {
                    self.currentClient = Client(id: id, name: name, goals: goals, preferredAvailability: preferredArr, meetingPreference: meetingPref, skillLevel: data["skillLevel"] as? String, zipCode: zip, city: city, bio: bio)
                    self.currentClientPhotoURL = resolved
                    if let r = resolved {
                        print("fetchCurrentProfiles: client photo resolved for \(id): \(r.absoluteString)")
                        self.fetchAndCacheTabImage(from: r)
                    } else {
                        print("fetchCurrentProfiles: no client photo for \(id)")
                        self.currentUserTabImage = nil
                    }
                }
            }
        }

        // Fetch coach document and resolve photo URL
        let coachRef = self.db.collection("coaches").document(uid)
        coachRef.getDocument { snap, err in
            if let err = self.handleFirestoreError(err) {
                print("fetchCurrentProfiles coach err: \(err)")
            }
            guard let data = snap?.data() else {
                DispatchQueue.main.async {
                    self.currentCoach = nil
                    self.currentCoachPhotoURL = nil
                }
                return
            }

            let id = snap?.documentID ?? uid
            let first = data["FirstName"] as? String ?? ""
            let last = data["LastName"] as? String ?? ""
            let name = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
            let specialties = data["Specialties"] as? [String] ?? []
            let experience = data["ExperienceYears"] as? Int ?? (data["ExperienceYears"] as? Double).flatMap { Int($0) } ?? 0
            let availability = data["Availability"] as? [String] ?? []
            let bio = data["Bio"] as? String
            let meetingPref = data["meetingPreference"] as? String
            let hourlyRate = data["HourlyRate"] as? Double
            let rateRange = data["RateRange"] as? [Double]

            let photoStr = (data["PhotoURL"] as? String) ?? (data["photoUrl"] as? String) ?? (data["photoURL"] as? String)
            self.resolvePhotoURL(photoStr) { resolved in
                DispatchQueue.main.async {
                    var paymentsMap: [String: String]? = nil
                    if let pm = data["payments"] as? [String: String] {
                        paymentsMap = pm
                    } else if let anyMap = data["payments"] as? [String: Any] {
                        var tmp: [String: String] = [:]
                        for (k, v) in anyMap { if let s = v as? String { tmp[k] = s } }
                        paymentsMap = tmp.isEmpty ? nil : tmp
                    }

                    self.currentCoach = Coach(id: id, name: name, specialties: specialties, experienceYears: experience, availability: availability, bio: bio, hourlyRate: hourlyRate, meetingPreference: meetingPref, payments: paymentsMap, rateRange: rateRange)
                    self.currentCoachPhotoURL = resolved
                    if let r = resolved {
                        print("fetchCurrentProfiles: coach photo resolved for \(id): \(r.absoluteString)")
                        self.fetchAndCacheTabImage(from: r)
                    } else {
                        print("fetchCurrentProfiles: no coach photo for \(id)")
                        self.currentUserTabImage = nil
                    }
                }
            }
        }
    }

    // Resolve a photo string (could be https URL, gs:// storage URL or plain storage path) into a downloadable https URL.
    // Calls completion on background thread; completion may be called synchronously for simple URLs.
    func resolvePhotoURL(_ photoStr: String?, completion: @escaping (URL?) -> Void) {
        guard let s = photoStr, !s.isEmpty else { completion(nil); return }

        // If it already looks like an http/https URL, pass through
        if s.hasPrefix("http://") || s.hasPrefix("https://") {
            completion(URL(string: s))
            return
        }

        // If it's a storage gs:// URL
        if s.hasPrefix("gs://") {
            // try to get download URL from storage
            let ref = Storage.storage().reference(forURL: s)
            ref.downloadURL { url, err in
                if let err = err { print("resolvePhotoURL: failed to downloadURL for gs:// path: \(err)"); completion(nil); return }
                completion(url)
            }
            return
        }

        // Otherwise, treat as a storage path; strip leading slashes
        var path = s
        if path.hasPrefix("/") { path.removeFirst() }

        // Create a reference for the path
        let ref = Storage.storage().reference().child(path)
        ref.downloadURL { url, err in
            if let err = err {
                print("resolvePhotoURL: failed to downloadURL for path \(path): \(err)")
                completion(nil)
                return
            }
            completion(url)
        }
    }

    // Download a small cached UIImage for the tab bar from a resolved URL and store it in `currentUserTabImage`.
    // Runs asynchronously and resizes the image to roughly 44x44 points (screen scale aware).
    func fetchAndCacheTabImage(from url: URL) {
        Task.detached { @MainActor in
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let image = UIImage(data: data) {
                    // Resize to 44x44 points at device scale to keep memory low and match UI
                    let targetPoints: CGFloat = 44.0
                    let scale = UIScreen.main.scale
                    let targetPx = CGSize(width: targetPoints * scale, height: targetPoints * scale)
                    let renderer = UIGraphicsImageRenderer(size: targetPx)
                    let resized = renderer.image { _ in
                        image.draw(in: CGRect(origin: .zero, size: targetPx))
                    }
                    self.currentUserTabImage = resized
                } else {
                    self.currentUserTabImage = nil
                }
            } catch {
                print("fetchAndCacheTabImage: failed to download image for tab: \(error) - url=\(url.absoluteString)")
                self.currentUserTabImage = nil
            }
        }
    }

    // Save client document using provided id
    func saveClient(id: String, name: String, goals: [String], preferredAvailability: [String], meetingPreference: String? = nil, meetingPreferenceClear: Bool = false, skillLevel: String? = nil, zipCode: String? = nil, city: String? = nil, bio: String? = nil, photoURL: String?, completion: @escaping (Error?) -> Void) {
        let docRef = self.db.collection("clients").document(id)

        // Base payload for updates (always set updatedAt)
        var updateData: [String: Any] = [
            "name": name,
            "goals": goals,
            "preferredAvailability": preferredAvailability,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let p = photoURL { updateData["photoURL"] = p }
        if let z = zipCode { updateData["zipCode"] = z }
        if let c = city { updateData["city"] = c }
        if let b = bio { updateData["bio"] = b }
        // If caller asked to clear the meetingPreference, request deletion in a merge/update operation
        if meetingPreferenceClear {
            updateData["meetingPreference"] = FieldValue.delete()
        } else if let mp = meetingPreference {
            updateData["meetingPreference"] = mp
        }
        // skillLevel handling: if provided as nil we don't touch it; if non-nil (including empty) we set it; caller can pass nil to leave unchanged
        if let sl = skillLevel {
            updateData["skillLevel"] = sl
        }

        // Check whether the document exists so we only set createdAt on creation
        docRef.getDocument { snap, err in
            if let err = err {
                // Best-effort: if we can't determine existence, include createdAt so newly-created docs have the field.
                print("saveClient: getDocument error: \(err). Proceeding to write with createdAt as a best-effort.")
                var data = updateData
                data["createdAt"] = FieldValue.serverTimestamp()
                docRef.setData(data, merge: true, completion: completion)
                return
            }

            if let exists = snap?.exists, exists {
                // Document already exists — only update mutable fields (don't touch createdAt)
                docRef.setData(updateData, merge: true, completion: completion)
            } else {
                // Document does not exist — include createdAt timestamps when creating
                var data = updateData
                data["createdAt"] = FieldValue.serverTimestamp()
                // Create the document (no merge necessary) so createdAt is set once
                docRef.setData(data, completion: completion)
            }
        }
    }

    // Save coach with the provided schema to "coaches" collection under document id
    func saveCoachWithSchema(id: String, firstName: String, lastName: String, specialties: [String], availability: [String], experienceYears: Int, hourlyRate: Double?, meetingPreference: String? = nil, photoURL: String?, bio: String? = nil, zipCode: String? = nil, city: String? = nil, active: Bool = true, overwrite: Bool = false, completion: @escaping (Error?) -> Void) {
        // Base payload (do not include createdAt here yet so we can control whether it is written)
        var baseData: [String: Any] = [
            "FirstName": firstName,
            "LastName": lastName,
            "Specialties": specialties,
            "Availability": availability,
            "ExperienceYears": experienceYears,
            "Active": active
        ]
        if let hr = hourlyRate { baseData["HourlyRate"] = hr }
        if let p = photoURL { baseData["PhotoURL"] = p }
        if let b = bio { baseData["Bio"] = b }
        if let z = zipCode { baseData["ZipCode"] = z }
        if let c = city { baseData["City"] = c }
        if let mp = meetingPreference { baseData["meetingPreference"] = mp }

        let docRef = self.db.collection("coaches").document(id)

        if overwrite {
            // Overwrite intent: treat as a fresh write and set createdAt to server timestamp
            var dataToWrite = baseData
            dataToWrite["createdAt"] = FieldValue.serverTimestamp()
            docRef.setData(dataToWrite, completion: completion)
            return
        }

        // Non-overwrite (merge) case: check existence to avoid overwriting createdAt
        docRef.getDocument { snap, err in
            if let err = err {
                // If we can't determine existence, proceed with a merge that includes createdAt as a best-effort.
                print("saveCoachWithSchema: getDocument error: \(err). Proceeding to merge with createdAt as a best-effort.")
                var data = baseData
                data["createdAt"] = FieldValue.serverTimestamp()
                docRef.setData(data, merge: true, completion: completion)
                return
            }

            if let exists = snap?.exists, exists {
                // Document exists: merge update but DON'T overwrite createdAt
                docRef.setData(baseData, merge: true, completion: completion)
            } else {
                // Document does not exist: include createdAt when creating
                var data = baseData
                data["createdAt"] = FieldValue.serverTimestamp()
                docRef.setData(data, completion: completion)
            }
        }
    }

    // Save a review document to "reviews" collection
    func saveReview(clientID: String, coachID: String, rating: String, ratingMessage: String, completion: @escaping (Error?) -> Void) {
        let data: [String: Any] = [
            "ClientID": clientID,
            "CoachID": coachID,
            "createdAt": FieldValue.serverTimestamp(),
            "Rating": rating,
            "RatingMessage": ratingMessage
        ]
        self.db.collection("reviews").addDocument(data: data, completion: completion)
    }

    /// Fetch bookings where the ClientID reference points to the currently signed-in user's client document.
    func fetchBookingsForCurrentUser() {
        DispatchQueue.main.async { self.bookingsDebug = "Starting bookings fetch..." }
        guard let uid = Auth.auth().currentUser?.uid else {
            print("fetchBookingsForCurrentUser: no authenticated user")
            DispatchQueue.main.async {
                self.bookings = []
                self.bookingsDebug = "No authenticated user"
            }
            return
        }

        DispatchQueue.main.async { self.bookingsDebug = "Querying bookings for uid=\(uid) by fetching all bookings and filtering locally" }

        // capture a local reference to avoid implicit self capture inside the closure
        let bookingsColl = self.db.collection("bookings")
        bookingsColl.getDocuments { snapshot, error in
            if let error = error {
                let msg = "fetchBookingsForCurrentUser: failed to list bookings: \(error.localizedDescription)"
                print(msg)
                DispatchQueue.main.async { self.bookingsDebug += "\n\(msg)" }
                return
            }

            let docs = snapshot?.documents ?? []
            DispatchQueue.main.async { self.bookingsDebug += "\nfetchAll returned \(docs.count) docs" }

            // Filter locally for documents that match the current user's uid in their ClientID field
            var matchingDocs: [QueryDocumentSnapshot] = []
            for doc in docs {
                let data = doc.data()
                let clientField = data["ClientID"]

                var extractedClientID: String? = nil
                if let ref = clientField as? DocumentReference {
                    extractedClientID = ref.documentID
                } else if let s = clientField as? String {
                    // try raw uid, path-like values, or trailing component
                    if s == uid {
                        extractedClientID = uid
                    } else {
                        let last = s.split(separator: "/").last.map(String.init) ?? s
                        if last == uid { extractedClientID = uid } else { extractedClientID = last }
                    }
                } else if let dict = clientField as? [String: Any] {
                    // sometimes clients are stored as maps with an 'id' key
                    if let id = dict["id"] as? String { extractedClientID = id }
                    else if let refPath = dict["path"] as? String { extractedClientID = refPath.split(separator: "/").last.map(String.init) }
                }

                if extractedClientID == uid {
                    matchingDocs.append(doc)
                }
            }

            DispatchQueue.main.async { self.bookingsDebug += "\nmatchingDocs count=\(matchingDocs.count)" }

            if matchingDocs.isEmpty {
                let msg = "fetchBookingsForCurrentUser: no bookings found for uid=\(uid) after local filtering"
                print(msg)
                DispatchQueue.main.async {
                    self.bookings = []
                    self.bookingsDebug += "\n\(msg)"
                }
                return
            }

            // Resolve names/references for matched docs
            var results: [BookingItem] = []
            let group = DispatchGroup()

            for doc in matchingDocs {
                group.enter()
                let data = doc.data()
                var clientID = ""
                var coachID = ""
                var clientName: String? = nil
                var coachName: String? = nil

                // client id handling
                if let clientReference = data["ClientID"] as? DocumentReference {
                    clientID = clientReference.documentID
                    clientReference.getDocument { cSnap, _ in
                        if let cdata = cSnap?.data() {
                            clientName = (cdata["name"] as? String) ?? (cdata["FirstName"] as? String).map { fn in
                                let ln = (cdata["LastName"] as? String) ?? ""
                                return ln.isEmpty ? fn : "\(fn) \(ln)"
                            }
                        }
                        // continue to coach resolution below via nested logic
                        // we don't leave the group here because we still need to resolve coach
                        // so call a helper function after we attempt to resolve coach as well
                        if let coachReference = data["CoachID"] as? DocumentReference {
                            coachID = coachReference.documentID
                            coachReference.getDocument { sSnap, _ in
                                if let sdata = sSnap?.data() {
                                    coachName = ((sdata["FirstName"] as? String) ?? "")
                                    if let last = sdata["LastName"] as? String, !last.isEmpty {
                                        coachName = ((coachName ?? "") + " " + last).trimmingCharacters(in: .whitespaces)
                                    }
                                }
                                // build item now
                                let startAt = (data["StartAt"] as? Timestamp)?.dateValue()
                                let endAt = (data["EndAt"] as? Timestamp)?.dateValue()
                                let location = data["Location"] as? String
                                let notes = data["Notes"] as? String
                                let status = data["Status"] as? String
                                let paymentStatus = data["PaymentStatus"] as? String
                                let rate = (data["RateUSD"] as? Double) ?? ((data["RateUSD"] as? Int).map { Double($0) })
                                let item = BookingItem(id: doc.documentID, clientID: clientID, clientName: clientName, coachID: coachID, coachName: coachName, startAt: startAt, endAt: endAt, location: location, notes: notes, status: status, paymentStatus: paymentStatus, RateUSD: rate)
                                results.append(item)
                                group.leave()
                            }
                        } else {
                            // coach might be string
                            if let coachStr = data["CoachID"] as? String { coachID = coachStr.split(separator: "/").last.map(String.init) ?? coachID }
                            let startAt = (data["StartAt"] as? Timestamp)?.dateValue()
                            let endAt = (data["EndAt"] as? Timestamp)?.dateValue()
                            let location = data["Location"] as? String
                            let notes = data["Notes"] as? String
                            let status = data["Status"] as? String
                            let paymentStatus = data["PaymentStatus"] as? String
                            let rate = (data["RateUSD"] as? Double) ?? ((data["RateUSD"] as? Int).map { Double($0) })
                            let item = BookingItem(id: doc.documentID, clientID: clientID, clientName: clientName, coachID: coachID, coachName: coachName, startAt: startAt, endAt: endAt, location: location, notes: notes, status: status, paymentStatus: paymentStatus, RateUSD: rate)
                            results.append(item)
                            group.leave()
                        }
                    }
                } else {
                    // client is not a reference; try string/path
                    if let clientStr = data["ClientID"] as? String {
                        clientID = clientStr.split(separator: "/").last.map(String.init) ?? clientStr
                    }

                    if let coachReference = data["CoachID"] as? DocumentReference {
                        coachID = coachReference.documentID
                        group.enter()
                        coachReference.getDocument { sSnap, _ in
                            if let sdata = sSnap?.data() {
                                coachName = ((sdata["FirstName"] as? String) ?? "")
                                if let last = sdata["LastName"] as? String, !last.isEmpty {
                                    coachName = ((coachName ?? "") + " " + last).trimmingCharacters(in: .whitespaces)
                                }
                            }
                            let startAt = (data["StartAt"] as? Timestamp)?.dateValue()
                            let endAt = (data["EndAt"] as? Timestamp)?.dateValue()
                            let location = data["Location"] as? String
                            let notes = data["Notes"] as? String
                            let status = data["Status"] as? String
                            let paymentStatus = data["PaymentStatus"] as? String
                            let rate = (data["RateUSD"] as? Double) ?? ((data["RateUSD"] as? Int).map { Double($0) })
                            let item = BookingItem(id: doc.documentID, clientID: clientID, clientName: clientName, coachID: coachID, coachName: coachName, startAt: startAt, endAt: endAt, location: location, notes: notes, status: status, paymentStatus: paymentStatus, RateUSD: rate)
                            results.append(item)
                            group.leave()
                        }
                    } else {
                        // neither client nor coach are references; just collect fields
                        if let coachStr = data["CoachID"] as? String { coachID = coachStr.split(separator: "/").last.map(String.init) ?? coachStr }
                        let startAt = (data["StartAt"] as? Timestamp)?.dateValue()
                        let endAt = (data["EndAt"] as? Timestamp)?.dateValue()
                        let location = data["Location"] as? String
                        let notes = data["Notes"] as? String
                        let status = data["Status"] as? String
                        let paymentStatus = data["PaymentStatus"] as? String
                        let rate = (data["RateUSD"] as? Double) ?? ((data["RateUSD"] as? Int).map { Double($0) })
                        let item = BookingItem(id: doc.documentID, clientID: clientID, clientName: clientName, coachID: coachID, coachName: coachName, startAt: startAt, endAt: endAt, location: location, notes: notes, status: status, paymentStatus: paymentStatus, RateUSD: rate)
                        results.append(item)
                        group.leave()
                    }
                }
            }

            group.notify(queue: .main) {
                // sort by startAt descending
                let sorted = results.sorted { (a,b) in
                    (a.startAt ?? Date.distantPast) > (b.startAt ?? Date.distantPast)
                }
                self.bookings = sorted
                self.bookingsDebug += "\nAssigned \(sorted.count) bookings to published list"
            }
        }
    }

    /// Debug helper: create a sample booking and verify mirrored docs exist; prints results to console.
    func debugCreateAndVerifyBooking(coachId: String, clientId: String) {
        let start = Date()
        let end = start.addingTimeInterval(30 * 60)
        saveBookingAndMirror(coachId: coachId, clientId: clientId, startAt: start, endAt: end, status: "requested", location: "Debug Location", notes: "Debug booking") { err in
            if let err = err {
                print("[FirestoreManager] debugCreateAndVerifyBooking: saveBookingAndMirror failed: \(err)")
            } else {
                print("[FirestoreManager] debugCreateAndVerifyBooking: booking created and docs verified (see above)")
            }
        }
    }

    /// Remove legacy booking arrays from parent documents.
    /// Deletes the `calendar` field on every coach and the `bookings` field on every client.
    /// Works in batched chunks to avoid exceeding the 500-operation per-batch limit.
    func removeBookingArraysFromParents(completion: @escaping (Error?) -> Void) {
        let coachColl = self.db.collection("coaches")
        let clientColl = self.db.collection("clients")

        let group = DispatchGroup()
        var firstError: Error? = nil

        func processDocs(_ docs: [QueryDocumentSnapshot], fieldName: String, collectionName: String, finish: @escaping () -> Void) {
            // Partition into batches of 450 updates to be safe
            let batchSize = 450
            var index = 0
            while index < docs.count {
                let end = min(index + batchSize, docs.count)
                let batch = self.db.batch()
                for i in index..<end {
                    let docRef = docs[i].reference
                    // Only issue delete if the field exists in the snapshot
                    if docs[i].data()[fieldName] != nil {
                        batch.updateData([fieldName: FieldValue.delete()], forDocument: docRef)
                    }
                }
                group.enter()
                batch.commit { err in
                    if let err = err {
                        print("removeBookingArraysFromParents commit error for \(collectionName): \(err)")
                        if firstError == nil { firstError = err }
                    }
                    group.leave()
                }
                index = end
            }
            // if there were zero docs or no updates, still call finish after group completes
            finish()
        }

        // Fetch coaches
        group.enter()
        coachColl.getDocuments { snap, err in
            if let err = err {
                print("removeBookingArraysFromParents: failed to list coaches: \(err)")
                if firstError == nil { firstError = err }
                group.leave()
            } else {
                let docs = snap?.documents ?? []
                // Process and schedule commits
                processDocs(docs, fieldName: "calendar", collectionName: "coaches") {
                    group.leave()
                }
            }
        }

        // Fetch clients
        group.enter()
        clientColl.getDocuments { snap, err in
            if let err = err {
                print("removeBookingArraysFromParents: failed to list clients: \(err)")
                if firstError == nil { firstError = err }
                group.leave()
            } else {
                let docs = snap?.documents ?? []
                processDocs(docs, fieldName: "bookings", collectionName: "clients") {
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            completion(firstError)
        }
    }

    /// Fetch bookings mirrored under a coach's `bookings` subcollection within an optional date range.
    func fetchBookingsForCoach(coachId: String, start: Date? = nil, end: Date? = nil, completion: @escaping ([BookingItem]) -> Void) {
        var query: Query = db.collection("coaches").document(coachId).collection("bookings")
        if let s = start { query = query.whereField("StartAt", isGreaterThanOrEqualTo: Timestamp(date: s)) }
        if let e = end { query = query.whereField("StartAt", isLessThan: Timestamp(date: e)) }
        query.getDocuments { snapshot, error in
            if let error = error { print("fetchBookingsForCoach error: \(error)"); completion([]); return }
            let docs = snapshot?.documents ?? []
            let items = docs.map { d -> BookingItem in
                let data = d.data()
                let id = d.documentID
                let clientID = (data["ClientID"] as? DocumentReference)?.documentID ?? (data["ClientID"] as? String ?? "")
                let startAt = (data["StartAt"] as? Timestamp)?.dateValue()
                let endAt = (data["EndAt"] as? Timestamp)?.dateValue()
                let status = data["Status"] as? String
                let location = data["Location"] as? String
                let notes = data["Notes"] as? String
                let paymentStatus = data["PaymentStatus"] as? String
                let rate = (data["RateUSD"] as? Double) ?? ((data["RateUSD"] as? Int).map { Double($0) })
                // Prefer denormalized coach name stored on booking doc
                let coachName = (data["CoachName"] as? String)
                    ?? (data["coachName"] as? String)
                    ?? (data["coach_name"] as? String)
                return BookingItem(id: id, clientID: clientID, clientName: nil, coachID: coachId, coachName: coachName, startAt: startAt, endAt: endAt, location: location, notes: notes, status: status, paymentStatus: paymentStatus, RateUSD: rate)
            }
            completion(items)
        }
    }

    /// Fetch bookings mirrored under a client's `bookings` subcollection.
    func fetchBookingsForClient(clientId: String, completion: @escaping ([BookingItem]) -> Void) {
        let coll = db.collection("clients").document(clientId).collection("bookings")
        coll.getDocuments { snapshot, error in
            if let error = error { print("fetchBookingsForClient error: \(error)"); completion([]); return }
            let docs = snapshot?.documents ?? []
            let items = docs.map { d -> BookingItem in
                let data = d.data()
                let id = d.documentID
                let coachID = (data["CoachID"] as? DocumentReference)?.documentID ?? (data["CoachID"] as? String ?? "")
                let startAt = (data["StartAt"] as? Timestamp)?.dateValue()
                let endAt = (data["EndAt"] as? Timestamp)?.dateValue()
                let status = data["Status"] as? String
                let location = data["Location"] as? String
                let notes = data["Notes"] as? String
                let paymentStatus = data["PaymentStatus"] as? String
                let rate = (data["RateUSD"] as? Double) ?? ((data["RateUSD"] as? Int).map { Double($0) })
                // Prefer denormalized coach name stored on booking doc
                let coachName = (data["CoachName"] as? String)
                    ?? (data["coachName"] as? String)
                    ?? (data["coach_name"] as? String)
                return BookingItem(id: id, clientID: clientId, clientName: nil, coachID: coachID, coachName: coachName, startAt: startAt, endAt: endAt, location: location, notes: notes, status: status, paymentStatus: paymentStatus, RateUSD: rate)
            }
            completion(items)
        }
    }

    /// Count bookings for a client (reads the client's bookings subcollection)
    func countBookingsForClient(clientId: String, completion: @escaping (Int?, Error?) -> Void) {
        let coll = db.collection("clients").document(clientId).collection("bookings")
        coll.getDocuments { snapshot, error in
            if let error = error { completion(nil, error); return }
            completion(snapshot?.documents.count ?? 0, nil)
        }
    }

    /// Fetch all reviews from the `reviews` collection and resolve client/coach names when possible.
    func fetchAllReviews() {
        DispatchQueue.main.async { self.reviewsDebug = "Starting fetchAllReviews..." }
        let reviewsColl = self.db.collection("reviews")
        reviewsColl.getDocuments { snapshot, error in
            if let error = error {
                let msg = "fetchAllReviews error: \(error.localizedDescription)"
                print(msg)
                DispatchQueue.main.async { self.reviewsDebug += "\n\(msg)" }
                return
            }
            let docs = snapshot?.documents ?? []
            let header = "fetchAllReviews: total=\(docs.count)"
            print(header)
            DispatchQueue.main.async { self.reviewsDebug += "\n\(header)" }

            var results: [ReviewItem] = []
            let group = DispatchGroup()

            for doc in docs {
                group.enter()
                let data = doc.data()
                var clientID = ""
                var coachID = ""
                var clientName: String? = nil
                var coachName: String? = nil
                let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()

                // rating may be stored as number or string
                var ratingStr: String? = nil
                if let r = data["Rating"] as? String { ratingStr = r }
                else if let r = data["Rating"] as? Int { ratingStr = String(r) }
                else if let r = data["Rating"] as? Double { ratingStr = String(Int(r)) }

                let ratingMessage = data["RatingMessage"] as? String

                let inner = DispatchGroup()

                // Client resolution
                if let clientRef = data["ClientID"] as? DocumentReference {
                    clientID = clientRef.documentID
                    inner.enter()
                    clientRef.getDocument { sSnap, _ in
                        if let sdata = sSnap?.data() {
                            clientName = (sdata["name"] as? String) ?? ([sdata["FirstName"] as? String, sdata["LastName"] as? String].compactMap { $0 }.joined(separator: " ")).trimmingCharacters(in: .whitespaces)
                        }
                        inner.leave()
                    }
                } else if let s = data["ClientID"] as? String {
                    clientID = s.split(separator: "/").last.map(String.init) ?? s
                    // fallback to direct client lookup
                    inner.enter()
                    self.db.collection("clients").document(clientID).getDocument { sSnap, _ in
                        if let sdata = sSnap?.data() {
                            clientName = sdata["name"] as? String
                        }
                        inner.leave()
                    }
                }

                // Coach resolution
                if let coachRef = data["CoachID"] as? DocumentReference {
                    coachID = coachRef.documentID
                    inner.enter()
                    coachRef.getDocument { sSnap, _ in
                        if let sdata = sSnap?.data() {
                            coachName = ([sdata["FirstName"] as? String, sdata["LastName"] as? String].compactMap { $0 }.joined(separator: " ")).trimmingCharacters(in: .whitespaces)
                        }
                        inner.leave()
                    }
                } else if let s = data["CoachID"] as? String {
                    coachID = s.split(separator: "/").last.map(String.init) ?? s
                    inner.enter()
                    self.db.collection("coaches").document(coachID).getDocument { sSnap, _ in
                        if let sdata = sSnap?.data() {
                            coachName = ([sdata["FirstName"] as? String, sdata["LastName"] as? String].compactMap { $0 }.joined(separator: " ")).trimmingCharacters(in: .whitespaces)
                        }
                        inner.leave()
                    }
                }

                // finalize after any async lookups
                inner.notify(queue: .main) {
                    let item = ReviewItem(id: doc.documentID, clientID: clientID, clientName: clientName, coachID: coachID, coachName: coachName, createdAt: createdAt, rating: ratingStr, ratingMessage: ratingMessage)
                    results.append(item)
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                let sorted = results.sorted { (a,b) in
                    (a.createdAt ?? Date.distantPast) > (b.createdAt ?? Date.distantPast)
                }
                self.reviews = sorted
                self.reviewsDebug += "\nAssigned \(sorted.count) reviews to published list"
            }
        }
    }

    /// Fetch reviews for a single coach by coach document id. Tolerant to CoachID stored as DocumentReference or String.
    func fetchReviewsForCoach(coachId: String, completion: @escaping ([ReviewItem]) -> Void) {
        let reviewsColl = self.db.collection("reviews")
        reviewsColl.getDocuments { snapshot, error in
            if let error = error {
                print("fetchReviewsForCoach error: \(error)")
                completion([])
                return
            }

            let docs = snapshot?.documents ?? []
            let matching = docs.filter { doc -> Bool in
                let data = doc.data()
                if let ref = data["CoachID"] as? DocumentReference {
                    return ref.documentID == coachId
                }
                if let s = data["CoachID"] as? String {
                    let last = s.split(separator: "/").last.map(String.init) ?? s
                    return last == coachId || s == "coaches/\(coachId)" || s == "/coaches/\(coachId)"
                }
                return false
            }

            var results: [ReviewItem] = []
            let group = DispatchGroup()

            for doc in matching {
                group.enter()
                let data = doc.data()
                var clientID = ""
                var clientName: String? = nil
                let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()

                // rating may be stored as number or string
                var ratingStr: String? = nil
                if let r = data["Rating"] as? String { ratingStr = r }
                else if let r = data["Rating"] as? Int { ratingStr = String(r) }
                else if let r = data["Rating"] as? Double { ratingStr = String(Int(r)) }

                let ratingMessage = data["RatingMessage"] as? String

                if let clientRef = data["ClientID"] as? DocumentReference {
                    clientID = clientRef.documentID
                    clientRef.getDocument { sSnap, _ in
                        if let sdata = sSnap?.data() {
                            clientName = (sdata["name"] as? String) ?? ([sdata["FirstName"] as? String, sdata["LastName"] as? String].compactMap { $0 }.joined(separator: " ")).trimmingCharacters(in: .whitespaces)
                        }
                        let item = ReviewItem(id: doc.documentID, clientID: clientID, clientName: clientName, coachID: coachId, coachName: nil, createdAt: createdAt, rating: ratingStr, ratingMessage: ratingMessage)
                        results.append(item)
                        group.leave()
                    }
                } else if let s = data["ClientID"] as? String {
                    clientID = s.split(separator: "/").last.map(String.init) ?? s
                    // try to fetch client doc to get name
                    self.db.collection("clients").document(clientID).getDocument { sSnap, _ in
                        if let sdata = sSnap?.data() {
                            clientName = sdata["name"] as? String
                        }
                        let item = ReviewItem(id: doc.documentID, clientID: clientID, clientName: clientName, coachID: coachId, coachName: nil, createdAt: createdAt, rating: ratingStr, ratingMessage: ratingMessage)
                        results.append(item)
                        group.leave()
                    }
                } else {
                    let item = ReviewItem(id: doc.documentID, clientID: "", clientName: nil, coachID: coachId, coachName: nil, createdAt: createdAt, rating: ratingStr, ratingMessage: ratingMessage)
                    results.append(item)
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                let sorted = results.sorted { (a,b) in
                    (a.createdAt ?? Date.distantPast) > (b.createdAt ?? Date.distantPast)
                }
                completion(sorted)
            }
        }
    }

    // Fetch reviews written by a specific client (by client document id). Handles ClientID stored as DocumentReference or String.
    func fetchReviewsByClient(clientId: String, completion: @escaping ([ReviewItem]) -> Void) {
        let reviewsColl = self.db.collection("reviews")
        reviewsColl.getDocuments { snapshot, error in
            if let error = error {
                print("fetchReviewsByClient error: \(error)")
                completion([])
                return
            }

            let docs = snapshot?.documents ?? []
            let matching = docs.filter { doc -> Bool in
                let data = doc.data()
                if let ref = data["ClientID"] as? DocumentReference {
                    return ref.documentID == clientId
                }
                if let s = data["ClientID"] as? String {
                    let last = s.split(separator: "/").last.map(String.init) ?? s
                    return last == clientId || s == "clients/\(clientId)" || s == "/clients/\(clientId)"
                }
                return false
            }

            var results: [ReviewItem] = []
            let group = DispatchGroup()

            for doc in matching {
                group.enter()
                let data = doc.data()
                var coachID: String = ""
                var coachName: String? = nil
                let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()

                // rating may be stored as number or string
                var ratingStr: String? = nil
                if let r = data["Rating"] as? String { ratingStr = r }
                else if let r = data["Rating"] as? Int { ratingStr = String(r) }
                else if let r = data["Rating"] as? Double { ratingStr = String(Int(r)) }

                let ratingMessage = data["RatingMessage"] as? String

                if let coachRef = data["CoachID"] as? DocumentReference {
                    coachID = coachRef.documentID
                    coachRef.getDocument { sSnap, _ in
                        if let sdata = sSnap?.data() {
                            coachName = ([sdata["FirstName"] as? String, sdata["LastName"] as? String].compactMap { $0 }.joined(separator: " ")).trimmingCharacters(in: .whitespaces)
                        }
                        let item = ReviewItem(id: doc.documentID, clientID: clientId, clientName: nil, coachID: coachID, coachName: coachName, createdAt: createdAt, rating: ratingStr, ratingMessage: ratingMessage)
                        results.append(item)
                        group.leave()
                    }
                } else if let s = data["CoachID"] as? String {
                    coachID = s.split(separator: "/").last.map(String.init) ?? s
                    coachName = coachID
                    let item = ReviewItem(id: doc.documentID, clientID: clientId, clientName: nil, coachID: coachID, coachName: coachName, createdAt: createdAt, rating: ratingStr, ratingMessage: ratingMessage)
                    results.append(item)
                    group.leave()
                } else {
                    let item = ReviewItem(id: doc.documentID, clientID: clientId, clientName: nil, coachID: coachID, coachName: nil, createdAt: createdAt, rating: ratingStr, ratingMessage: ratingMessage)
                    results.append(item)
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                let sorted = results.sorted { (a,b) in
                    (a.createdAt ?? Date.distantPast) > (b.createdAt ?? Date.distantPast)
                }
                completion(sorted)
            }
        }
    }

    /// Fetch all documents from the `locations` collection and populate `locations`.
    func fetchLocations() {
        DispatchQueue.main.async { self.locationsDebug = "Starting fetchLocations..." }
        let coll = self.db.collection("locations")
        coll.getDocuments { snapshot, error in
            if let error = error {
                let msg = "fetchLocations error: \(error.localizedDescription)"
                print(msg)
                DispatchQueue.main.async { self.locationsDebug += "\n\(msg)" }
                return
            }
            let docs = snapshot?.documents ?? []
            DispatchQueue.main.async { self.locationsDebug += "\nfetchLocations: total=\(docs.count)" }

            let mapped: [LocationItem] = docs.map { d in
                let data = d.data()
                let id = d.documentID
                let name = (data["Name"] as? String) ?? (data["name"] as? String) ?? (data["locationName"] as? String)
                let address = (data["Address"] as? String) ?? (data["address"] as? String) ?? (data["Location"] as? String)
                let notes = (data["Notes"] as? String) ?? (data["notes"] as? String)
                var lat: Double? = nil
                var lng: Double? = nil
                if let latNum = data["latitude"] as? Double { lat = latNum } else if let latNum = data["Latitude"] as? Double { lat = latNum }
                if let lngNum = data["longitude"] as? Double { lng = lngNum } else if let lngNum = data["Longitude"] as? Double { lng = lngNum }
                if let gp = data["geo"] as? GeoPoint { lat = gp.latitude; lng = gp.longitude }
                return LocationItem(id: id, name: name, address: address, notes: notes, latitude: lat, longitude: lng)
            }

            DispatchQueue.main.async {
                self.locations = mapped
                self.locationsDebug += "\nAssigned \(mapped.count) locations"
            }
        }
    }

    /// Add a new location document into the `locations` collection.
    func addLocation(name: String, address: String? = nil, latitude: Double, longitude: Double, ownerRefs: [DocumentReference]? = nil, clientRef: DocumentReference? = nil, coachRef: DocumentReference? = nil, completion: @escaping (Error?) -> Void) {
        let coll = self.db.collection("locations")

        // base payload
        var data: [String: Any] = [
            "Name": name,
            "createdAt": FieldValue.serverTimestamp(),
            "geo": GeoPoint(latitude: latitude, longitude: longitude)
        ]
        if let address = address { data["Address"] = address }

        // If owner refs provided, store them on the root document and also store simple ownerUIDs for easy queries
        if let owners = ownerRefs {
            data["Owners"] = owners
            let uids = owners.map { $0.documentID }
            data["OwnerUIDs"] = uids
        }

        // Also include explicit ClientID/CoachID fields when available for convenience
        if let cRef = clientRef { data["ClientID"] = cRef }
        if let sRef = coachRef { data["CoachID"] = sRef }

        // Create a new document ref and use a batch to optionally mirror to owner subcollections
        let newDocRef = coll.document()
        let batch = self.db.batch()
        batch.setData(data, forDocument: newDocRef)

        if let owners = ownerRefs {
            for owner in owners {
                let ownerLocRef = owner.collection("locations").document(newDocRef.documentID)
                batch.setData(data, forDocument: ownerLocRef)
            }
        }

        batch.commit { err in
            if let err = err {
                print("addLocation commit error: \(err)")
                completion(err)
                return
            }
            // refresh local cache
            self.fetchLocations()
            completion(nil)
        }
    }

    /// Convenience: add a location and mirror it under the current user's client/coach subcollections (if applicable)
    func addLocationForCurrentUser(name: String, address: String? = nil, latitude: Double, longitude: Double, completion: @escaping (Error?) -> Void) {
        var ownerRefs: [DocumentReference] = []
        var clientReference: DocumentReference? = nil
        var coachReference: DocumentReference? = nil

        guard let uid = Auth.auth().currentUser?.uid else {
            // no authenticated user: just add to root
            addLocation(name: name, address: address, latitude: latitude, longitude: longitude, ownerRefs: nil, clientRef: nil, coachRef: nil, completion: completion)
            return
        }

        // Always create references for clients/{uid} and coaches/{uid} so the root doc contains pointers
        // We still mirror under the subcollections only if those profiles exist (or we can always mirror).
        let clientRefCandidate = db.collection("clients").document(uid)
        let coachRefCandidate = db.collection("coaches").document(uid)

        // If a client profile exists (cached) or we want to assume client ownership, add it
        if let client = self.currentClient, client.id == uid {
            ownerRefs.append(clientRefCandidate)
            clientReference = clientRefCandidate
        }

        // If a coach profile exists (cached) add it
        if let coach = self.currentCoach, coach.id == uid {
            ownerRefs.append(coachRefCandidate)
            coachReference = coachRefCandidate
        }

        // If neither client nor coach cached but user is authenticated, still attach the clientRef by default
        // so the saved location has a pointer to the user's document path. This helps identify ownership even
        // before the profile document is created.
        if ownerRefs.isEmpty {
            // default to client ownership (if your app separate roles, change logic accordingly)
            ownerRefs.append(clientRefCandidate)
            clientReference = clientRefCandidate
        }

        addLocation(name: name, address: address, latitude: latitude, longitude: longitude, ownerRefs: ownerRefs, clientRef: clientReference, coachRef: coachReference, completion: completion)
    }

    /// Seed developer/test sample locations into the `locations` collection.
    /// This is intended as a convenience for development only.
    func seedLocations(overwriteExisting: Bool = false, completion: @escaping (Error?) -> Void = { _ in }) {
        let coll = self.db.collection("locations")

        let samples: [[String: Any]] = [
            [
                "name": "Burnsville High School",
                "address": "600 E Highway 13, Burnsville, MN",
                "city": "Burnsville",
                "state": "MN",
                "zipcode": "55337",
                "geo": GeoPoint(latitude: 44.775, longitude: -93.279),
                "createdAt": FieldValue.serverTimestamp()
            ],
            [
                "name": "Heart of the City Park",
                "address": "230 W Main St, Minneapolis, MN",
                "city": "Minneapolis",
                "state": "MN",
                "zipcode": "55401",
                "geo": GeoPoint(latitude: 44.9778, longitude: -93.2650),
                "createdAt": FieldValue.serverTimestamp()
            ],
            [
                "name": "Riverfront Sports Center",
                "address": "100 Riverfront Ave, Saint Paul, MN",
                "city": "Saint Paul",
                "state": "MN",
                "zipcode": "55101",
                "geo": GeoPoint(latitude: 44.9537, longitude: -93.0900),
                "createdAt": FieldValue.serverTimestamp()
            ]
        ]

        // If overwrite flag is set, optionally clear existing documents (dev only)
        if overwriteExisting {
            coll.getDocuments { snap, err in
                if let err = err { completion(err); return }
                let batch = self.db.batch()
                for doc in snap?.documents ?? [] { batch.deleteDocument(doc.reference) }
                batch.commit { berr in
                    if let berr = berr { completion(berr); return }
                    // continue to add samples
                    self.writeSampleLocations(samples: samples, to: coll, completion: completion)
                }
            }
        } else {
            // write samples without deleting
            self.writeSampleLocations(samples: samples, to: coll, completion: completion)
        }
    }

    private func writeSampleLocations(samples: [[String: Any]], to coll: CollectionReference, completion: @escaping (Error?) -> Void) {
        let batch = self.db.batch()
        for s in samples {
            let doc = coll.document()
            batch.setData(s, forDocument: doc)
        }
        batch.commit { err in
            if let err = err {
                print("seedLocations commit error: \(err)")
                completion(err)
            } else {
                print("seedLocations: wrote \(samples.count) sample locations")
                completion(nil)
            }
        }
    }

    /// Migrate existing root `bookings` documents into per-coach and per-client subcollections.
    /// This is idempotent: it will set the same document data under each subcollection using the booking's root document ID.
    func migrateBookingsToSubcollections(completion: @escaping (Error?) -> Void) {
        let bookingsColl = self.db.collection("bookings")
        bookingsColl.getDocuments { [weak self] snapshot, error in
            guard let self = self else { completion(nil); return }
            if let error = error { completion(error); return }
            let docs = snapshot?.documents ?? []
            guard !docs.isEmpty else { completion(nil); return }

            let batch = self.db.batch()
            for doc in docs {
                let data = doc.data()
                let bookingId = doc.documentID
                // Resolve coach id & client id from either DocumentReference or string
                var coachId: String? = nil
                var clientId: String? = nil
                if let cref = data["CoachID"] as? DocumentReference { coachId = cref.documentID }
                else if let s = data["CoachID"] as? String { coachId = s.split(separator: "/").last.map(String.init) ?? s }
                if let cref = data["ClientID"] as? DocumentReference { clientId = cref.documentID }
                else if let s = data["ClientID"] as? String { clientId = s.split(separator: "/").last.map(String.init) ?? s }

                if let cId = coachId {
                    let coachBookingRef = self.db.collection("coaches").document(cId).collection("bookings").document(bookingId)
                    batch.setData(data, forDocument: coachBookingRef)
                }
                if let clId = clientId {
                    let clientBookingRef = self.db.collection("clients").document(clId).collection("bookings").document(bookingId)
                    batch.setData(data, forDocument: clientBookingRef)
                }
            }

            batch.commit { err in
                if let err = err { print("migrateBookingsToSubcollections commit error: \(err)"); completion(err) }
                else { print("migrateBookingsToSubcollections: mirrored \(docs.count) bookings"); completion(nil) }
            }
        }
    }

    /// Save booking to root `bookings` and mirror under coach/client subcollections.
    func saveBookingAndMirror(coachId: String,
                              clientId: String,
                              startAt: Date,
                              endAt: Date,
                              status: String = "requested",
                              location: String? = nil,
                              notes: String? = nil,
                              extra: [String: Any]? = nil,
                              completion: @escaping (Error?) -> Void) {
        let coachRef = self.db.collection("coaches").document(coachId)
        let clientRef = self.db.collection("clients").document(clientId)
        let bookingRef = self.db.collection("bookings").document()
        let coachBookingRef = coachRef.collection("bookings").document(bookingRef.documentID)
        let clientBookingRef = clientRef.collection("bookings").document(bookingRef.documentID)

        // Fetch coach and client names before saving booking
        coachRef.getDocument { [weak self] coachSnap, coachErr in
            guard let self = self else { return }

            var coachName: String? = nil
            if let coachData = coachSnap?.data() {
                let firstName = coachData["FirstName"] as? String ?? ""
                let lastName = coachData["LastName"] as? String ?? ""
                let fullName = [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
                if !fullName.isEmpty { coachName = fullName }
            }

            // Fetch client name for notification
            clientRef.getDocument { [weak self] clientSnap, clientErr in
            guard let self = self else { return }

            var clientName: String? = nil
            if let clientData = clientSnap?.data() {
                let firstName = clientData["FirstName"] as? String ?? ""
                let lastName = clientData["LastName"] as? String ?? ""
                let fullName = [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
                if !fullName.isEmpty { clientName = fullName }
            }

            var data: [String: Any] = [
                "CoachID": coachRef,
                "ClientID": clientRef,
                "StartAt": Timestamp(date: startAt),
                "EndAt": Timestamp(date: endAt),
                "Location": location ?? "",
                "Notes": notes ?? "",
                "Status": status,
                "createdAt": FieldValue.serverTimestamp()
            ]
            if let name = coachName { data["CoachName"] = name }
            if let extra = extra { for (k,v) in extra { data[k] = v } }

            print("[FirestoreManager] saveBookingAndMirror begin: bookingId=\(bookingRef.documentID) coachId=\(coachId) clientId=\(clientId) coachName=\(coachName ?? "nil")")

            let batch = self.db.batch()
            batch.setData(data, forDocument: bookingRef)
            batch.setData(data, forDocument: coachBookingRef)
            batch.setData(data, forDocument: clientBookingRef)

        // Build a compact denormalized summary to append to coach.calendar
        let bookingSummary: [String: Any] = [
            "id": bookingRef.documentID,
            "ClientID": clientRef.documentID,
            "CoachID": coachRef.documentID,
            "StartAt": Timestamp(date: startAt),
            "EndAt": Timestamp(date: endAt),
            "Location": location ?? "",
            "Notes": notes ?? "",
            "Status": status,
            "createdAt": Timestamp(date: Date())
        ]

        // Use arrayUnion to append without duplicating existing entries.
        batch.updateData(["calendar": FieldValue.arrayUnion([bookingSummary])], forDocument: coachRef)

        batch.commit { err in
            if let err = err {
                print("[FirestoreManager] saveBookingAndMirror commit error: \(err)")
                completion(err)
                return
            }
            print("[FirestoreManager] saveBookingAndMirror commit succeeded for booking \(bookingRef.documentID). Verifying mirrors...")

            let group = DispatchGroup()
            var firstError: Error? = nil

            group.enter()
            coachBookingRef.getDocument { snap, err in
                if let err = err {
                    print("[FirestoreManager] coach mirror getDocument error: \(err)")
                    if firstError == nil { firstError = err }
                } else if let snap = snap, snap.exists {
                    print("[FirestoreManager] coach mirror exists at \(coachBookingRef.path)")
                } else {
                    print("[FirestoreManager] coach mirror MISSING at \(coachBookingRef.path)")
                }
                group.leave()
            }

            group.enter()
            clientBookingRef.getDocument { snap, err in
                if let err = err {
                    print("[FirestoreManager] client mirror getDocument error: \(err)")
                    if firstError == nil { firstError = err }
                } else if let snap = snap, snap.exists {
                    print("[FirestoreManager] client mirror exists at \(clientBookingRef.path)")
                } else {
                    print("[FirestoreManager] client mirror MISSING at \(clientBookingRef.path)")
                }
                group.leave()
            }

            group.notify(queue: .main) {
                if let err = firstError {
                    completion(err)
                } else {
                    // Send notification to coach for requested bookings
                    if status.lowercased() == "requested" {
                        let displayName = clientName ?? "A client"
                        let notifRef = self.db.collection("pendingNotifications").document(coachId).collection("notifications").document()
                        let notifPayload: [String: Any] = [
                            "title": "Booking Requested",
                            "body": "Booking Requested by \(displayName) Action Required",
                            "bookingId": bookingRef.documentID,
                            "senderId": clientId,
                            "createdAt": FieldValue.serverTimestamp(),
                            "delivered": false
                        ]
                        notifRef.setData(notifPayload) { nerr in
                            if let nerr = nerr {
                                print("[FirestoreManager] Failed to write booking notification for coach \(coachId): \(nerr)")
                            } else {
                                print("[FirestoreManager] Booking notification sent to coach \(coachId)")
                            }
                        }
                    }
                    completion(nil)
                }
            }
        }
        } // end clientRef.getDocument
        } // end coachRef.getDocument
    }

    /// Convenience wrapper used by UI to save a booking. Calls the internal saveBookingAndMirror implementation.
    func saveBooking(clientUid: String, coachUid: String, startAt: Date, endAt: Date, location: String?, notes: String?, status: String = "requested", completion: @escaping (Error?) -> Void) {
        saveBookingAndMirror(coachId: coachUid, clientId: clientUid, startAt: startAt, endAt: endAt, status: status, location: location, notes: notes, extra: nil, completion: completion)
    }

    /// Debug helper to fetch all bookings (root collection) and append a readable dump into bookingsDebug.
    func fetchAllBookingsDebug() {
        DispatchQueue.main.async { self.bookingsDebug = "Starting fetchAllBookingsDebug..." }
        let coll = self.db.collection("bookings")
        coll.getDocuments { snapshot, error in
            if let error = error {
                let msg = "fetchAllBookingsDebug error: \(error.localizedDescription)"
                print(msg)
                DispatchQueue.main.async { self.bookingsDebug += "\n\(msg)" }
                return
            }
            let docs = snapshot?.documents ?? []
            var lines: [String] = ["Total bookings: \(docs.count)"]
            for d in docs.prefix(50) {
                let data = d.data()
                let id = d.documentID
                let start = (data["StartAt"] as? Timestamp)?.dateValue()
                let coach = (data["CoachID"] as? DocumentReference)?.documentID ?? (data["CoachID"] as? String ?? "")
                let client = (data["ClientID"] as? DocumentReference)?.documentID ?? (data["ClientID"] as? String ?? "")
                lines.append("id=\(id) coach=\(coach) client=\(client) start=\(start ?? Date.distantPast)")
            }
            DispatchQueue.main.async {
                self.bookingsDebug += "\n" + lines.joined(separator: "\n")
            }
        }
    }

    // Dummy upload to cloudinary - placeholder to satisfy callers
    func uploadToCloudinary(data: Data, filename: String, completion: @escaping (Result<URL, Error>) -> Void) {
        // Placeholder - user must configure their unsigned preset and cloud name
        completion(.failure(NSError(domain: "Cloudinary", code: 0, userInfo: [NSLocalizedDescriptionKey: "Cloudinary not configured"])))
    }

    func showToast(_ message: String) {
        // placeholder for UI toast handling
        print("Toast: \(message)")
    }

    // Upload profile image to Firebase Storage and return a download URL.
    // Stores images under "profileImages/<filename>" in the project's default storage bucket.
    func uploadProfileImageToStorage(data: Data, filename: String, completion: @escaping (Result<URL, Error>) -> Void) {
        // Ensure Storage is available
        let storage = Storage.storage()
        // Use a folder for profile images
        let storageRef = storage.reference().child("profileImages")
        let fileRef = storageRef.child(filename)

        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        fileRef.putData(data, metadata: metadata) { meta, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            fileRef.downloadURL { url, err in
                if let err = err {
                    completion(.failure(err))
                } else if let url = url {
                    completion(.success(url))
                } else {
                    completion(.failure(NSError(domain: "Storage", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown error getting download URL"])))
                }
            }
        }
    }

    /// Fetch bookings stored under clients/{clientId}/bookings and set published `bookings`.
    func fetchBookingsFromClientSubcollection(clientId: String) {
        DispatchQueue.main.async { self.bookingsDebug = "Starting fetchBookingsFromClientSubcollection for \(clientId)..." }
        fetchBookingsForClient(clientId: clientId) { items in
            DispatchQueue.main.async {
                self.bookings = items.sorted { (a,b) in
                    (a.startAt ?? Date.distantPast) > (b.startAt ?? Date.distantPast)
                }
                self.bookingsDebug += "\nFetched \(items.count) bookings from clients/\(clientId)/bookings"
            }
        }
    }

    /// Convenience: fetch bookings for the currently authenticated user from their client subcollection.
    func fetchBookingsForCurrentClientSubcollection() {
        DispatchQueue.main.async { self.bookingsDebug = "Starting fetchBookingsForCurrentClientSubcollection..." }
        guard let uid = Auth.auth().currentUser?.uid else {
            DispatchQueue.main.async { self.bookings = []; self.bookingsDebug += "\nNo authenticated user" }
            return
        }
        fetchBookingsFromClientSubcollection(clientId: uid)
    }

    /// Fetch all bookings mirrored under each coach's `bookings` subcollection and populate `coachBookings`.
    func fetchAllCoachBookings() {
        DispatchQueue.main.async { self.coachBookingsDebug = "Starting fetchAllCoachBookings..." }
        let coachColl = self.db.collection("coaches")
        coachColl.getDocuments { snap, err in
            if let err = err {
                let msg = "fetchAllCoachBookings: failed to list coaches: \(err.localizedDescription)"
                print(msg)
                DispatchQueue.main.async { self.coachBookingsDebug += "\n\(msg)" }
                return
            }
            let coachDocs = snap?.documents ?? []
            DispatchQueue.main.async { self.coachBookingsDebug += "\nFound \(coachDocs.count) coaches" }

            let group = DispatchGroup()
            var aggregated: [BookingItem] = []

            for coachDoc in coachDocs {
                group.enter()
                let coachId = coachDoc.documentID
                let coachFirst = coachDoc.data()["FirstName"] as? String ?? ""
                let coachLast = coachDoc.data()["LastName"] as? String ?? ""
                let coachName = [coachFirst, coachLast].filter { !$0.isEmpty }.joined(separator: " ")

                let coll = coachDoc.reference.collection("bookings")
                coll.getDocuments { bsnap, berr in
                    if let berr = berr {
                        print("fetchAllCoachBookings: failed to list bookings for coach \(coachId): \(berr)")
                        group.leave()
                        return
                    }
                    let docs = bsnap?.documents ?? []
                    for d in docs {
                        let data = d.data()
                        let id = d.documentID
                        let clientID = (data["ClientID"] as? DocumentReference)?.documentID ?? (data["ClientID"] as? String ?? "")
                        let startAt = (data["StartAt"] as? Timestamp)?.dateValue()
                        let endAt = (data["EndAt"] as? Timestamp)?.dateValue()
                        let status = data["Status"] as? String
                        let location = data["Location"] as? String
                        let notes = data["Notes"] as? String
                        // attempt to resolve client name sync-ish: we won't block overall fetching per-client
                        // we don't retain clientName here because it will be resolved later in bulk
                        var clientName: String? = nil
                        if let clientRef = data["ClientID"] as? DocumentReference {
                            clientRef.getDocument { cSnap, _ in
                                if let cdata = cSnap?.data() {
                                    clientName = cdata["name"] as? String
                                }
                            }
                        } else if let clientStr = data["ClientID"] as? String {
                            // try to fetch client doc to get name
                            self.db.collection("clients").document(clientID).getDocument { cSnap, _ in
                                if let cdata = cSnap?.data() { /* no-op: resolve later if needed */ }
                            }
                        }

                        let item = BookingItem(id: id, clientID: clientID, clientName: clientName, coachID: coachId, coachName: coachName.isEmpty ? coachId : coachName, startAt: startAt, endAt: endAt, location: location, notes: notes, status: status, paymentStatus: nil, RateUSD: nil)
                        aggregated.append(item)
                    }
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                // sort by start descending
                let sorted = aggregated.sorted { (a,b) in
                    (a.startAt ?? Date.distantPast) > (b.startAt ?? Date.distantPast)
                }
                self.coachBookings = sorted
                self.coachBookingsDebug += "\nAssigned \(sorted.count) coach-side bookings"
            }
        }
    }

    /// Fetch bookings for a specific coach's bookings subcollection and populate `coachBookings`.
    func fetchBookingsForCoachSubcollection(coachId: String) {
        DispatchQueue.main.async { self.coachBookingsDebug = "Starting fetchBookingsForCoachSubcollection for \(coachId)..." }
        fetchBookingsForCoach(coachId: coachId) { items in
            DispatchQueue.main.async {
                self.coachBookings = items.sorted { (a,b) in
                    (a.startAt ?? Date.distantPast) > (b.startAt ?? Date.distantPast)
                }
                self.coachBookingsDebug += "\nFetched \(items.count) bookings from coaches/\(coachId)/bookings"
            }
        }
    }

    /// Convenience: fetch bookings for the currently authenticated user treating them as a coach.
    func fetchBookingsForCurrentCoachSubcollection() {
        DispatchQueue.main.async { self.coachBookingsDebug = "Starting fetchBookingsForCurrentCoachSubcollection..." }
        guard let uid = Auth.auth().currentUser?.uid else {
            DispatchQueue.main.async { self.coachBookings = []; self.coachBookingsDebug += "\nNo authenticated user" }
            return
        }
        fetchBookingsForCoachSubcollection(coachId: uid)
    }

    /// Fetch locations from a client's `locations` subcollection and return mapped LocationItem array.
    func fetchLocationsForClient(clientId: String, completion: @escaping ([LocationItem]) -> Void) {
        let coll = db.collection("clients").document(clientId).collection("locations")
        coll.getDocuments { snapshot, error in
            if let error = error {
                print("fetchLocationsForClient error: \(error)")
                completion([])
                return
            }
            let docs = snapshot?.documents ?? []
            let mapped: [LocationItem] = docs.map { d in
                let data = d.data()
                let id = d.documentID
                let name = (data["Name"] as? String) ?? (data["name"] as? String) ?? (data["locationName"] as? String)
                let address = (data["Address"] as? String) ?? (data["address"] as? String) ?? (data["Location"] as? String)
                let notes = (data["Notes"] as? String) ?? (data["notes"] as? String)
                var lat: Double? = nil
                var lng: Double? = nil
                if let latNum = data["latitude"] as? Double { lat = latNum } else if let latNum = data["Latitude"] as? Double { lat = latNum }
                if let lngNum = data["longitude"] as? Double { lng = lngNum } else if let lngNum = data["Longitude"] as? Double { lng = lngNum }
                if let gp = data["geo"] as? GeoPoint { lat = gp.latitude; lng = gp.longitude }
                return LocationItem(id: id, name: name, address: address, notes: notes, latitude: lat, longitude: lng)
            }
            completion(mapped)
        }
    }

    /// Convenience: fetch locations for the currently authenticated user (clients/{uid}/locations)
    func fetchLocationsForCurrentUser() {
        DispatchQueue.main.async { self.locationsDebug = "Starting fetchLocationsForCurrentUser..." }
        guard let uid = Auth.auth().currentUser?.uid else {
            DispatchQueue.main.async {
                self.locations = []
                self.locationsDebug += "\nNo authenticated user"
            }
            return
        }
        fetchLocationsForClient(clientId: uid) { items in
            DispatchQueue.main.async {
                self.locations = items
                self.locationsDebug += "\nFetched \(items.count) locations for client/\(uid)"
            }
        }
    }

    /// Reads the `userType/{uid}` document and publishes the `type` field.
    func fetchUserType(for uid: String, completion: (() -> Void)? = nil) {
        let docRef = db.collection("userType").document(uid)
        DispatchQueue.main.async { self.userTypeLoaded = false }
        docRef.getDocument { snap, err in
            if let err = err {
                print("fetchUserType error: \(err)")
                DispatchQueue.main.async { self.currentUserType = nil; self.userTypeLoaded = true; completion?() }
                return
            }
            guard let data = snap?.data() else {
                DispatchQueue.main.async { self.currentUserType = nil; self.userTypeLoaded = true; completion?() }
                return
            }
            let t = (data["type"] as? String)?.uppercased()
            DispatchQueue.main.async { self.currentUserType = t; self.userTypeLoaded = true; completion?() }
        }
    }

    /// Update the Status field for a booking across root and mirrored subcollections.
    /// This is tolerant to CoachID/ClientID stored as DocumentReference or String.
    func updateBookingStatus(bookingId: String, status: String, completion: @escaping (Error?) -> Void) {
        let bookingRef = self.db.collection("bookings").document(bookingId)

        // Read the booking to resolve coach/client ids (if needed)
        bookingRef.getDocument { snap, err in
            if let err = err {
                print("updateBookingStatus: failed to read booking \(bookingId): \(err)")
                completion(err)
                return
            }

            guard let data = snap?.data() else {
                // Booking missing: nothing to update
                print("updateBookingStatus: booking \(bookingId) not found")
                completion(NSError(domain: "FirestoreManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Booking not found"]))
                return
            }

            // Helper to extract document id from various representations
            func extractId(from field: Any?) -> String? {
                if let ref = field as? DocumentReference { return ref.documentID }
                if let s = field as? String { return s.split(separator: "/").last.map(String.init) ?? s }
                if let dict = field as? [String: Any] {
                    if let id = dict["id"] as? String { return id }
                    if let path = dict["path"] as? String { return path.split(separator: "/").last.map(String.init) }
                }
                return nil
            }

            let coachId = extractId(from: data["CoachID"])
            let clientId = extractId(from: data["ClientID"])

            // Build batch to update root booking and any mirrored subcollection documents
            let batch = self.db.batch()

            // Update root booking
            batch.updateData(["Status": status], forDocument: bookingRef)

            // Update coach mirror if possible
            if let cId = coachId {
                let coachBookingRef = self.db.collection("coaches").document(cId).collection("bookings").document(bookingId)
                batch.updateData(["Status": status], forDocument: coachBookingRef)
            }

            // Update client mirror if possible
            if let clId = clientId {
                let clientBookingRef = self.db.collection("clients").document(clId).collection("bookings").document(bookingId)
                batch.updateData(["Status": status], forDocument: clientBookingRef)
            }

            batch.commit { err in
                if let err = err {
                    print("updateBookingStatus: batch commit failed: \(err)")
                    completion(err)
                } else {
                    print("updateBookingStatus: booking \(bookingId) status updated to \(status)")
                    // If booking was confirmed and the user opted into auto-add, add to calendar
                    if status.lowercased() == "confirmed" || status.lowercased() == "accepted" {
                        // Only proceed if the current user opted in
                        if self.autoAddToCalendar {
                            // Fetch the booking doc to extract details and add to calendar
                            bookingRef.getDocument { bsnap, berr in
                                if let berr = berr { print("updateBookingStatus: failed fetching booking to add calendar: \(berr)"); completion(nil); return }
                                guard let bdata = bsnap?.data() else { completion(nil); return }
                                // Extract title: prefer coach/client names
                                var title = "Booking"
                                if let clientRef = bdata["ClientID"] as? DocumentReference {
                                    title = "Session with \(clientRef.documentID)"
                                }
                                if let coachRef = bdata["CoachID"] as? DocumentReference {
                                    title = "Session with \(coachRef.documentID)"
                                }
                                // Extract start/end
                                let start = (bdata["StartAt"] as? Timestamp)?.dateValue() ?? Date()
                                let end = (bdata["EndAt"] as? Timestamp)?.dateValue() ?? Calendar.current.date(byAdding: .minute, value: 30, to: start) ?? Date()
                                let location = bdata["Location"] as? String
                                let notes = bdata["Notes"] as? String
                                self.addBookingToAppleCalendar(title: title, start: start, end: end, location: location, notes: notes, bookingId: bookingId) { res in
                                    switch res {
                                    case .success(let eventId): print("Added booking to calendar: \(eventId)")
                                    case .failure(let err): print("Failed to add booking to calendar: \(err)")
                                    }
                                }
                            }
                        }
                    }
                    completion(nil)
                }
            }
        }
    }

    /// Update the PaymentStatus field for a booking across root and mirrored subcollections.
    func updateBookingPaymentStatus(bookingId: String, paymentStatus: String, completion: @escaping (Error?) -> Void) {
        let bookingRef = self.db.collection("bookings").document(bookingId)

        bookingRef.getDocument { snap, err in
            if let err = err {
                print("updateBookingPaymentStatus: failed to read booking \(bookingId): \(err)")
                completion(err)
                return
            }

            guard let data = snap?.data() else {
                print("updateBookingPaymentStatus: booking \(bookingId) not found")
                completion(NSError(domain: "FirestoreManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Booking not found"]))
                return
            }

            func extractId(from field: Any?) -> String? {
                if let ref = field as? DocumentReference { return ref.documentID }
                if let s = field as? String { return s.split(separator: "/").last.map(String.init) ?? s }
                if let dict = field as? [String: Any] {
                    if let id = dict["id"] as? String { return id }
                    if let path = dict["path"] as? String { return path.split(separator: "/").last.map(String.init) }
                }
                return nil
            }

            let coachId = extractId(from: data["CoachID"])
            let clientId = extractId(from: data["ClientID"])

            let batch = self.db.batch()

            // Update root booking
            batch.updateData(["PaymentStatus": paymentStatus], forDocument: bookingRef)

            // Update coach mirror if possible
            if let cId = coachId {
                let coachBookingRef = self.db.collection("coaches").document(cId).collection("bookings").document(bookingId)
                batch.updateData(["PaymentStatus": paymentStatus], forDocument: coachBookingRef)
            }

            // Update client mirror if possible
            if let clId = clientId {
                let clientBookingRef = self.db.collection("clients").document(clId).collection("bookings").document(bookingId)
                batch.updateData(["PaymentStatus": paymentStatus], forDocument: clientBookingRef)
            }

            batch.commit { err in
                if let err = err {
                    print("updateBookingPaymentStatus: batch commit failed: \(err)")
                    completion(err)
                } else {
                    print("updateBookingPaymentStatus: booking \(bookingId) payment status updated to \(paymentStatus)")
                    completion(nil)
                }
            }
        }
    }

    /// Fetch bookings from the root `bookings` collection for a specific coach within an optional date range.
    /// This is a fallback for projects that don't mirror bookings into coaches/{id}/bookings.
    func fetchRootBookingsForCoach(coachId: String, start: Date? = nil, end: Date? = nil, completion: @escaping ([BookingItem]) -> Void) {
        var query: Query = db.collection("bookings")
        if let s = start { query = query.whereField("StartAt", isGreaterThanOrEqualTo: Timestamp(date: s)) }
        if let e = end { query = query.whereField("StartAt", isLessThan: Timestamp(date: e)) }
        query.getDocuments { snapshot, error in
            if let error = error { print("fetchRootBookingsForCoach error: \(error)"); completion([]); return }
            let docs = snapshot?.documents ?? []
            var items: [BookingItem] = []
            for d in docs {
                let data = d.data()
                // resolve coach id either as DocumentReference or String
                var docCoachId: String = ""
                if let cref = data["CoachID"] as? DocumentReference { docCoachId = cref.documentID }
                else if let s = data["CoachID"] as? String { docCoachId = s.split(separator: "/").last.map(String.init) ?? s }
                if docCoachId != coachId { continue }
                let id = d.documentID
                let clientID = (data["ClientID"] as? DocumentReference)?.documentID ?? (data["ClientID"] as? String ?? "")
                let startAt = (data["StartAt"] as? Timestamp)?.dateValue()
                let endAt = (data["EndAt"] as? Timestamp)?.dateValue()
                let status = data["Status"] as? String
                let location = data["Location"] as? String
                let notes = data["Notes"] as? String
                let paymentStatus = data["PaymentStatus"] as? String
                let rate = (data["RateUSD"] as? Double) ?? ((data["RateUSD"] as? Int).map { Double($0) })
                let item = BookingItem(id: id, clientID: clientID, clientName: nil, coachID: coachId, coachName: nil, startAt: startAt, endAt: endAt, location: location, notes: notes, status: status, paymentStatus: paymentStatus, RateUSD: rate)
                items.append(item)
            }
            completion(items)
        }
    }

    /// Send a text message into chats/{chatId}/messages and update the parent chat document's lastMessage fields.
    /// Writes a senderRef DocumentReference and also preserves legacy senderId for compatibility.
    func sendMessage(chatId: String, text: String, completion: ((Error?) -> Void)? = nil) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion?(NSError(domain: "FirestoreManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]))
            return
        }

        let chatRef = db.collection("chats").document(chatId)

        // Read chat participants so we can update per-user pointer docs as well
        chatRef.getDocument { snap, err in
            if let err = err {
                print("sendMessage: failed to read chat for participants: \(err)")
                // continue anyway and write message to chat
            }

            // Determine current user collection for senderRef
            let userTypeUpper = (self.currentUserType ?? "").uppercased()
            let userCollName = (userTypeUpper == "COACH") ? "coaches" : "clients"
            let senderRef = self.db.collection(userCollName).document(uid)

            let messagesColl = chatRef.collection("messages")
            let newMsgRef = messagesColl.document()

            // When creating a new message, do NOT mark the sender in `readBy`.
            // `readBy` should represent recipients who have read the message. The sender should not be listed here.
            var data: [String: Any] = [
                "text": text,
                "createdAt": FieldValue.serverTimestamp(),
                // write both reference and id for backward compatibility
                "senderRef": senderRef,
                "senderId": uid
            ]

            // Use a batch to write the message and update the parent chat metadata atomically
            let batch = self.db.batch()
            batch.setData(data, forDocument: newMsgRef)
            // Update chat metadata (last message). Avoid writing into other users' subcollections here because
            // client-originated writes may be blocked by security rules (clients can't write into coaches/{id}/chats).
            batch.setData(["lastMessageText": text, "lastMessageAt": FieldValue.serverTimestamp()], forDocument: chatRef, merge: true)

            batch.commit { err in
                if let err = err {
                    print("sendMessage: failed to send message for chatId=\(chatId): \(err)")
                    completion?(err)
                } else {
                    // After successfully writing the message, write small pendingNotifications for recipients (non-blocking)
                    if let pData = snap?.data() {
                        var recipients: [String] = []
                        if let prefRefs = pData["participantRefs"] as? [DocumentReference] {
                            for r in prefRefs {
                                let rid = r.documentID
                                if rid != uid { recipients.append(rid) }
                            }
                        } else if let pArr = pData["participants"] as? [String] {
                            for raw in pArr {
                                let rid = raw.split(separator: "/").last.map(String.init) ?? raw
                                if rid != uid { recipients.append(rid) }
                            }
                        }

                        var senderDisplayName: String = uid
                        if let cached = self.participantNames[uid], !cached.isEmpty { senderDisplayName = cached }
                        else if let curCoach = self.currentCoach, curCoach.id == uid { senderDisplayName = curCoach.name }
                        else if let curClient = self.currentClient, curClient.id == uid { senderDisplayName = curClient.name }

                        for rid in recipients {
                            let notifColl = self.db.collection("pendingNotifications").document(rid).collection("notifications")
                            let notifDoc = notifColl.document()
                            let payload: [String: Any] = [
                                "title": senderDisplayName,
                                "body": text,
                                "chatId": chatId,
                                "messageId": newMsgRef.documentID,
                                "senderId": uid,
                                "createdAt": FieldValue.serverTimestamp(),
                                "delivered": false
                            ]
                            notifDoc.setData(payload) { nerr in
                                if let nerr = nerr { print("sendMessage: failed to write pending notification for \(rid): \(nerr)") }
                            }
                        }
                    }

                    completion?(nil)
                }
            }
        }
    }

    /// Ensure a chat exists for the current user and the coachId. Uses deterministic id composed of sorted uids joined with '_' so UI can optimistically navigate.
    /// Calls completion with the chatId or nil on failure. Writes participantRefs as DocumentReferences and creates per-user pointer docs.
    func createOrGetChat(withCoachId coachId: String, completion: @escaping (String?) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else { completion(nil); return }
        let chatId = ([uid, coachId].sorted().joined(separator: "_"))
        let chatRef = db.collection("chats").document(chatId)
        chatRef.getDocument { snap, err in
            if let err = err {
                print("createOrGetChat: getDocument failed: \(err)")
                // Try to create anyway
            }
            if let snap = snap, snap.exists {
                completion(chatId)
                return
            }

            // Resolve roles (userType) for both participants so we can create DocumentReferences with ordering
            let uids = [uid, coachId]
            var types: [String: String] = [:]
            let group = DispatchGroup()
            for id in uids {
                group.enter()
                let doc = self.db.collection("userType").document(id)
                doc.getDocument { usnap, _ in
                    if let t = usnap?.data()?["type"] as? String {
                        types[id] = t.uppercased()
                        group.leave()
                        return
                    }
                    // fallback: check existence under coaches -> if exists treat as COACH, else CLIENT
                    self.db.collection("coaches").document(id).getDocument { csnap, _ in
                        if let cs = csnap, cs.exists { types[id] = "COACH" }
                        else { types[id] = "CLIENT" }
                        group.leave()
                    }
                }
            }

            group.notify(queue: .main) {
                // Build DocumentReferences for participants and ensure coach is first index
                var coachRef: DocumentReference? = nil
                var clientRef: DocumentReference? = nil

                for id in uids {
                    let t = types[id] ?? "CLIENT"
                    if t == "COACH" {
                        coachRef = self.db.collection("coaches").document(id)
                    } else {
                        // treat as client
                        if clientRef == nil { clientRef = self.db.collection("clients").document(id) }
                    }
                }

                // If we couldn't detect a coach (both clients), fall back to deterministic ordering by uid
                var participantRefs: [DocumentReference] = []
                if let cRef = coachRef, let clRef = clientRef {
                    participantRefs = [cRef, clRef]
                } else if let cRef = coachRef {
                    // only one coach detected
                    let otherId = (cRef.documentID == uid) ? coachId : uid
                    let otherType = types[otherId] ?? "CLIENT"
                    let otherRef = (otherType == "COACH") ? self.db.collection("coaches").document(otherId) : self.db.collection("clients").document(otherId)
                    if types[otherId] == "COACH" {
                        // both are coaches -> order by uid to be deterministic
                        let pair = [cRef, otherRef].sorted { $0.documentID < $1.documentID }
                        participantRefs = pair
                    } else {
                        // coach + client
                        participantRefs = [cRef, otherRef]
                    }
                } else {
                    // no coach detected -> treat both as clients; order deterministically by uid ascending
                    let refs = uids.sorted().map { self.db.collection("clients").document($0) }
                    participantRefs = refs
                }

                // Only write participantRefs now; do not write the legacy participants string array.
                let data: [String: Any] = [
                    "participantRefs": participantRefs,
                    "createdAt": FieldValue.serverTimestamp(),
                    "lastMessageText": NSNull(),
                    "lastMessageAt": FieldValue.serverTimestamp()
                ]

                chatRef.setData(data, merge: true) { err in
                    if let err = err {
                        print("createOrGetChat: failed to create chat: \(err)")
                        completion(nil)
                    } else {
                        // also create pointer docs under each participant for fast per-user listing
                        let batch = self.db.batch()
                        // Only write the per-user pointer doc for the current authenticated user to avoid
                        // writing into other users' collections (which may be prohibited by security rules).
                        for pref in participantRefs {
                            let comps = pref.path.split(separator: "/").map(String.init)
                            if comps.count >= 2 {
                                let collName = comps[0]
                                let userId = comps[1]
                                // only create pointer doc for the current user
                                if userId == uid {
                                    let userChatDoc = self.db.collection(collName).document(userId).collection("chats").document(chatId)
                                    let pointerData: [String: Any] = [
                                        "chatRef": chatRef,
                                        "participantRefs": participantRefs,
                                        "lastMessageText": NSNull(),
                                        "lastMessageAt": FieldValue.serverTimestamp()
                                    ]
                                    batch.setData(pointerData, forDocument: userChatDoc, merge: true)
                                }
                            }
                        }
                        batch.commit { berr in
                            if let berr = berr { print("createOrGetChat: failed to create pointer docs: \(berr)") }
                            completion(chatId)
                        }
                     }
                 }
             }
         }
     }

    /// Migrate legacy chat documents that store `participants` as [String] into using `participantRefs` ([DocumentReference]).
    /// This also creates/updates per-user pointer docs under coaches/{id}/chats and clients/{id}/chats.
    /// Safe to run once during a rollout; idempotent for already-migrated chats.
    func migrateChatsToParticipantRefs(limit: Int = 500, completion: @escaping (Error?) -> Void = { _ in }) {
        let coll = self.db.collection("chats")
        coll.limit(to: limit).getDocuments { snap, err in
            if let err = err { print("migrateChatsToParticipantRefs: failed to list chats: \(err)"); completion(err); return }
            let docs = snap?.documents ?? []
            if docs.isEmpty { print("migrateChatsToParticipantRefs: no chats found to migrate"); completion(nil); return }

            let group = DispatchGroup()
            var firstError: Error? = nil

            for doc in docs {
                let data = doc.data()
                // skip if already migrated
                if data["participantRefs"] != nil { continue }
                guard let partArr = data["participants"] as? [String], !partArr.isEmpty else { continue }

                group.enter()
                // Resolve each participant string to a DocumentReference.
                var resolvedRefs: [DocumentReference] = []
                let inner = DispatchGroup()

                for raw in partArr {
                    inner.enter()
                    // normalize to uid (take last path component)
                    let uid = raw.split(separator: "/").last.map(String.init) ?? raw

                    // prefer reading userType collection if present
                    let userTypeDoc = self.db.collection("userType").document(uid)
                    userTypeDoc.getDocument { utsnap, _ in
                        if let t = utsnap?.data()?["type"] as? String {
                            let upper = t.uppercased()
                            if upper == "COACH" {
                                resolvedRefs.append(self.db.collection("coaches").document(uid))
                                inner.leave()
                                return
                            } else {
                                resolvedRefs.append(self.db.collection("clients").document(uid))
                                inner.leave()
                                return
                            }
                        }
                        // fallback: check coaches/{uid} existence
                        self.db.collection("coaches").document(uid).getDocument { csnap, _ in
                            if let cs = csnap, cs.exists {
                                resolvedRefs.append(self.db.collection("coaches").document(uid))
                            } else {
                                resolvedRefs.append(self.db.collection("clients").document(uid))
                            }
                            inner.leave()
                        }
                    }
                }

                inner.notify(queue: .main) {
                    // write participantRefs into the chat doc and create pointer docs under each participant
                    let chatRef = self.db.collection("chats").document(doc.documentID)
                    var update: [String: Any] = ["participantRefs": resolvedRefs]
                    // keep legacy participants as well for compatibility
                    update["participants"] = partArr
                    chatRef.setData(update, merge: true) { err in
                        if let err = err {
                            print("migrateChatsToParticipantRefs: failed to update chat \(doc.documentID): \(err)")
                            if firstError == nil { firstError = err }
                            group.leave()
                            return
                        }

                        // create/update pointer docs under each participant's chats subcollection
                        let batch = self.db.batch()
                        for pref in resolvedRefs {
                            let comps = pref.path.split(separator: "/").map(String.init)
                            if comps.count >= 2 {
                                let collName = comps[0]
                                let userId = comps[1]
                                let userChatDoc = self.db.collection(collName).document(userId).collection("chats").document(doc.documentID)
                                let pointerData: [String: Any] = [
                                    "chatRef": chatRef,
                                    "participantRefs": resolvedRefs,
                                    "participants": partArr,
                                    "lastMessageText": data["lastMessageText"] ?? NSNull(),
                                    "lastMessageAt": data["lastMessageAt"] ?? FieldValue.serverTimestamp()
                                ]
                                batch.setData(pointerData, forDocument: userChatDoc, merge: true)
                            }
                        }
                        batch.commit { berr in
                            if let berr = berr { print("migrateChatsToParticipantRefs: failed to commit pointers for \(doc.documentID): \(berr)"); if firstError == nil { firstError = berr } }
                            group.leave()
                        }
                    }
                }
            }

            group.notify(queue: .main) {
                completion(firstError)
            }
        }
    }

    /// Migrate all chats in the `chats` collection by paging through documents in batches and converting legacy `participants` string arrays into `participantRefs` (DocumentReference[]).
    /// This function uses `migrateChatsToParticipantRefs(limit:completion:)` internally on each page and is idempotent.
    func migrateAllChatsInBatches(pageSize: Int = 200, completion: @escaping (Error?) -> Void = { _ in }) {
        let coll = self.db.collection("chats")
        var lastDoc: DocumentSnapshot? = nil
        var firstError: Error? = nil

        func fetchPage() {
            var q: Query = coll.order(by: FieldPath.documentID()).limit(to: pageSize)
            if let last = lastDoc { q = q.start(afterDocument: last) }
            q.getDocuments { snap, err in
                if let err = err { completion(err); return }
                let docs = snap?.documents ?? []
                if docs.isEmpty { completion(firstError); return }

                // Build a lightweight array of documentIDs to pass to a batch migration helper
                let docIDs = docs.map { $0.documentID }
                // Use the existing single-batch migration helper with a tailored limit: we'll directly process these docs.
                self.migrateSpecificChats(docIDs: docIDs) { err in
                    if let err = err {
                        if firstError == nil { firstError = err }
                    }
                    // advance to next page
                    lastDoc = docs.last
                    // small delay to avoid hammering backend
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { fetchPage() }
                }
            }
        }

        fetchPage()
    }

    /// Helper to migrate a specific list of chat document IDs into participantRefs, used by the paged migrator.
    private func migrateSpecificChats(docIDs: [String], completion: @escaping (Error?) -> Void) {
        guard !docIDs.isEmpty else { completion(nil); return }
        let group = DispatchGroup()
        var firstError: Error? = nil

        for id in docIDs {
            group.enter()
            let chatRef = self.db.collection("chats").document(id)
            chatRef.getDocument { snap, err in
                if let err = err { print("migrateSpecificChats: failed to read chat \(id): \(err)"); if firstError == nil { firstError = err }; group.leave(); return }
                guard let data = snap?.data() else { group.leave(); return }
                if data["participantRefs"] != nil { group.leave(); return }
                guard let partArr = data["participants"] as? [String], !partArr.isEmpty else { group.leave(); return }

                // Resolve participants into refs
                var resolvedRefs: [DocumentReference] = []
                let inner = DispatchGroup()
                for raw in partArr {
                    inner.enter()
                    let uid = raw.split(separator: "/").last.map(String.init) ?? raw
                    let userTypeDoc = self.db.collection("userType").document(uid)
                    userTypeDoc.getDocument { utsnap, _ in
                        if let t = utsnap?.data()?["type"] as? String {
                            let upper = t.uppercased()
                            if upper == "COACH" {
                                resolvedRefs.append(self.db.collection("coaches").document(uid))
                                inner.leave()
                                return
                            } else {
                                resolvedRefs.append(self.db.collection("clients").document(uid))
                                inner.leave()
                                return
                            }
                        }
                        // fallback: check coaches/{uid} existence
                        self.db.collection("coaches").document(uid).getDocument { csnap, _ in
                            if let cs = csnap, cs.exists {
                                resolvedRefs.append(self.db.collection("coaches").document(uid))
                            } else {
                                resolvedRefs.append(self.db.collection("clients").document(uid))
                            }
                            inner.leave()
                        }
                    }
                }

                inner.notify(queue: .main) {
                    let update: [String: Any] = ["participantRefs": resolvedRefs, "participants": partArr]
                    chatRef.setData(update, merge: true) { err in
                        if let err = err { print("migrateSpecificChats: failed to setData for \(id): \(err)"); if firstError == nil { firstError = err }; group.leave(); return }
                        // update pointer docs
                        let batch = self.db.batch()
                        for pref in resolvedRefs {
                            let comps = pref.path.split(separator: "/").map(String.init)
                            if comps.count >= 2 {
                                let collName = comps[0]
                                let userId = comps[1]
                                let userChatDoc = self.db.collection(collName).document(userId).collection("chats").document(id)
                                let pointerData: [String: Any] = [
                                    "chatRef": chatRef,
                                    "participantRefs": resolvedRefs,
                                    "participants": partArr,
                                    "lastMessageText": data["lastMessageText"] ?? NSNull(),
                                    "lastMessageAt": data["lastMessageAt"] ?? FieldValue.serverTimestamp()
                                ]
                                batch.setData(pointerData, forDocument: userChatDoc, merge: true)
                            }
                        }
                        batch.commit { berr in
                            if let berr = berr { print("migrateSpecificChats: failed to commit pointers for \(id): \(berr)"); if firstError == nil { firstError = berr } }
                            group.leave()
                        }
                    }
                }
            }
        }

        group.notify(queue: .main) { completion(firstError) }
    }

    /// Fetch latest message doc for a chat and return senderId and readBy map (if any)
    func fetchLatestMessageInfo(chatId: String, completion: @escaping ((_ info: (senderId: String?, readBy: [String: Any]?)?) -> Void)) {
        let coll = db.collection("chats").document(chatId).collection("messages")
        coll.order(by: "createdAt", descending: true).limit(to: 1).getDocuments { snap, err in
            if let err = err { print("fetchLatestMessageInfo(\(chatId)) error: \(err)"); completion(nil); return }
            guard let doc = snap?.documents.first else { completion(nil); return }
            let data = doc.data()
            var sender: String? = nil
            if let sRef = data["senderRef"] as? DocumentReference { sender = sRef.documentID }
            else if let s = data["senderId"] as? String { sender = s }
            else if let s = data["sender"] as? String { sender = s }
            let readBy = data["readBy"] as? [String: Any]
            completion((sender, readBy))
        }
    }

    /// Add a booking to the Apple Calendar as an event.
    /// - Parameter title: The title of the event.
    /// - Parameter start: The start date and time of the event.
    /// - Parameter end: The end date and time of the event.
    /// - Parameter location: The location of the event.
    /// - Parameter notes: Any notes for the event.
    /// - Parameter bookingId: The Firestore booking document ID, used to check for duplicates.
    /// - Parameter completion: Completion handler with the event identifier or error.
    func addBookingToAppleCalendar(title: String, start: Date, end: Date, location: String?, notes: String?, bookingId: String, completion: @escaping (Result<String, Error>) -> Void) {
        // Create the event store inside the closure to avoid capturing a non-Sendable instance
        let handleAccessResponse: (Bool, Error?) -> Void = { granted, error in
            // Recreate eventStore here (inside Sendable closure scope)
            let eventStore = EKEventStore()
            if let err = error {
                print("addBookingToAppleCalendar: requestAccess error: \(err)")
                completion(.failure(err))
                return
            }
            if !granted {
                let err = NSError(domain: "FirestoreManager", code: 403, userInfo: [NSLocalizedDescriptionKey: "Calendar access not granted"])
                print("addBookingToAppleCalendar: calendar access denied by user")
                completion(.failure(err))
                return
            }

            // Avoid duplicates: check if booking doc already has calendarEventId
            let bookingRef = self.db.collection("bookings").document(bookingId)
            bookingRef.getDocument { snap, err in
                if let err = err {
                    print("addBookingToAppleCalendar: failed to read booking doc: \(err)")
                    // continue attempt but still check later
                }
                if let data = snap?.data(), let existingEventId = data["calendarEventId"] as? String, !existingEventId.isEmpty {
                    // Already added on some device; return existing id
                    DispatchQueue.main.async { completion(.success(existingEventId)) }
                    return
                }

                // Create the event
                let event = EKEvent(eventStore: eventStore)
                event.title = title
                event.startDate = start
                event.endDate = end
                event.location = location
                event.notes = notes
                event.calendar = eventStore.defaultCalendarForNewEvents

                do {
                    try eventStore.save(event, span: .thisEvent)
                    let eventId = event.eventIdentifier ?? ""
                    // Persist the event identifier on the booking doc to avoid duplicates
                    bookingRef.setData(["calendarEventId": eventId, "calendarAddedAt": FieldValue.serverTimestamp(), "calendarAddedBy": Auth.auth().currentUser?.uid ?? NSNull()], merge: true) { err in
                        if let err = err {
                            print("addBookingToAppleCalendar: failed to persist calendarEventId to booking: \(err)")
                            // still return success for the local calendar save
                            DispatchQueue.main.async { completion(.success(eventId)) }
                        } else {
                            DispatchQueue.main.async { completion(.success(eventId)) }
                        }
                    }
                } catch {
                    print("addBookingToAppleCalendar: failed to save event: \(error)")
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            }
        }

        if #available(iOS 17.0, *) {
            EKEventStore().requestFullAccessToEvents { granted, error in
                handleAccessResponse(granted, error)
            }
        } else {
            EKEventStore().requestAccess(to: .event) { granted, error in
                handleAccessResponse(granted, error)
            }
        }
    }

    /// Update or set the payments dictionary on the current coach document. Keys are payment types (e.g., "venmo", "paypal"), values are usernames.
    func updateCurrentCoachPayments(_ payments: [String: String], completion: ((Error?) -> Void)? = nil) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion?(NSError(domain: "FirestoreManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]))
            return
        }
        let ref = db.collection("coaches").document(uid)
        ref.setData(["payments": payments, "updatedAt": FieldValue.serverTimestamp()], merge: true) { err in
            if let err = err {
                print("updateCurrentCoachPayments error: \(err)")
                completion?(err)
                return
            }
            if let cur = self.currentCoach {
                let updated = Coach(id: cur.id,
                                    name: cur.name,
                                    specialties: cur.specialties,
                                    experienceYears: cur.experienceYears,
                                    availability: cur.availability,
                                    bio: cur.bio,
                                    hourlyRate: cur.hourlyRate,
                                    photoURLString: cur.photoURLString,
                                    meetingPreference: cur.meetingPreference,
                                    zipCode: cur.zipCode,
                                    city: cur.city,
                                    payments: payments)
                self.currentCoach = updated
            }
            completion?(nil)
        }
    }

    // MARK: - Payments Helpers
    /// Fetch the payments dictionary for a coach by id. Returns keys like "venmo", "paypal" mapped to usernames.
    /// Tolerant to a CoachID stored as raw uid or path (e.g., "coaches/<id>").
    func fetchCoachPayments(coachIdOrPath: String, completion: @escaping ([String: String]) -> Void) {
        // normalize id
        let coachId = coachIdOrPath.split(separator: "/").last.map(String.init) ?? coachIdOrPath
        let ref = db.collection("coaches").document(coachId)
        ref.getDocument { snap, err in
            if let err = err { print("fetchCoachPayments error: \(err)"); completion([:]); return }
            guard let data = snap?.data() else { completion([:]); return }
            if let map = data["payments"] as? [String: String] { completion(map); return }
            // Coerce [String: Any] -> [String: String]
            if let anyMap = data["payments"] as? [String: Any] {
                var out: [String: String] = [:]
                for (k, v) in anyMap { if let s = v as? String { out[k] = s } }
                completion(out)
                return
            }
            completion([:])
        }
    }

    /// Resolve a coach display name given a CoachID (uid or path). Falls back to the id if name is not set.
    func fetchCoachDisplayName(coachIdOrPath: String, completion: @escaping (String) -> Void) {
        let coachId = coachIdOrPath.split(separator: "/").last.map(String.init) ?? coachIdOrPath
        let ref = db.collection("coaches").document(coachId)
        ref.getDocument { snap, err in
            if let err = err { print("fetchCoachDisplayName error: \(err)"); completion(coachId); return }
            guard let data = snap?.data() else { completion(coachId); return }
            let first = data["FirstName"] as? String ?? ""
            let last = data["LastName"] as? String ?? ""
            let name = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
            completion(name.isEmpty ? coachId : name)
        }
    }

    /// Normalize Firestore errors for call sites that want to log and continue.
    /// Returns the same error for now; you can expand this to map FirestoreStatus to user-friendly messages.
    func handleFirestoreError(_ error: Error?) -> Error? {
        guard let error = error else { return nil }
        return error
    }
}

extension FirestoreManager {
    struct AwayTimeItem: Identifiable {
        let id: String
        let startAt: Date
        let endAt: Date
        let notes: String?
    }

    /// Fetch away time blocks for a coach from coaches/{coachId}/awayTimes within an optional date range.
    func fetchAwayTimesForCoach(coachId: String, start: Date? = nil, end: Date? = nil, completion: @escaping ([AwayTimeItem]) -> Void) {
        var query: Query = db.collection("coaches").document(coachId).collection("awayTimes")
        if let s = start { query = query.whereField("startAt", isGreaterThanOrEqualTo: Timestamp(date: s)) }
        if let e = end { query = query.whereField("startAt", isLessThan: Timestamp(date: e)) }
        query.getDocuments { snapshot, error in
            if let error = error {
                print("fetchAwayTimesForCoach error: \(error)")
                completion([])
                return
            }
            let docs = snapshot?.documents ?? []
            let items: [AwayTimeItem] = docs.compactMap { d in
                let data = d.data()
                guard let s = (data["startAt"] as? Timestamp)?.dateValue(), let e = (data["endAt"] as? Timestamp)?.dateValue() else { return nil }
                let notes = data["notes"] as? String
                return AwayTimeItem(id: d.documentID, startAt: s, endAt: e, notes: notes)
            }
            completion(items)
        }
    }
}
