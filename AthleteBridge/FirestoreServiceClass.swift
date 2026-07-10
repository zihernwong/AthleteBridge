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
        var tournamentSoftwareLink: String? = nil
    }
    @Published var signupEvents: [SignupEvent] = []
    @Published var tournaments: [Tournament] = []
    @Published var placesToPlay: [PlaceToPlay] = []
    @Published var clubAnnouncements: [String: [ClubAnnouncement]] = [:]  // placeId -> announcements
    @Published var playersToPlayWith: [PlayerToPlayWith] = []
    @Published var stringers: [BadmintonStringer] = []
    @Published var stringerReviews: [StringerReview] = []
    @Published var stringerOrders: [StringerOrder] = []
    @Published var stringerIncomingOrders: [StringerOrder] = []
    @Published var myStringerOrders: [StringerOrder] = []
    @Published var clients: [UserSummary] = []
    @Published var clientPhotoURLs: [String: URL?] = [:]
    @Published var clientLastSeen: [String: Date] = [:]
    @Published var currentClient: Client? = nil
    @Published var currentClientPhotoURL: URL? = nil
    // Small cached UIImage for the tab bar/avatar usage (keeps MainAppView simple and avoids re-downloading)
    @Published var currentUserTabImage: UIImage? = nil
    @Published var currentCoach: Coach? = nil
    @Published var currentCoachPhotoURL: URL? = nil
    // Published user type from `userType/{uid}` (e.g. "COACH" or "CLIENT")
    @Published var currentUserType: String? = nil
    @Published var userTypeLoaded: Bool = false
    @Published var currentAdditionalTypes: [String] = []
    @Published var currentUserPhoneVerified: Bool = false
    @Published var profilesLoaded: Bool = false
    private var pendingProfileFetches = 0

    // User preference: whether to automatically add confirmed bookings to the device calendar
    @Published var autoAddToCalendar: Bool = false

    // User preference: whether the user has granted location permission for driving time
    @Published var locationPermissionGranted: Bool = false

    // Track booking IDs currently being processed for calendar add to prevent race conditions
    private var calendarAddInProgress: Set<String> = []

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
            let locPerm = data["locationPermissionGranted"] as? Bool ?? false
            DispatchQueue.main.async {
                self.autoAddToCalendar = auto
                self.locationPermissionGranted = locPerm
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

    /// Persist the location permission preference for the current user into Firestore.
    func setLocationPermissionGranted(_ value: Bool, completion: ((Error?) -> Void)? = nil) {
        DispatchQueue.main.async { self.locationPermissionGranted = value }
        guard let uid = Auth.auth().currentUser?.uid else { completion?(nil); return }
        let ref = db.collection("userSettings").document(uid)
        ref.setData(["locationPermissionGranted": value], merge: true) { err in
            if let err = err { print("setLocationPermissionGranted error: \(err)") }
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
    struct BookingItem: Identifiable, Equatable {
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

        // Group booking fields
        let clientIDs: [String]?
        let clientNames: [String]?
        let coachIDs: [String]?
        let coachNames: [String]?
        let isGroupBooking: Bool?
        let creatorID: String?
        let creatorType: String?
        let coachAcceptances: [String: Bool]?
        let clientConfirmations: [String: Bool]?
        let coachRates: [String: Double]?
        let coachNote: String?
        let rejectionReason: String?
        let rejectedBy: String?
        let clientDeclineReason: String?
        let requiresPaymentUpfront: Bool?
        let sessionRecap: String?      // coach-written, client-visible recap

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
             RateUSD: Double? = nil,
             clientIDs: [String]? = nil,
             clientNames: [String]? = nil,
             coachIDs: [String]? = nil,
             coachNames: [String]? = nil,
             isGroupBooking: Bool? = nil,
             creatorID: String? = nil,
             creatorType: String? = nil,
             coachAcceptances: [String: Bool]? = nil,
             clientConfirmations: [String: Bool]? = nil,
             coachRates: [String: Double]? = nil,
             coachNote: String? = nil,
             rejectionReason: String? = nil,
             rejectedBy: String? = nil,
             clientDeclineReason: String? = nil,
             requiresPaymentUpfront: Bool? = nil,
             sessionRecap: String? = nil) {
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
            self.clientIDs = clientIDs
            self.clientNames = clientNames
            self.coachIDs = coachIDs
            self.coachNames = coachNames
            self.isGroupBooking = isGroupBooking
            self.creatorID = creatorID
            self.creatorType = creatorType
            self.coachAcceptances = coachAcceptances
            self.clientConfirmations = clientConfirmations
            self.coachRates = coachRates
            self.coachNote = coachNote
            self.rejectionReason = rejectionReason
            self.rejectedBy = rejectedBy
            self.clientDeclineReason = clientDeclineReason
            self.requiresPaymentUpfront = requiresPaymentUpfront
            self.sessionRecap = sessionRecap
        }

        // Computed properties for unified access
        var allCoachIDs: [String] {
            if let ids = coachIDs, !ids.isEmpty { return ids }
            return coachID.isEmpty ? [] : [coachID]
        }

        var allClientIDs: [String] {
            if let ids = clientIDs, !ids.isEmpty { return ids }
            return clientID.isEmpty ? [] : [clientID]
        }

        var allCoachNames: [String] {
            if let names = coachNames, !names.isEmpty { return names }
            if let name = coachName { return [name] }
            return []
        }

        var allClientNames: [String] {
            if let names = clientNames, !names.isEmpty { return names }
            if let name = clientName { return [name] }
            return []
        }

        var allCoachesAccepted: Bool {
            guard let acceptances = coachAcceptances, !acceptances.isEmpty else {
                return true // Legacy booking or no acceptances tracking
            }
            return acceptances.values.allSatisfy { $0 }
        }

        var allClientsConfirmed: Bool {
            guard let confirmations = clientConfirmations, !confirmations.isEmpty else {
                return true // Legacy booking or no confirmations tracking
            }
            return confirmations.values.allSatisfy { $0 }
        }

        var participantSummary: String {
            let coachCount = allCoachIDs.count
            let clientCount = allClientIDs.count
            if coachCount == 1 && clientCount == 1 {
                return "1:1 Session"
            }
            return "\(coachCount) coach\(coachCount > 1 ? "es" : ""), \(clientCount) client\(clientCount > 1 ? "s" : "")"
        }
    }

    @Published var bookings: [BookingItem] = []
    @Published var bookingsDebug: String = ""

    // MARK: - Session Logs
    // After each completed session the coach logs what was worked on, what
    // needs improvement, what improved, and optional named metrics (e.g.
    // "1 mile sprint" -> "8:00"). Metrics are keyed by name so progress across
    // sessions can be shown. One log per booking (doc id = booking id).

    struct SessionMetric: Identifiable, Equatable, Hashable {
        var name: String
        var value: String
        var id: String { name + "|" + value }
    }

    struct SessionLog: Identifiable, Equatable {
        let id: String            // == booking id
        let coachID: String
        let clientID: String
        let coachName: String
        let clientName: String
        let sessionDate: Date?
        let workedOn: String
        let toImprove: String
        let improved: String
        let metrics: [SessionMetric]
        let createdAt: Date?
    }

    /// Logs written by the current coach (powers pending-log detection and
    /// the per-client history in My Clients).
    @Published var coachSessionLogs: [SessionLog] = []
    /// Logs about the current client (powers per-coach history in My Coaches).
    @Published var clientSessionLogs: [SessionLog] = []

    private var coachSessionLogsListener: ListenerRegistration? = nil
    private var clientSessionLogsListener: ListenerRegistration? = nil

    private static func parseSessionLog(_ id: String, _ data: [String: Any]) -> SessionLog {
        var metrics: [SessionMetric] = []
        if let raw = data["Metrics"] as? [[String: Any]] {
            for entry in raw {
                let name = (entry["name"] as? String ?? "").trimmingCharacters(in: .whitespaces)
                let value = (entry["value"] as? String ?? "").trimmingCharacters(in: .whitespaces)
                if !name.isEmpty && !value.isEmpty {
                    metrics.append(SessionMetric(name: name, value: value))
                }
            }
        }
        return SessionLog(
            id: id,
            coachID: data["CoachID"] as? String ?? "",
            clientID: data["ClientID"] as? String ?? "",
            coachName: data["CoachName"] as? String ?? "",
            clientName: data["ClientName"] as? String ?? "",
            sessionDate: (data["SessionDate"] as? Timestamp)?.dateValue(),
            workedOn: data["WorkedOn"] as? String ?? "",
            toImprove: data["ToImprove"] as? String ?? "",
            improved: data["Improved"] as? String ?? "",
            metrics: metrics,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue()
        )
    }

    /// Live listener for all logs written by this coach.
    func listenSessionLogsForCoach(coachId: String) {
        guard !coachId.isEmpty, coachSessionLogsListener == nil else { return }
        coachSessionLogsListener = db.collection("sessionLogs")
            .whereField("CoachID", isEqualTo: coachId)
            .addSnapshotListener { [weak self] snap, err in
                if let err = err { print("listenSessionLogsForCoach error: \(err)"); return }
                let logs = (snap?.documents ?? [])
                    .map { Self.parseSessionLog($0.documentID, $0.data()) }
                    .sorted { ($0.sessionDate ?? .distantPast) > ($1.sessionDate ?? .distantPast) }
                DispatchQueue.main.async { self?.coachSessionLogs = logs }
            }
    }

    /// Live listener for all logs about this client.
    func listenSessionLogsForClient(clientId: String) {
        guard !clientId.isEmpty, clientSessionLogsListener == nil else { return }
        clientSessionLogsListener = db.collection("sessionLogs")
            .whereField("ClientID", isEqualTo: clientId)
            .addSnapshotListener { [weak self] snap, err in
                if let err = err { print("listenSessionLogsForClient error: \(err)"); return }
                let logs = (snap?.documents ?? [])
                    .map { Self.parseSessionLog($0.documentID, $0.data()) }
                    .sorted { ($0.sessionDate ?? .distantPast) > ($1.sessionDate ?? .distantPast) }
                DispatchQueue.main.async { self?.clientSessionLogs = logs }
            }
    }

    /// Create or update the session log for a booking (doc id = booking id, so
    /// re-saving edits the same log).
    func saveSessionLog(bookingId: String,
                        coachId: String,
                        clientId: String,
                        coachName: String,
                        clientName: String,
                        sessionDate: Date?,
                        workedOn: String,
                        toImprove: String,
                        improved: String,
                        metrics: [SessionMetric],
                        completion: ((Error?) -> Void)? = nil) {
        guard !bookingId.isEmpty, !coachId.isEmpty else {
            completion?(NSError(domain: "FirestoreManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Missing booking or coach id"]))
            return
        }
        var payload: [String: Any] = [
            "BookingID": bookingId,
            "CoachID": coachId,
            "ClientID": clientId,
            "CoachName": coachName,
            "ClientName": clientName,
            "WorkedOn": workedOn.trimmingCharacters(in: .whitespacesAndNewlines),
            "ToImprove": toImprove.trimmingCharacters(in: .whitespacesAndNewlines),
            "Improved": improved.trimmingCharacters(in: .whitespacesAndNewlines),
            "Metrics": metrics
                .filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty && !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
                .map { ["name": $0.name.trimmingCharacters(in: .whitespaces), "value": $0.value.trimmingCharacters(in: .whitespaces)] },
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let d = sessionDate { payload["SessionDate"] = Timestamp(date: d) }
        payload["createdAt"] = FieldValue.serverTimestamp()
        db.collection("sessionLogs").document(bookingId).setData(payload, merge: true) { err in
            if let err = err { print("saveSessionLog error: \(err)") }
            completion?(err)
        }
    }

    /// Completed (confirmed, ended) sessions from the last 14 days that the
    /// coach has not logged yet — used to prompt the coach after each session.
    func pendingSessionLogs(coachId: String) -> [BookingItem] {
        let loggedIds = Set(coachSessionLogs.map { $0.id })
        let now = Date()
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: now) ?? now
        return coachBookings.filter { b in
            guard (b.status ?? "").lowercased() == "confirmed" else { return false }
            guard let end = b.endAt, end < now, end > cutoff else { return false }
            guard !loggedIds.contains(b.id) else { return false }
            return true
        }
        .sorted { ($0.endAt ?? .distantPast) > ($1.endAt ?? .distantPast) }
    }

    // MARK: - Agreed Rates (simplified booking flow)
    // Once a coach and client have settled on a price, it is stored in
    // agreedRates/{coachId}_{clientId} so future requests can carry the rate
    // and be confirmed by the coach in one tap. A pair can hold several
    // labeled rates (e.g. "1-on-1" and "Joint session").
    struct AgreedRate: Identifiable, Equatable {
        let label: String
        let rateUSD: Double
        var id: String { label }
    }

    private func agreedRatesDocRef(coachId: String, clientId: String) -> DocumentReference {
        db.collection("agreedRates").document("\(coachId)_\(clientId)")
    }

    func fetchAgreedRates(coachId: String, clientId: String, completion: @escaping ([AgreedRate]) -> Void) {
        guard !coachId.isEmpty, !clientId.isEmpty else { completion([]); return }
        agreedRatesDocRef(coachId: coachId, clientId: clientId).getDocument { snap, err in
            if let err = err {
                print("[FirestoreManager] fetchAgreedRates error: \(err)")
                completion([])
                return
            }
            let raw = snap?.data()?["Rates"] as? [[String: Any]] ?? []
            let rates: [AgreedRate] = raw.compactMap { entry in
                guard let label = entry["label"] as? String,
                      let rate = (entry["rateUSD"] as? Double) ?? ((entry["rateUSD"] as? Int).map { Double($0) }),
                      rate > 0 else { return nil }
                return AgreedRate(label: label, rateUSD: rate)
            }
            completion(rates)
        }
    }

    /// Upsert a labeled rate for a coach/client pair (replaces an existing rate with the same label).
    func saveAgreedRate(coachId: String, clientId: String, label: String, rateUSD: Double, completion: ((Error?) -> Void)? = nil) {
        guard !coachId.isEmpty, !clientId.isEmpty, rateUSD > 0 else { completion?(nil); return }
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalLabel = trimmedLabel.isEmpty ? "1-on-1" : trimmedLabel
        let docRef = agreedRatesDocRef(coachId: coachId, clientId: clientId)
        docRef.getDocument { snap, _ in
            var rates = snap?.data()?["Rates"] as? [[String: Any]] ?? []
            rates.removeAll { ($0["label"] as? String)?.lowercased() == finalLabel.lowercased() }
            rates.append(["label": finalLabel, "rateUSD": rateUSD])
            let payload: [String: Any] = [
                "CoachID": coachId,
                "ClientID": clientId,
                "Rates": rates,
                "updatedAt": FieldValue.serverTimestamp()
            ]
            docRef.setData(payload, merge: true) { err in
                if let err = err { print("[FirestoreManager] saveAgreedRate error: \(err)") }
                completion?(err)
            }
        }
    }

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
                && lhs.notes == rhs.notes
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

    struct ChatItem: Identifiable, Equatable {
        let id: String
        let participants: [String]
        let lastMessageText: String?
        let lastMessageAt: Date?
        /// Per-user hide state: uid -> when they hid the chat. A chat stays
        /// hidden for a user until a message newer than their hide time arrives.
        var hiddenBy: [String: Date] = [:]

        func isHidden(for uid: String) -> Bool {
            guard !uid.isEmpty, let hiddenAt = hiddenBy[uid] else { return false }
            guard let last = lastMessageAt else { return true }
            return last <= hiddenAt
        }
    }

    /// Hide or unhide a chat for the current user only. Hiding writes a
    /// timestamp so the chat automatically reappears when a new message arrives.
    func setChatHidden(chatId: String, hidden: Bool, completion: ((Error?) -> Void)? = nil) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion?(NSError(domain: "FirestoreManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]))
            return
        }
        let payload: [String: Any] = [
            "hiddenBy.\(uid)": hidden ? Timestamp(date: Date()) : FieldValue.delete()
        ]
        db.collection("chats").document(chatId).updateData(payload) { err in
            if let err = err { print("setChatHidden error: \(err)") }
            completion?(err)
        }
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

        // If user type hasn't loaded yet, defer and retry after a short delay
        if !userTypeLoaded {
            print("listenForChatsForCurrentUser: userType not loaded yet, will retry in 0.5s")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.listenForChatsForCurrentUser()
            }
            return
        }

        // Stop previous listeners if any
        chatsListener?.remove()
        chatsListener = nil
        chatsListenerSecondary?.remove()
        chatsListenerSecondary = nil
        chatsListenerLegacy?.remove()
        chatsListenerLegacy = nil

        print("listenForChatsForCurrentUser: registering listeners for uid=\(uid) userType=\(self.currentUserType ?? "nil")")

        // Create references for both possible collections (coaches and clients)
        // This ensures we find chats regardless of how the participant was added
        let coachRef = db.collection("coaches").document(uid)
        let clientRef = db.collection("clients").document(uid)

        // Track results from all queries to merge them
        var coachChats: [ChatItem] = []
        var clientChats: [ChatItem] = []
        var legacyChats: [ChatItem] = []
        var coachOtherUids: Set<String> = []
        var clientOtherUids: Set<String> = []
        var legacyOtherUids: Set<String> = []

        // Helper to merge and publish results
        let mergeAndPublish: () -> Void = { [weak self] in
            guard let self = self else { return }
            // Combine chats from all queries, removing duplicates by id
            var seen = Set<String>()
            var merged: [ChatItem] = []
            for chat in (coachChats + clientChats + legacyChats) {
                if !seen.contains(chat.id) {
                    seen.insert(chat.id)
                    merged.append(chat)
                }
            }
            // Sort by lastMessageAt descending
            merged.sort { ($0.lastMessageAt ?? .distantPast) > ($1.lastMessageAt ?? .distantPast) }

            DispatchQueue.main.async {
                self.chats = merged
                self.chatsDebug = "Loaded \(merged.count) chats"
                let ids = merged.map { $0.id }
                if !ids.isEmpty { self.loadPreviewsForChats(chatIds: ids) }
            }

            // Resolve participant names and photos up-front for the whole list,
            // instead of lazily per-row (which made avatars appear seconds late)
            let allOtherUids = coachOtherUids.union(clientOtherUids).union(legacyOtherUids)
            if !allOtherUids.isEmpty {
                DispatchQueue.main.async {
                    self.ensureParticipantNames(Array(allOtherUids))
                    for uid in allOtherUids {
                        self.fetchAndCacheUserPhotoURL(uid: uid)
                    }
                }
            }
        }

        // Query 1: Chats where user is referenced as a coach
        // Note: We don't use orderBy here to avoid requiring a composite Firestore index.
        // Sorting is done locally in mergeAndPublish().
        let coachQuery = db.collection("chats").whereField("participantRefs", arrayContains: coachRef)
        chatsListener = coachQuery.addSnapshotListener { [weak self] snap, err in
            guard let self = self else { return }
            if let err = err {
                print("listenForChatsForCurrentUser (coach): error: \(err.localizedDescription)")
            }
            let docs = snap?.documents ?? []
            coachChats = []
            coachOtherUids = []
            for d in docs {
                let data = d.data()
                let id = d.documentID
                var participantsArr: [String] = []
                if let refs = data["participantRefs"] as? [DocumentReference] {
                    participantsArr = refs.map { $0.documentID }
                } else if let strArr = data["participants"] as? [String] {
                    participantsArr = strArr
                }
                // Seed participant name/photo caches from the chat's denormalized maps
                self.seedParticipantInfo(fromChatData: data)
                let lastText = data["lastMessageText"] as? String
                let lastAt = (data["lastMessageAt"] as? Timestamp)?.dateValue()
                var hiddenBy: [String: Date] = [:]
                if let rawHidden = data["hiddenBy"] as? [String: Timestamp] {
                    for (k, v) in rawHidden { hiddenBy[k] = v.dateValue() }
                }
                coachChats.append(ChatItem(id: id, participants: participantsArr, lastMessageText: lastText, lastMessageAt: lastAt, hiddenBy: hiddenBy))
                for p in participantsArr where p != uid { coachOtherUids.insert(p) }
            }
            mergeAndPublish()
        }

        // Query 2: Chats where user is referenced as a client
        // Note: We don't use orderBy here to avoid requiring a composite Firestore index.
        // Sorting is done locally in mergeAndPublish().
        let clientQuery = db.collection("chats").whereField("participantRefs", arrayContains: clientRef)
        chatsListenerSecondary = clientQuery.addSnapshotListener { [weak self] snap, err in
            guard let self = self else { return }
            if let err = err {
                print("listenForChatsForCurrentUser (client): error: \(err.localizedDescription)")
            }
            let docs = snap?.documents ?? []
            clientChats = []
            clientOtherUids = []
            for d in docs {
                let data = d.data()
                let id = d.documentID
                var participantsArr: [String] = []
                if let refs = data["participantRefs"] as? [DocumentReference] {
                    participantsArr = refs.map { $0.documentID }
                } else if let strArr = data["participants"] as? [String] {
                    participantsArr = strArr
                }
                // Seed participant name/photo caches from the chat's denormalized maps
                self.seedParticipantInfo(fromChatData: data)
                let lastText = data["lastMessageText"] as? String
                let lastAt = (data["lastMessageAt"] as? Timestamp)?.dateValue()
                var hiddenBy: [String: Date] = [:]
                if let rawHidden = data["hiddenBy"] as? [String: Timestamp] {
                    for (k, v) in rawHidden { hiddenBy[k] = v.dateValue() }
                }
                clientChats.append(ChatItem(id: id, participants: participantsArr, lastMessageText: lastText, lastMessageAt: lastAt, hiddenBy: hiddenBy))
                for p in participantsArr where p != uid { clientOtherUids.insert(p) }
            }
            mergeAndPublish()
        }

        // Query 3: Legacy chats where user is in participants string array (for backward compatibility)
        // Note: We don't use orderBy here to avoid requiring a composite Firestore index.
        // Sorting is done locally in mergeAndPublish().
        let legacyQuery = db.collection("chats").whereField("participants", arrayContains: uid)
        chatsListenerLegacy = legacyQuery.addSnapshotListener { [weak self] snap, err in
            guard let self = self else { return }
            if let err = err {
                print("listenForChatsForCurrentUser (legacy): error: \(err.localizedDescription)")
            }
            let docs = snap?.documents ?? []
            legacyChats = []
            legacyOtherUids = []
            for d in docs {
                let data = d.data()
                let id = d.documentID
                var participantsArr: [String] = []
                if let refs = data["participantRefs"] as? [DocumentReference] {
                    participantsArr = refs.map { $0.documentID }
                } else if let strArr = data["participants"] as? [String] {
                    participantsArr = strArr
                }
                // Seed participant name/photo caches from the chat's denormalized maps
                self.seedParticipantInfo(fromChatData: data)
                let lastText = data["lastMessageText"] as? String
                let lastAt = (data["lastMessageAt"] as? Timestamp)?.dateValue()
                var hiddenBy: [String: Date] = [:]
                if let rawHidden = data["hiddenBy"] as? [String: Timestamp] {
                    for (k, v) in rawHidden { hiddenBy[k] = v.dateValue() }
                }
                legacyChats.append(ChatItem(id: id, participants: participantsArr, lastMessageText: lastText, lastMessageAt: lastAt, hiddenBy: hiddenBy))
                for p in participantsArr where p != uid { legacyOtherUids.insert(p) }
            }
            mergeAndPublish()
        }
    }

    // Secondary chat listener for querying both collections
    private var chatsListenerSecondary: ListenerRegistration?
    // Tertiary chat listener for legacy participants string array
    private var chatsListenerLegacy: ListenerRegistration?

    /// Debug function to inspect all chats in the database and their structure.
    /// Also attempts to find chats for the current user and load them directly.
    func debugFetchAllChats() {
        guard let uid = Auth.auth().currentUser?.uid else {
            print("DEBUG: No authenticated user")
            return
        }
        print("DEBUG: Fetching all chats to inspect structure... (current uid=\(uid))")
        db.collection("chats").limit(to: 50).getDocuments { [weak self] snap, err in
            guard let self = self else { return }
            if let err = err {
                print("DEBUG: Error fetching chats: \(err)")
                return
            }
            let docs = snap?.documents ?? []
            print("DEBUG: Found \(docs.count) total chats in database")

            var userChats: [ChatItem] = []
            var otherUids: Set<String> = []

            for doc in docs {
                let data = doc.data()
                print("DEBUG: Chat \(doc.documentID):")

                var participantsArr: [String] = []
                var userInChat = false

                if let refs = data["participantRefs"] as? [DocumentReference] {
                    print("  - participantRefs (DocumentReference[]): \(refs.map { $0.path })")
                    participantsArr = refs.map { $0.documentID }
                    userInChat = refs.contains { $0.documentID == uid }
                } else if let refs = data["participantRefs"] {
                    print("  - participantRefs (unknown type): \(type(of: refs)) = \(refs)")
                } else {
                    print("  - participantRefs: nil")
                }

                if let parts = data["participants"] as? [String] {
                    print("  - participants (String[]): \(parts)")
                    if participantsArr.isEmpty {
                        // Extract UIDs from participants - they might be paths like "coaches/uid" or just "uid"
                        participantsArr = parts.map { p in
                            if p.contains("/") {
                                return String(p.split(separator: "/").last ?? Substring(p))
                            }
                            return p
                        }
                    }
                    userInChat = userInChat || parts.contains(uid) || parts.contains { $0.contains(uid) }
                } else if let parts = data["participants"] {
                    print("  - participants (unknown type): \(type(of: parts)) = \(parts)")
                } else {
                    print("  - participants: nil")
                }

                print("  - lastMessageAt: \(data["lastMessageAt"] ?? "nil")")
                print("  - lastMessageText: \(data["lastMessageText"] ?? "nil")")
                print("  - currentUserInChat: \(userInChat)")

                // If user is in this chat, add it to our list
                if userInChat {
                    let lastText = data["lastMessageText"] as? String
                    let lastAt = (data["lastMessageAt"] as? Timestamp)?.dateValue()
                    userChats.append(ChatItem(id: doc.documentID, participants: participantsArr, lastMessageText: lastText, lastMessageAt: lastAt))
                    for p in participantsArr where p != uid { otherUids.insert(p) }
                }
            }

            print("DEBUG: Found \(userChats.count) chats for current user")

            // If we found chats but the main listeners didn't, load them directly
            if !userChats.isEmpty && self.chats.isEmpty {
                print("DEBUG: Main listeners found no chats, but debug found \(userChats.count). Loading directly...")
                userChats.sort { ($0.lastMessageAt ?? .distantPast) > ($1.lastMessageAt ?? .distantPast) }
                DispatchQueue.main.async {
                    self.chats = userChats
                    self.chatsDebug = "DEBUG loaded \(userChats.count) chats"
                    let ids = userChats.map { $0.id }
                    if !ids.isEmpty { self.loadPreviewsForChats(chatIds: ids) }
                }
                if !otherUids.isEmpty {
                    self.ensureParticipantNames(Array(otherUids))
                }
            }
        }
    }

    // Original single-query listener kept for reference but replaced above
    private func listenForChatsForCurrentUserSingleQuery() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let userTypeUpper = (self.currentUserType ?? "").uppercased()
        let userCollName = (userTypeUpper == "COACH") ? "coaches" : "clients"
        let userRef = db.collection(userCollName).document(uid)
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
                // Seed participant name/photo caches from the chat's denormalized maps
                self.seedParticipantInfo(fromChatData: data)
                let lastText = data["lastMessageText"] as? String
                let lastAt = (data["lastMessageAt"] as? Timestamp)?.dateValue()
                var hiddenBy: [String: Date] = [:]
                if let rawHidden = data["hiddenBy"] as? [String: Timestamp] {
                    for (k, v) in rawHidden { hiddenBy[k] = v.dateValue() }
                }
                mapped.append(ChatItem(id: id, participants: participantsArr, lastMessageText: lastText, lastMessageAt: lastAt, hiddenBy: hiddenBy))

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
        if let l = chatsListenerSecondary { l.remove(); chatsListenerSecondary = nil }
        if let l = chatsListenerLegacy { l.remove(); chatsListenerLegacy = nil }
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
    // MARK: - Participant display info helpers

    /// Resolve a display name from a profile document, handling every field
    /// convention in use: `name`/`Name` (client docs) and `FirstName`/`LastName`
    /// (coach docs and clients created by older flows / the Android app).
    static func profileDisplayName(from data: [String: Any]) -> String {
        if let n = (data["name"] as? String) ?? (data["Name"] as? String) {
            let trimmed = n.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
        let first = ((data["FirstName"] as? String) ?? (data["firstName"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
        let last = ((data["LastName"] as? String) ?? (data["lastName"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
        return [first, last].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Resolve a raw photo path/URL string from a profile document.
    static func profilePhotoString(from data: [String: Any]) -> String? {
        let p = (data["photoURL"] as? String) ?? (data["PhotoURL"] as? String) ?? (data["photoUrl"] as? String)
        if let p = p, !p.isEmpty { return p }
        return nil
    }

    /// Fetch a user's display name and raw photo string, checking coaches then
    /// clients. Falls through to the clients doc when the coaches doc exists but
    /// carries no usable name (stub docs).
    func fetchUserDisplayInfo(uid: String, completion: @escaping (String?, String?) -> Void) {
        guard !uid.isEmpty else { completion(nil, nil); return }
        db.collection("coaches").document(uid).getDocument { snap, _ in
            if let data = snap?.data(), snap?.exists == true {
                let name = Self.profileDisplayName(from: data)
                if !name.isEmpty {
                    completion(name, Self.profilePhotoString(from: data))
                    return
                }
            }
            self.db.collection("clients").document(uid).getDocument { csnap, _ in
                guard let cdata = csnap?.data(), csnap?.exists == true else {
                    completion(nil, nil)
                    return
                }
                let name = Self.profileDisplayName(from: cdata)
                completion(name.isEmpty ? nil : name, Self.profilePhotoString(from: cdata))
            }
        }
    }

    /// Seed the in-memory participant caches from a chat document's denormalized
    /// `participantNames` / `participantPhotoURLs` maps, so names and avatars
    /// render even before (or without) a live profile lookup.
    func seedParticipantInfo(fromChatData data: [String: Any]) {
        if let nameMap = data["participantNames"] as? [String: String] {
            for (pid, nm) in nameMap where !nm.isEmpty {
                let cached = participantNames[pid]
                if cached == nil || cached == pid {
                    DispatchQueue.main.async { self.participantNames[pid] = nm }
                }
            }
        }
        if let photoMap = data["participantPhotoURLs"] as? [String: String] {
            for (pid, ps) in photoMap where !ps.isEmpty {
                if coachPhotoURLs[pid] ?? nil == nil, clientPhotoURLs[pid] ?? nil == nil {
                    resolvePhotoURL(ps) { url in
                        DispatchQueue.main.async {
                            if self.coachPhotoURLs[pid] ?? nil == nil, self.clientPhotoURLs[pid] ?? nil == nil {
                                self.clientPhotoURLs[pid] = url
                            }
                        }
                    }
                }
            }
        }
    }

    /// Write the given user's current display name and photo onto the chat doc's
    /// denormalized maps. Called when a user opens a chat so the other side
    /// always has fresh info to display (self-healing for legacy chats).
    func updateChatParticipantInfo(chatId: String, uid: String) {
        guard !chatId.isEmpty, !uid.isEmpty else { return }
        fetchUserDisplayInfo(uid: uid) { name, photo in
            var payload: [String: Any] = [:]
            if let n = name, !n.isEmpty { payload["participantNames.\(uid)"] = n }
            if let p = photo, !p.isEmpty { payload["participantPhotoURLs.\(uid)"] = p }
            guard !payload.isEmpty else { return }
            self.db.collection("chats").document(chatId).updateData(payload) { err in
                if let err = err { print("updateChatParticipantInfo: \(err.localizedDescription)") }
            }
        }
    }

    func ensureParticipantNames(_ uids: [String]) {
        // Treat a cached value equal to the UID itself as unresolved — an early
        // failed lookup must not permanently block resolution (previously these
        // only recovered via the 5-second polling timer in MessagesView).
        let missing = uids.filter { self.participantNames[$0] == nil || self.participantNames[$0] == $0 }
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
                        let name = Self.profileDisplayName(from: data)
                        // Only treat the coach doc as authoritative when it carries a
                        // usable name; otherwise fall through to the clients lookup
                        // (stub coach docs would otherwise mask a real client profile).
                        guard !name.isEmpty else { continue }
                        DispatchQueue.main.async { self.participantNames[id] = name }

                        // cache photo URL for coach if present
                        if let ps = Self.profilePhotoString(from: data) {
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
                            let name = Self.profileDisplayName(from: cdata)
                            DispatchQueue.main.async { self.participantNames[id] = name.isEmpty ? id : name }

                            // cache client photo URL if present
                            if let ps = Self.profilePhotoString(from: cdata) {
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

    /// Force refresh participant names by directly fetching from Firestore (bypassing cache).
    /// Call this when pull-to-refresh is triggered or when names appear as UIDs.
    func forceRefreshParticipantNames(for uids: [String]) {
        guard !uids.isEmpty else { return }

        // Clear cached names for these UIDs so UI shows loading state
        for uid in uids {
            // Only clear if it looks like a UID (not a real name)
            if let cached = participantNames[uid], looksLikeUID(cached) {
                participantNames.removeValue(forKey: uid)
            }
        }

        // Fetch directly from Firestore with source: .server to bypass cache
        fetchParticipantNamesFromServer(uids)
    }

    /// Check if a string looks like a Firebase UID
    private func looksLikeUID(_ str: String) -> Bool {
        return str.count >= 20 && !str.contains(" ") && str.allSatisfy { $0.isLetter || $0.isNumber }
    }

    /// Fetch participant names directly from server, bypassing Firestore cache
    private func fetchParticipantNamesFromServer(_ uids: [String]) {
        // Chunk into groups of 10 (Firestore 'in' query limit)
        let chunks = stride(from: 0, to: uids.count, by: 10).map {
            Array(uids[$0..<min($0 + 10, uids.count)])
        }

        for chunk in chunks {
            // Query coaches first
            db.collection("coaches").whereField(FieldPath.documentID(), in: chunk)
                .getDocuments(source: .server) { [weak self] snap, err in
                    guard let self = self else { return }
                    if let err = err {
                        print("forceRefreshParticipantNames (coaches): \(err.localizedDescription)")
                    }

                    var foundIds: Set<String> = []
                    if let docs = snap?.documents {
                        for doc in docs {
                            let id = doc.documentID
                            let data = doc.data()
                            let first = (data["FirstName"] as? String ?? "").trimmingCharacters(in: .whitespaces)
                            let last = (data["LastName"] as? String ?? "").trimmingCharacters(in: .whitespaces)
                            let name = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
                            if !name.isEmpty {
                                DispatchQueue.main.async { self.participantNames[id] = name }
                                foundIds.insert(id)
                            }
                            // Also update photo URL
                            if let photoStr = (data["PhotoURL"] as? String) ?? (data["photoURL"] as? String), !photoStr.isEmpty {
                                self.resolvePhotoURL(photoStr) { url in
                                    DispatchQueue.main.async { self.coachPhotoURLs[id] = url }
                                }
                            }
                        }
                    }

                    // Query clients for remaining UIDs
                    let remaining = chunk.filter { !foundIds.contains($0) }
                    if remaining.isEmpty { return }

                    self.db.collection("clients").whereField(FieldPath.documentID(), in: remaining)
                        .getDocuments(source: .server) { [weak self] csnap, cerr in
                            guard let self = self else { return }
                            if let cerr = cerr {
                                print("forceRefreshParticipantNames (clients): \(cerr.localizedDescription)")
                            }

                            var foundClientIds: Set<String> = []
                            if let cdocs = csnap?.documents {
                                for cdoc in cdocs {
                                    let id = cdoc.documentID
                                    let cdata = cdoc.data()
                                    let name = Self.profileDisplayName(from: cdata)
                                    if !name.isEmpty {
                                        DispatchQueue.main.async { self.participantNames[id] = name }
                                        foundClientIds.insert(id)
                                    }
                                    // Also update photo URL
                                    if let photoStr = (cdata["photoURL"] as? String) ?? (cdata["PhotoURL"] as? String), !photoStr.isEmpty {
                                        self.resolvePhotoURL(photoStr) { url in
                                            DispatchQueue.main.async { self.clientPhotoURLs[id] = url }
                                        }
                                    }
                                }
                            }

                            // For UIDs still not found, schedule a retry after a delay
                            let stillMissing = remaining.filter { !foundClientIds.contains($0) }
                            if !stillMissing.isEmpty {
                                // Retry after 2 seconds - the profile might still be creating
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                                    self?.retryFetchParticipantNames(stillMissing, attempt: 1)
                                }
                            }
                        }
                }
        }
    }

    /// Retry fetching participant names with exponential backoff
    private func retryFetchParticipantNames(_ uids: [String], attempt: Int) {
        guard attempt <= 3 else {
            // Give up after 3 attempts, use UID as fallback
            for uid in uids where participantNames[uid] == nil {
                DispatchQueue.main.async { self.participantNames[uid] = uid }
            }
            return
        }

        print("retryFetchParticipantNames: attempt \(attempt) for \(uids.count) UIDs")

        // Check coaches
        db.collection("coaches").whereField(FieldPath.documentID(), in: uids)
            .getDocuments(source: .server) { [weak self] snap, _ in
                guard let self = self else { return }
                var found: Set<String> = []
                if let docs = snap?.documents {
                    for doc in docs {
                        let id = doc.documentID
                        let data = doc.data()
                        let first = (data["FirstName"] as? String ?? "").trimmingCharacters(in: .whitespaces)
                        let last = (data["LastName"] as? String ?? "").trimmingCharacters(in: .whitespaces)
                        let name = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
                        if !name.isEmpty {
                            DispatchQueue.main.async { self.participantNames[id] = name }
                            found.insert(id)
                        }
                    }
                }

                let remaining = uids.filter { !found.contains($0) }
                if remaining.isEmpty { return }

                // Check clients
                self.db.collection("clients").whereField(FieldPath.documentID(), in: remaining)
                    .getDocuments(source: .server) { [weak self] csnap, _ in
                        guard let self = self else { return }
                        var foundClients: Set<String> = []
                        if let cdocs = csnap?.documents {
                            for cdoc in cdocs {
                                let id = cdoc.documentID
                                let cdata = cdoc.data()
                                let name = Self.profileDisplayName(from: cdata)
                                if !name.isEmpty {
                                    DispatchQueue.main.async { self.participantNames[id] = name }
                                    foundClients.insert(id)
                                }
                            }
                        }

                        let stillMissing = remaining.filter { !foundClients.contains($0) }
                        if !stillMissing.isEmpty {
                            // Retry again with exponential backoff
                            let delay = Double(attempt + 1) * 2.0
                            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                                self?.retryFetchParticipantNames(stillMissing, attempt: attempt + 1)
                            }
                        }
                    }
            }
    }

    /// Refresh all participant names for current chats
    func refreshAllParticipantNames() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        var allParticipants: Set<String> = []
        for chat in chats {
            for p in chat.participants where p != uid {
                allParticipants.insert(p)
            }
        }
        if !allParticipants.isEmpty {
            forceRefreshParticipantNames(for: Array(allParticipants))
        }
    }

    /// Return the best-known photo URL for a participant (coach first, then client).
    /// The caches are [String: URL?] — an entry explicitly cached as nil ("no
    /// photo found") must NOT mask a real URL in the other cache, so flatten
    /// both levels explicitly instead of chaining `??`.
    func participantPhotoURL(_ uid: String) -> URL? {
        if let entry = coachPhotoURLs[uid], let url = entry { return url }
        if let entry = clientPhotoURLs[uid], let url = entry { return url }
        return nil
    }

    /// Fetch and cache the photo URL for an arbitrary user UID.
    /// Checks both coaches and clients collections. Skips the fetch if the UID
    /// is already cached (including a cached nil — explicit absence).
    func fetchAndCacheUserPhotoURL(uid: String) {
        guard !uid.isEmpty else { return }
        // Skip if already cached
        if coachPhotoURLs.keys.contains(uid) || clientPhotoURLs.keys.contains(uid) { return }

        let coachRef = db.collection("coaches").document(uid)
        coachRef.getDocument { [weak self] snap, _ in
            guard let self = self else { return }
            // Only stop at the coach doc when it actually carries a photo —
            // a stub coach doc must not mask a client profile's photo.
            if let data = snap?.data(), let photoStr = Self.profilePhotoString(from: data) {
                self.resolvePhotoURL(photoStr) { url in
                    DispatchQueue.main.async { self.coachPhotoURLs[uid] = url }
                }
                return
            }
            // Fall back to clients collection
            self.db.collection("clients").document(uid).getDocument { snap, _ in
                let data = snap?.data() ?? [:]
                self.resolvePhotoURL(Self.profilePhotoString(from: data)) { url in
                    DispatchQueue.main.async { self.clientPhotoURLs[uid] = url }
                }
            }
        }
    }

    /// Write the current user's lastSeen timestamp to their Firestore profile document.
    func updateLastSeen() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let timestamp = FieldValue.serverTimestamp()
        // Use updateData (not setData) so that if the document doesn't exist the call
        // fails silently rather than creating a bare {"lastSeen": ...} document that
        // overwrites the real profile on the next full write.
        db.collection("clients").document(uid).updateData(["lastSeen": timestamp]) { _ in }
        db.collection("coaches").document(uid).updateData(["lastSeen": timestamp]) { _ in }
    }

    /// Fetch lastSeen timestamps for a list of client IDs and populate clientLastSeen.
    func fetchLastSeen(for clientIds: [String]) {
        guard !clientIds.isEmpty else { return }
        let chunks = stride(from: 0, to: clientIds.count, by: 10).map {
            Array(clientIds[$0..<min($0 + 10, clientIds.count)])
        }
        for chunk in chunks {
            db.collection("clients").whereField(FieldPath.documentID(), in: chunk)
                .getDocuments { [weak self] snap, _ in
                    guard let self = self else { return }
                    for doc in snap?.documents ?? [] {
                        if let ts = doc.data()["lastSeen"] as? Timestamp {
                            DispatchQueue.main.async {
                                self.clientLastSeen[doc.documentID] = ts.dateValue()
                            }
                        }
                    }
                    // Also try coaches collection for clients who happen to be coaches
                    let found = Set((snap?.documents ?? []).map { $0.documentID })
                    let remaining = chunk.filter { !found.contains($0) }
                    guard !remaining.isEmpty else { return }
                    self.db.collection("coaches").whereField(FieldPath.documentID(), in: remaining)
                        .getDocuments { [weak self] csnap, _ in
                            guard let self = self else { return }
                            for doc in csnap?.documents ?? [] {
                                if let ts = doc.data()["lastSeen"] as? Timestamp {
                                    DispatchQueue.main.async {
                                        self.clientLastSeen[doc.documentID] = ts.dateValue()
                                    }
                                }
                            }
                        }
                }
        }
    }

    func stopListeningForMessages(chatId: String) {
        if let l = messageListeners[chatId] { l.remove(); messageListeners.removeValue(forKey: chatId) }
        DispatchQueue.main.async { self.messagesByChat[chatId] = [] }
    }

    func stopAllChatListeners() {
        if let l = chatsListener { l.remove(); chatsListener = nil }
        if let l = chatsListenerSecondary { l.remove(); chatsListenerSecondary = nil }
        if let l = chatsListenerLegacy { l.remove(); chatsListenerLegacy = nil }
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
                 self.updateLastSeen()
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
                      self.userTypeLoaded = false
                      self.currentAdditionalTypes = []
                      self.profilesLoaded = false
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
                let first = (data["FirstName"] as? String ?? "").trimmingCharacters(in: .whitespaces)
                let last = (data["LastName"] as? String ?? "").trimmingCharacters(in: .whitespaces)
                let name = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
                let specialties = data["Specialties"] as? [String] ?? []
                let experience = data["ExperienceYears"] as? Int ?? (data["ExperienceYears"] as? Double).flatMap { Int($0) } ?? 0
                let availability = data["Availability"] as? [String] ?? []
                let bio = data["Bio"] as? String
                let hourlyRate = data["HourlyRate"] as? Double
                let rateRange = data["RateRange"] as? [Double]
                let tierRaw = data["subscriptionTier"] as? String ?? "free"
                let subscriptionTier = CoachTier(rawValue: tierRaw) ?? .free
                let phoneVerified = data["phoneVerified"] as? Bool ?? false
                let linkedPlaceIds = data["linkedPlaceIds"] as? [String] ?? []

                mapped.append(Coach(id: id, name: name, specialties: specialties, experienceYears: experience, availability: availability, bio: bio, hourlyRate: hourlyRate, rateRange: rateRange, subscriptionTier: subscriptionTier, phoneVerified: phoneVerified, linkedPlaceIds: linkedPlaceIds))

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
                    let first = ((data["FirstName"] as? String) ?? (data["firstName"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
                    let last = ((data["LastName"] as? String) ?? (data["lastName"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
                    nameVal = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
                }
                let tsLink = data["tournamentSoftwareLink"] as? String
                // resolve photo URL if present
                let photoStr = (data["photoURL"] as? String) ?? (data["PhotoURL"] as? String) ?? (data["photoUrl"] as? String)
                if let ps = photoStr, !ps.isEmpty {
                    self.resolvePhotoURL(ps) { url in
                        DispatchQueue.main.async {
                            results.append(UserSummary(id: id, name: nameVal.isEmpty ? id : nameVal, photoURL: url, tournamentSoftwareLink: tsLink))
                            // after processing all docs we'll assign below; but assign incrementally for responsiveness
                            self.clients = results.sorted { $0.name.lowercased() < $1.name.lowercased() }
                        }
                    }
                } else {
                    results.append(UserSummary(id: id, name: nameVal.isEmpty ? id : nameVal, photoURL: nil, tournamentSoftwareLink: tsLink))
                    DispatchQueue.main.async {
                        self.clients = results.sorted { $0.name.lowercased() < $1.name.lowercased() }
                    }
                }
            }
        }
    }

    // MARK: - Signup Events

    func fetchSignupEvents() {
        self.db.collection("signupEvents").order(by: "eventDate").getDocuments { snap, err in
            if let err = err {
                print("fetchSignupEvents error: \(err)")
                return
            }
            let docs = snap?.documents ?? []
            var results: [SignupEvent] = []
            for d in docs {
                let data = d.data()
                let id = d.documentID
                let title = data["title"] as? String ?? ""
                let description = data["description"] as? String ?? ""
                let location = data["location"] as? String ?? ""
                let placeId = data["placeId"] as? String ?? ""
                let placeName = data["placeName"] as? String ?? ""
                let createdBy = data["createdBy"] as? String ?? ""
                let maxSignups = data["maxSignups"] as? Int ?? 0
                let signupCount = data["signupCount"] as? Int ?? 0
                let eventDate: Date
                if let ts = data["eventDate"] as? Timestamp {
                    eventDate = ts.dateValue()
                } else {
                    eventDate = Date()
                }
                var signups: [SignupEventSignup] = []
                if let raw = data["signups"] as? [String: Any] {
                    for (key, value) in raw {
                        if let info = value as? [String: Any] {
                            let name = info["name"] as? String ?? ""
                            let email = info["email"] as? String ?? ""
                            let userId = info["userId"] as? String
                            let signedUpAt: Date
                            if let ts = info["signedUpAt"] as? Timestamp {
                                signedUpAt = ts.dateValue()
                            } else {
                                signedUpAt = Date()
                            }
                            let paid = info["paid"] as? Bool ?? false
                            signups.append(SignupEventSignup(id: key, name: name, email: email, userId: userId, signedUpAt: signedUpAt, paid: paid))
                        }
                    }
                }
                signups.sort { $0.signedUpAt < $1.signedUpAt }
                var waitlist: [SignupEventSignup] = []
                if let raw = data["waitlist"] as? [String: Any] {
                    for (key, value) in raw {
                        if let info = value as? [String: Any] {
                            let joinedAt = (info["joinedAt"] as? Timestamp)?.dateValue() ?? Date()
                            waitlist.append(SignupEventSignup(
                                id: key,
                                name: info["name"] as? String ?? "",
                                email: info["email"] as? String ?? "",
                                userId: info["userId"] as? String,
                                signedUpAt: joinedAt,
                                paid: false
                            ))
                        }
                    }
                }
                waitlist.sort { $0.signedUpAt < $1.signedUpAt }
                results.append(SignupEvent(id: id, title: title, description: description, eventDate: eventDate, location: location, placeId: placeId, placeName: placeName, maxSignups: maxSignups, signupCount: signupCount, createdBy: createdBy, signups: signups, waitlist: waitlist))
            }
            DispatchQueue.main.async {
                self.signupEvents = results
            }
        }
    }

    func createSignupEvent(title: String, description: String, eventDate: Date, location: String, placeId: String, placeName: String, maxSignups: Int, completion: @escaping (Error?) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(NSError(domain: "FirestoreManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]))
            return
        }
        let data: [String: Any] = [
            "title": title,
            "description": description,
            "eventDate": Timestamp(date: eventDate),
            "location": location,
            "placeId": placeId,
            "placeName": placeName,
            "maxSignups": maxSignups,
            "signupCount": 0,
            "createdBy": uid,
            "createdAt": FieldValue.serverTimestamp(),
            "signups": [String: Any]()
        ]
        self.db.collection("signupEvents").addDocument(data: data) { err in
            if let err = err {
                print("createSignupEvent error: \(err)")
                completion(err)
                return
            }
            DispatchQueue.main.async {
                self.fetchSignupEvents()
            }
            completion(nil)
        }
    }

    func signupForEvent(eventId: String, completion: ((Error?) -> Void)? = nil) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion?(NSError(domain: "FirestoreManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]))
            return
        }
        let userName: String = {
            if let name = self.currentClient?.name, !name.isEmpty { return name }
            if let coach = self.currentCoach, !coach.name.isEmpty { return coach.name }
            return "Unknown"
        }()
        let userEmail = Auth.auth().currentUser?.email ?? ""
        let ref = self.db.collection("signupEvents").document(eventId)
        self.db.runTransaction({ (transaction, errorPointer) -> Any? in
            let snapshot: DocumentSnapshot
            do {
                try snapshot = transaction.getDocument(ref)
            } catch let fetchError as NSError {
                errorPointer?.pointee = fetchError
                return nil
            }
            guard let data = snapshot.data() else {
                let err = NSError(domain: "FirestoreManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Event not found"])
                errorPointer?.pointee = err
                return nil
            }
            let currentCount = data["signupCount"] as? Int ?? 0
            let maxSignups = data["maxSignups"] as? Int ?? 0
            if currentCount >= maxSignups {
                let err = NSError(domain: "FirestoreManager", code: 409, userInfo: [NSLocalizedDescriptionKey: "This event is full"])
                errorPointer?.pointee = err
                return nil
            }
            // Check if user already signed up
            if let signups = data["signups"] as? [String: Any] {
                for (_, value) in signups {
                    if let info = value as? [String: Any], let existingUid = info["userId"] as? String, existingUid == uid {
                        let err = NSError(domain: "FirestoreManager", code: 409, userInfo: [NSLocalizedDescriptionKey: "You're already signed up"])
                        errorPointer?.pointee = err
                        return nil
                    }
                }
            }
            let key = UUID().uuidString
            let signupData: [String: Any] = [
                "name": userName,
                "email": userEmail,
                "userId": uid,
                "signedUpAt": Timestamp(date: Date()),
                "paid": false
            ]
            transaction.updateData([
                "signups.\(key)": signupData,
                "signupCount": FieldValue.increment(Int64(1))
            ], forDocument: ref)
            return nil
        }) { [weak self] _, error in
            if let error = error {
                print("signupForEvent error: \(error)")
                completion?(error)
                return
            }
            DispatchQueue.main.async { self?.fetchSignupEvents() }
            completion?(nil)
        }
    }

    func removeSignupFromEvent(eventId: String, signupId: String, completion: ((Error?) -> Void)? = nil) {
        let ref = self.db.collection("signupEvents").document(eventId)
        ref.updateData([
            "signups.\(signupId)": FieldValue.delete(),
            "signupCount": FieldValue.increment(Int64(-1))
        ]) { [weak self] err in
            if let err = err {
                print("removeSignupFromEvent error: \(err)")
                completion?(err)
                return
            }
            // A spot just opened — promote the first person on the waitlist, if any
            self?.promoteFromWaitlist(eventId: eventId)
            DispatchQueue.main.async { self?.fetchSignupEvents() }
            completion?(nil)
        }
    }

    // MARK: - Event Waitlist

    func joinEventWaitlist(eventId: String, completion: ((Error?) -> Void)? = nil) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion?(NSError(domain: "FirestoreManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]))
            return
        }
        let userName: String = {
            if let name = self.currentClient?.name, !name.isEmpty { return name }
            if let coach = self.currentCoach, !coach.name.isEmpty { return coach.name }
            return "Unknown"
        }()
        let userEmail = Auth.auth().currentUser?.email ?? ""
        let key = UUID().uuidString
        self.db.collection("signupEvents").document(eventId).updateData([
            "waitlist.\(key)": [
                "name": userName,
                "email": userEmail,
                "userId": uid,
                "joinedAt": Timestamp(date: Date())
            ]
        ]) { [weak self] err in
            if err == nil { DispatchQueue.main.async { self?.fetchSignupEvents() } }
            completion?(err)
        }
    }

    func leaveEventWaitlist(eventId: String, completion: ((Error?) -> Void)? = nil) {
        guard let uid = Auth.auth().currentUser?.uid else { completion?(nil); return }
        let ref = self.db.collection("signupEvents").document(eventId)
        ref.getDocument { [weak self] snap, _ in
            guard let raw = snap?.data()?["waitlist"] as? [String: Any] else { completion?(nil); return }
            let key = raw.first { (_, value) in
                ((value as? [String: Any])?["userId"] as? String) == uid
            }?.key
            guard let key = key else { completion?(nil); return }
            ref.updateData(["waitlist.\(key)": FieldValue.delete()]) { err in
                if err == nil { DispatchQueue.main.async { self?.fetchSignupEvents() } }
                completion?(err)
            }
        }
    }

    /// Move the earliest-joined waitlist entry into signups when capacity allows, and notify them.
    private func promoteFromWaitlist(eventId: String) {
        let ref = self.db.collection("signupEvents").document(eventId)
        ref.getDocument { [weak self] snap, _ in
            guard let self = self, let data = snap?.data() else { return }
            let count = data["signupCount"] as? Int ?? 0
            let max = data["maxSignups"] as? Int ?? 0
            guard count < max, let raw = data["waitlist"] as? [String: Any], !raw.isEmpty else { return }

            // Earliest joinedAt goes first
            var firstKey: String? = nil
            var firstInfo: [String: Any] = [:]
            var firstDate = Date.distantFuture
            for (key, value) in raw {
                guard let info = value as? [String: Any] else { continue }
                let joined = (info["joinedAt"] as? Timestamp)?.dateValue() ?? .distantPast
                if joined < firstDate {
                    firstDate = joined
                    firstKey = key
                    firstInfo = info
                }
            }
            guard let key = firstKey else { return }

            ref.updateData([
                "waitlist.\(key)": FieldValue.delete(),
                "signups.\(key)": [
                    "name": firstInfo["name"] as? String ?? "",
                    "email": firstInfo["email"] as? String ?? "",
                    "userId": firstInfo["userId"] as? String ?? "",
                    "signedUpAt": Timestamp(date: Date()),
                    "paid": false
                ],
                "signupCount": FieldValue.increment(Int64(1))
            ]) { err in
                guard err == nil else { return }
                if let promotedUid = firstInfo["userId"] as? String, !promotedUid.isEmpty {
                    let title = data["title"] as? String ?? "an event"
                    let notifRef = self.db.collection("pendingNotifications").document(promotedUid).collection("notifications").document()
                    notifRef.setData([
                        "title": "You're in!",
                        "body": "A spot opened up in \"\(title)\" — you've been moved off the waitlist.",
                        "type": "event_waitlist_promoted",
                        "eventId": eventId,
                        "placeId": data["placeId"] as? String ?? "",
                        "createdAt": FieldValue.serverTimestamp(),
                        "delivered": false
                    ]) { _ in }
                }
                DispatchQueue.main.async { self.fetchSignupEvents() }
            }
        }
    }

    func toggleSignupPaid(eventId: String, signupId: String, paid: Bool) {
        let ref = self.db.collection("signupEvents").document(eventId)
        ref.updateData(["signups.\(signupId).paid": paid]) { [weak self] err in
            if let err = err {
                print("toggleSignupPaid error: \(err)")
                return
            }
            DispatchQueue.main.async { self?.fetchSignupEvents() }
        }
    }

    func updateSignupEventCapacity(eventId: String, newMax: Int, completion: ((Error?) -> Void)? = nil) {
        let ref = self.db.collection("signupEvents").document(eventId)
        ref.updateData(["maxSignups": newMax]) { [weak self] err in
            if let err = err {
                print("updateSignupEventCapacity error: \(err)")
                completion?(err)
                return
            }
            DispatchQueue.main.async { self?.fetchSignupEvents() }
            completion?(nil)
        }
    }

    func deleteSignupEvent(id: String, completion: ((Error?) -> Void)? = nil) {
        self.db.collection("signupEvents").document(id).delete { [weak self] err in
            if let err = err {
                print("deleteSignupEvent error: \(err)")
                completion?(err)
                return
            }
            DispatchQueue.main.async { self?.fetchSignupEvents() }
            completion?(nil)
        }
    }

    // MARK: - Tournaments

    func fetchTournaments() {
        self.db.collection("tournaments").order(by: "startDate").getDocuments { snap, err in
            if let err = err {
                print("fetchTournaments error: \(err)")
                return
            }
            let docs = snap?.documents ?? []
            var results: [Tournament] = []
            for d in docs {
                let data = d.data()
                let id = d.documentID
                let name = data["name"] as? String ?? ""
                let location = data["location"] as? String ?? ""
                let createdBy = data["createdBy"] as? String ?? ""
                let startDate: Date
                if let ts = data["startDate"] as? Timestamp {
                    startDate = ts.dateValue()
                } else {
                    startDate = Date()
                }
                let endDate: Date
                if let ts = data["endDate"] as? Timestamp {
                    endDate = ts.dateValue()
                } else {
                    endDate = Calendar.current.date(byAdding: .day, value: 1, to: startDate) ?? startDate
                }
                let signupLink = data["signupLink"] as? String
                var participantsMap: [String: TournamentParticipantInfo] = [:]
                if let raw = data["participants"] as? [String: Any] {
                    for (uid, value) in raw {
                        if let info = value as? [String: Any] {
                            let gender = info["gender"] as? String ?? ""
                            let events = info["events"] as? [String] ?? []
                            let skillLevels = info["skillLevels"] as? [String] ?? []
                            participantsMap[uid] = TournamentParticipantInfo(gender: gender, events: events, skillLevels: skillLevels)
                        }
                    }
                }
                results.append(Tournament(id: id, name: name, startDate: startDate, endDate: endDate, location: location, createdBy: createdBy, signupLink: signupLink, participants: participantsMap))
            }
            DispatchQueue.main.async {
                self.tournaments = results
            }
        }
    }

    func createTournament(name: String, startDate: Date, endDate: Date, location: String, signupLink: String? = nil, completion: @escaping (Error?) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(NSError(domain: "FirestoreManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]))
            return
        }
        var data: [String: Any] = [
            "name": name,
            "startDate": Timestamp(date: startDate),
            "endDate": Timestamp(date: endDate),
            "location": location,
            "createdBy": uid,
            "createdAt": FieldValue.serverTimestamp()
        ]
        if let link = signupLink, !link.isEmpty {
            data["signupLink"] = link
        }
        self.db.collection("tournaments").addDocument(data: data) { err in
            if let err = err {
                print("createTournament error: \(err)")
                completion(err)
                return
            }
            DispatchQueue.main.async {
                self.fetchTournaments()
            }
            completion(nil)
        }
    }

    func joinTournament(tournamentId: String, gender: String, events: [String], skillLevels: [String], completion: ((Error?) -> Void)? = nil) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion?(NSError(domain: "FirestoreManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]))
            return
        }
        let info: [String: Any] = [
            "gender": gender,
            "events": events,
            "skillLevels": skillLevels
        ]
        let ref = self.db.collection("tournaments").document(tournamentId)
        ref.updateData(["participants.\(uid)": info]) { err in
            if let err = err {
                print("joinTournament error: \(err)")
                completion?(err)
                return
            }
            DispatchQueue.main.async { self.fetchTournaments() }
            completion?(nil)
        }
    }

    func leaveTournament(tournamentId: String, completion: ((Error?) -> Void)? = nil) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion?(NSError(domain: "FirestoreManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]))
            return
        }
        let ref = self.db.collection("tournaments").document(tournamentId)
        ref.updateData(["participants.\(uid)": FieldValue.delete()]) { err in
            if let err = err {
                print("leaveTournament error: \(err)")
                completion?(err)
                return
            }
            DispatchQueue.main.async { self.fetchTournaments() }
            completion?(nil)
        }
    }

    // MARK: - Places to Play

    private var placesToPlayListener: ListenerRegistration? = nil

    /// Attach a live snapshot listener so club data (pending join requests,
    /// members, admins) updates automatically — no manual refresh needed for
    /// approve/reject buttons to appear when a join request comes in.
    func fetchPlacesToPlay() {
        // Already listening — the snapshot listener keeps data fresh.
        if placesToPlayListener != nil { return }
        placesToPlayListener = self.db.collection("placesToPlay").order(by: "createdAt", descending: true).addSnapshotListener { [weak self] snap, err in
            guard let self = self else { return }
            if let err = err {
                print("fetchPlacesToPlay listener error: \(err)")
                return
            }
            let docs = snap?.documents ?? []
            let results: [PlaceToPlay] = docs.compactMap { d in
                let data = d.data()
                let name = data["name"] as? String ?? ""
                guard !name.isEmpty else { return nil }
                var timesMap: [String: String] = [:]
                if let raw = data["playingTimes"] as? [String: String] {
                    timesMap = raw
                } else if let raw = data["playingTimes"] as? [String: Any] {
                    for (k, v) in raw { timesMap[k] = "\(v)" }
                }
                var members: [ClubMember] = []
                if let raw = data["members"] as? [String: Any] {
                    for (uid, value) in raw {
                        if let info = value as? [String: Any] {
                            let mName = info["name"] as? String ?? ""
                            let joinedAt: Date
                            if let ts = info["joinedAt"] as? Timestamp { joinedAt = ts.dateValue() } else { joinedAt = Date() }
                            members.append(ClubMember(id: uid, name: mName, joinedAt: joinedAt))
                        }
                    }
                }
                members.sort { $0.joinedAt < $1.joinedAt }

                var pendingMembers: [ClubMember] = []
                if let raw = data["pendingMembers"] as? [String: Any] {
                    for (uid, value) in raw {
                        if let info = value as? [String: Any] {
                            let mName = info["name"] as? String ?? ""
                            let requestedAt: Date
                            if let ts = info["requestedAt"] as? Timestamp { requestedAt = ts.dateValue() } else { requestedAt = Date() }
                            pendingMembers.append(ClubMember(id: uid, name: mName, joinedAt: requestedAt))
                        }
                    }
                }
                pendingMembers.sort { $0.joinedAt < $1.joinedAt }

                // Club admins: new multi-admin map, with legacy contactUid fallback
                let contactUid = data["contactUid"] as? String
                let contactName = data["contactName"] as? String
                var admins: [ClubMember] = []
                if let raw = data["admins"] as? [String: Any] {
                    for (uid, value) in raw {
                        if let info = value as? [String: Any] {
                            let aName = info["name"] as? String ?? ""
                            let addedAt: Date
                            if let ts = info["addedAt"] as? Timestamp { addedAt = ts.dateValue() } else { addedAt = Date() }
                            admins.append(ClubMember(id: uid, name: aName, joinedAt: addedAt))
                        }
                    }
                }
                if admins.isEmpty, let cUid = contactUid, !cUid.isEmpty {
                    admins = [ClubMember(id: cUid, name: contactName ?? "Club Admin", joinedAt: Date())]
                }
                admins.sort { $0.joinedAt < $1.joinedAt }

                return PlaceToPlay(
                    id: d.documentID,
                    name: name,
                    address: data["address"] as? String ?? "",
                    playingTimes: timesMap,
                    pricePerSession: data["pricePerSession"] as? String ?? "",
                    createdBy: data["createdBy"] as? String ?? "",
                    contactUid: contactUid,
                    contactName: contactName,
                    admins: admins,
                    members: members,
                    pendingMembers: pendingMembers
                )
            }
            DispatchQueue.main.async {
                self.placesToPlay = results
            }
        }
    }

    func addPlaceToPlay(name: String, address: String, playingTimes: [String: String], pricePerSession: String, completion: @escaping (Error?) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(NSError(domain: "FirestoreManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]))
            return
        }
        let data: [String: Any] = [
            "name": name,
            "address": address,
            "playingTimes": playingTimes,
            "pricePerSession": pricePerSession,
            "createdBy": uid,
            "createdAt": FieldValue.serverTimestamp()
        ]
        self.db.collection("placesToPlay").addDocument(data: data) { err in
            if let err = err {
                print("addPlaceToPlay error: \(err)")
                completion(err)
                return
            }
            DispatchQueue.main.async { self.fetchPlacesToPlay() }
            completion(nil)
        }
    }

    func deletePlaceToPlay(id: String, completion: ((Error?) -> Void)? = nil) {
        self.db.collection("placesToPlay").document(id).delete { err in
            if let err = err {
                print("deletePlaceToPlay error: \(err)")
                completion?(err)
                return
            }
            DispatchQueue.main.async { self.fetchPlacesToPlay() }
            completion?(nil)
        }
    }

    /// Add the current user as a club admin. A club can have multiple admins:
    /// each admin is stored in the `admins` map; the legacy `contactUid`/
    /// `contactName` fields are still maintained (first admin) for compatibility.
    func assignPlaceContact(placeId: String, completion: @escaping (Error?) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(NSError(domain: "FirestoreManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]))
            return
        }
        let adminName: String = {
            if let name = self.currentClient?.name, !name.isEmpty { return name }
            if let coach = self.currentCoach, !coach.name.isEmpty { return coach.name }
            return "Club Admin"
        }()
        var payload: [String: Any] = [
            "admins.\(uid)": [
                "name": adminName,
                "addedAt": Timestamp(date: Date())
            ],
            "members.\(uid)": [
                "name": adminName,
                "joinedAt": Timestamp(date: Date())
            ]
        ]
        // Keep the legacy single-contact fields pointing at the first admin
        let place = self.placesToPlay.first(where: { $0.id == placeId })
        if place?.contactUid == nil || place?.contactUid?.isEmpty == true {
            payload["contactUid"] = uid
            payload["contactName"] = adminName
        }
        self.db.collection("placesToPlay").document(placeId).updateData(payload) { err in
            if let err = err {
                print("assignPlaceContact error: \(err)")
                completion(err)
                return
            }
            completion(nil)
        }
    }

    /// Remove the current user from the club's admins. If they were the legacy
    /// contact, promote another remaining admin into the legacy fields.
    func removePlaceContact(placeId: String, completion: @escaping (Error?) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(NSError(domain: "FirestoreManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]))
            return
        }
        var payload: [String: Any] = [
            "admins.\(uid)": FieldValue.delete()
        ]
        let place = self.placesToPlay.first(where: { $0.id == placeId })
        if place?.contactUid == uid {
            if let next = place?.admins.first(where: { $0.id != uid }) {
                payload["contactUid"] = next.id
                payload["contactName"] = next.name
            } else {
                payload["contactUid"] = FieldValue.delete()
                payload["contactName"] = FieldValue.delete()
            }
        }
        self.db.collection("placesToPlay").document(placeId).updateData(payload) { err in
            if let err = err {
                print("removePlaceContact error: \(err)")
                completion(err)
                return
            }
            completion(nil)
        }
    }

    // MARK: - Club Membership

    func requestToJoinClub(placeId: String, completion: ((Error?) -> Void)? = nil) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion?(NSError(domain: "FirestoreManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]))
            return
        }
        let userName: String = {
            if let name = self.currentClient?.name, !name.isEmpty { return name }
            if let coach = self.currentCoach, !coach.name.isEmpty { return coach.name }
            return "Unknown"
        }()
        let ref = self.db.collection("placesToPlay").document(placeId)
        ref.updateData([
            "pendingMembers.\(uid)": [
                "name": userName,
                "requestedAt": Timestamp(date: Date())
            ]
        ]) { [weak self] err in
            if let err = err {
                print("requestToJoinClub error: \(err)")
                completion?(err)
                return
            }
            // Notify every club admin
            if let place = self?.placesToPlay.first(where: { $0.id == placeId }) {
                for adminId in place.adminIds where !adminId.isEmpty && adminId != uid {
                    let notifRef = Firestore.firestore().collection("pendingNotifications").document(adminId).collection("notifications").document()
                    notifRef.setData([
                        "title": "New Club Join Request",
                        "body": "\(userName) wants to join \(place.name)",
                        "type": "club_join_request",
                        "placeId": placeId,
                        "senderId": uid,
                        "createdAt": FieldValue.serverTimestamp(),
                        "delivered": false
                    ]) { _ in }
                }
            }
            DispatchQueue.main.async { self?.fetchPlacesToPlay() }
            completion?(nil)
        }
    }

    func approveClubMember(placeId: String, userId: String, completion: ((Error?) -> Void)? = nil) {
        guard let place = self.placesToPlay.first(where: { $0.id == placeId }),
              let pending = place.pendingMembers.first(where: { $0.id == userId }) else {
            completion?(NSError(domain: "FirestoreManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Pending member not found"]))
            return
        }
        let ref = self.db.collection("placesToPlay").document(placeId)
        ref.updateData([
            "pendingMembers.\(userId)": FieldValue.delete(),
            "members.\(userId)": [
                "name": pending.name,
                "joinedAt": Timestamp(date: Date())
            ]
        ]) { [weak self] err in
            if let err = err {
                print("approveClubMember error: \(err)")
                completion?(err)
                return
            }
            // Notify the approved member
            let notifRef = Firestore.firestore().collection("pendingNotifications").document(userId).collection("notifications").document()
            notifRef.setData([
                "title": "Welcome to \(place.name)!",
                "body": "Your request to join \(place.name) has been approved.",
                "type": "club_approved",
                "placeId": placeId,
                "createdAt": FieldValue.serverTimestamp(),
                "delivered": false
            ]) { _ in }
            DispatchQueue.main.async { self?.fetchPlacesToPlay() }
            completion?(nil)
        }
    }

    func rejectClubMember(placeId: String, userId: String, completion: ((Error?) -> Void)? = nil) {
        let ref = self.db.collection("placesToPlay").document(placeId)
        ref.updateData([
            "pendingMembers.\(userId)": FieldValue.delete()
        ]) { [weak self] err in
            if let err = err {
                print("rejectClubMember error: \(err)")
                completion?(err)
                return
            }
            DispatchQueue.main.async { self?.fetchPlacesToPlay() }
            completion?(nil)
        }
    }

    func removeClubMember(placeId: String, userId: String, completion: ((Error?) -> Void)? = nil) {
        let ref = self.db.collection("placesToPlay").document(placeId)
        ref.updateData([
            "members.\(userId)": FieldValue.delete()
        ]) { [weak self] err in
            if let err = err {
                print("removeClubMember error: \(err)")
                completion?(err)
                return
            }
            DispatchQueue.main.async { self?.fetchPlacesToPlay() }
            completion?(nil)
        }
    }

    func leaveClub(placeId: String, completion: ((Error?) -> Void)? = nil) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion?(NSError(domain: "FirestoreManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]))
            return
        }
        let ref = self.db.collection("placesToPlay").document(placeId)
        ref.updateData([
            "members.\(uid)": FieldValue.delete()
        ]) { [weak self] err in
            if let err = err {
                print("leaveClub error: \(err)")
                completion?(err)
                return
            }
            DispatchQueue.main.async { self?.fetchPlacesToPlay() }
            completion?(nil)
        }
    }

    /// Send an announcement to all club members. The notification title is
    /// always the club's name so recipients immediately know which club sent it.
    func sendClubAnnouncement(placeId: String, body: String, completion: ((Error?) -> Void)? = nil) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion?(NSError(domain: "FirestoreManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]))
            return
        }
        guard let place = self.placesToPlay.first(where: { $0.id == placeId }) else {
            completion?(NSError(domain: "FirestoreManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Place not found"]))
            return
        }
        let memberIds = place.members.map { $0.id }
        guard !memberIds.isEmpty else {
            completion?(NSError(domain: "FirestoreManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "No members to notify"]))
            return
        }

        // The club name IS the announcement title
        let title = place.name

        // Determine sender name for the stored announcement
        let senderName = self.currentCoach?.name ?? self.currentClient?.name ?? "Unknown"

        // 1. Store the announcement in the club's subcollection
        let announcementRef = self.db.collection("placesToPlay").document(placeId).collection("announcements").document()
        let announcementId = announcementRef.documentID
        announcementRef.setData([
            "title": title,
            "body": body,
            "senderName": senderName,
            "createdBy": uid,
            "createdAt": FieldValue.serverTimestamp()
        ]) { [weak self] err in
            if let err = err {
                print("sendClubAnnouncement: failed to store announcement: \(err)")
                completion?(err)
                return
            }
            // 2. Send push notifications to all members with the announcementId
            let batch = self?.db.batch()
            for memberId in memberIds where memberId != uid {
                if let notifRef = self?.db.collection("pendingNotifications").document(memberId).collection("notifications").document() {
                    batch?.setData([
                        "title": title,
                        "body": body,
                        "type": "club_announcement",
                        "placeId": placeId,
                        "announcementId": announcementId,
                        "senderId": uid,
                        "createdAt": FieldValue.serverTimestamp(),
                        "delivered": false
                    ], forDocument: notifRef)
                }
            }
            batch?.commit { err in
                if let err = err {
                    print("sendClubAnnouncement notification error: \(err)")
                    completion?(err)
                    return
                }
                completion?(nil)
            }
        }
    }

    private var clubAnnouncementListeners: [String: ListenerRegistration] = [:]

    /// Attach a live snapshot listener for a club's announcements so new
    /// announcements appear automatically (e.g. while a member is viewing the
    /// announcements screen when the push notification arrives) — no manual
    /// refresh needed.
    func fetchClubAnnouncements(placeId: String) {
        // Already listening — the snapshot listener keeps data fresh.
        if clubAnnouncementListeners[placeId] != nil { return }
        clubAnnouncementListeners[placeId] = self.db.collection("placesToPlay").document(placeId).collection("announcements")
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snap, err in
                if let err = err {
                    print("fetchClubAnnouncements listener error: \(err)")
                    return
                }
                let docs = snap?.documents ?? []
                let results: [ClubAnnouncement] = docs.compactMap { d in
                    let data = d.data()
                    let title = data["title"] as? String ?? ""
                    let body = data["body"] as? String ?? ""
                    let senderName = data["senderName"] as? String ?? "Unknown"
                    let createdBy = data["createdBy"] as? String ?? ""
                    let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                    return ClubAnnouncement(
                        id: d.documentID,
                        placeId: placeId,
                        title: title,
                        body: body,
                        senderName: senderName,
                        createdBy: createdBy,
                        createdAt: createdAt
                    )
                }
                DispatchQueue.main.async {
                    self?.clubAnnouncements[placeId] = results
                }
            }
    }

    // MARK: - Players to Play With

    func fetchPlayersToPlayWith() {
        self.db.collection("playersToPlayWith")
            .order(by: "createdAt", descending: true)
            .getDocuments { snap, err in
                if let err = err {
                    print("fetchPlayersToPlayWith error: \(err)")
                    return
                }
                let docs = snap?.documents ?? []
                let results: [PlayerToPlayWith] = docs.compactMap { d in
                    let data = d.data()
                    let name = data["name"] as? String ?? ""
                    guard !name.isEmpty else { return nil }
                    let ts = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                    return PlayerToPlayWith(
                        id: d.documentID,
                        name: name,
                        skillLevel: data["skillLevel"] as? String ?? "",
                        city: data["city"] as? String ?? "",
                        availability: data["availability"] as? [String] ?? [],
                        connectedVenueIds: data["connectedVenueIds"] as? [String] ?? [],
                        createdBy: data["createdBy"] as? String ?? d.documentID,
                        createdAt: ts
                    )
                }
                DispatchQueue.main.async {
                    self.playersToPlayWith = results
                }
            }
    }

    func addPlayerToPlayWith(skillLevel: String? = nil, city: String? = nil, availability: [String]? = nil, connectedVenueIds: [String] = [], completion: @escaping (Error?) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(NSError(domain: "FirestoreManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]))
            return
        }
        // Name always auto-filled from profile
        let name: String = {
            if let n = self.currentClient?.name, !n.isEmpty { return n }
            if let c = self.currentCoach, !c.name.isEmpty { return c.name }
            return "Player"
        }()
        let resolvedSkillLevel: String = skillLevel ?? {
            if let s = self.currentClient?.skillLevel, !s.isEmpty { return s }
            return ""
        }()
        let resolvedCity: String = city ?? {
            if let c = self.currentClient?.city, !c.isEmpty { return c }
            if let c = self.currentCoach?.city, !c.isEmpty { return c }
            return ""
        }()
        let resolvedAvailability: [String] = availability ?? {
            if let a = self.currentClient?.preferredAvailability, !a.isEmpty { return a }
            if let a = self.currentCoach?.availability, !a.isEmpty { return a }
            return []
        }()
        let data: [String: Any] = [
            "name": name,
            "skillLevel": resolvedSkillLevel,
            "city": resolvedCity,
            "availability": resolvedAvailability,
            "connectedVenueIds": connectedVenueIds,
            "createdBy": uid,
            "createdAt": FieldValue.serverTimestamp()
        ]
        self.db.collection("playersToPlayWith").document(uid).setData(data) { err in
            if let err = err {
                print("addPlayerToPlayWith error: \(err)")
                completion(err)
                return
            }
            DispatchQueue.main.async { self.fetchPlayersToPlayWith() }
            completion(nil)
        }
    }

    func updatePlayerToPlayWith(skillLevel: String, city: String, availability: [String], connectedVenueIds: [String], completion: @escaping (Error?) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(NSError(domain: "FirestoreManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]))
            return
        }
        let updates: [String: Any] = [
            "skillLevel": skillLevel,
            "city": city,
            "availability": availability,
            "connectedVenueIds": connectedVenueIds
        ]
        self.db.collection("playersToPlayWith").document(uid).updateData(updates) { err in
            if let err = err {
                print("updatePlayerToPlayWith error: \(err)")
                completion(err)
                return
            }
            DispatchQueue.main.async { self.fetchPlayersToPlayWith() }
            completion(nil)
        }
    }

    func deletePlayerToPlayWith(completion: ((Error?) -> Void)? = nil) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion?(NSError(domain: "FirestoreManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]))
            return
        }
        self.db.collection("playersToPlayWith").document(uid).delete { err in
            if let err = err {
                print("deletePlayerToPlayWith error: \(err)")
                completion?(err)
                return
            }
            DispatchQueue.main.async { self.fetchPlayersToPlayWith() }
            completion?(nil)
        }
    }

    // MARK: - Badminton Stringers

    func fetchStringers() {
        self.db.collection("stringers").order(by: "createdAt", descending: true).getDocuments { snap, err in
            if let err = err {
                print("fetchStringers error: \(err)")
                return
            }
            let docs = snap?.documents ?? []
            let results: [BadmintonStringer] = docs.compactMap { d in
                let data = d.data()
                let name = data["name"] as? String ?? ""
                guard !name.isEmpty else { return nil }
                var stringsMap: [String: String] = [:]
                if let raw = data["stringsOffered"] as? [String: String] {
                    stringsMap = raw
                } else if let raw = data["stringsOffered"] as? [String: Any] {
                    for (k, v) in raw { stringsMap[k] = "\(v)" }
                }
                // Parse rich meetup locations (with coordinates)
                var locations: [StringerLocation] = []
                if let rawLocs = data["meetupLocations"] as? [[String: Any]] {
                    for loc in rawLocs {
                        let locId = loc["id"] as? String ?? UUID().uuidString
                        let locName = loc["name"] as? String ?? ""
                        let locAddr = loc["address"] as? String ?? ""
                        let lat = loc["latitude"] as? Double ?? 0
                        let lng = loc["longitude"] as? Double ?? 0
                        if !locName.isEmpty {
                            locations.append(StringerLocation(id: locId, name: locName, address: locAddr, latitude: lat, longitude: lng))
                        }
                    }
                }
                return BadmintonStringer(
                    id: d.documentID,
                    name: name,
                    meetupLocationNames: data["meetupLocationNames"] as? [String] ?? [],
                    meetupLocations: locations,
                    stringsOffered: stringsMap,
                    laborCost: data["laborCost"] as? String ?? "",
                    createdBy: data["createdBy"] as? String ?? ""
                )
            }
            DispatchQueue.main.async {
                self.stringers = results
            }
        }
    }

    func addStringer(name: String, meetupLocationNames: [String], stringsOffered: [String: String], laborCost: String, meetupLocations: [StringerLocation] = [], completion: @escaping (Error?) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(NSError(domain: "FirestoreManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]))
            return
        }
        let locationsData: [[String: Any]] = meetupLocations.map { loc in
            [
                "id": loc.id,
                "name": loc.name,
                "address": loc.address,
                "latitude": loc.latitude,
                "longitude": loc.longitude
            ]
        }
        let data: [String: Any] = [
            "name": name,
            "meetupLocationNames": meetupLocationNames,
            "meetupLocations": locationsData,
            "stringsOffered": stringsOffered,
            "laborCost": laborCost,
            "createdBy": uid,
            "createdAt": FieldValue.serverTimestamp()
        ]
        // Use the user's UID as the document key so the Stringer collection is keyed by coach/client UID
        self.db.collection("stringers").document(uid).setData(data) { [weak self] err in
            if let err = err {
                print("addStringer error: \(err)")
                completion(err)
                return
            }
            // Auto-add "Stringer" to the user's additionalTypes so userType points to the Stringer collection
            self?.updateAdditionalTypes(add: ["Stringer"]) { _ in }
            DispatchQueue.main.async { self?.fetchStringers() }
            completion(nil)
        }
    }

    func deleteStringer(id: String, completion: ((Error?) -> Void)? = nil) {
        self.db.collection("stringers").document(id).delete { [weak self] err in
            if let err = err {
                print("deleteStringer error: \(err)")
                completion?(err)
                return
            }
            // Auto-remove "Stringer" from the user's additionalTypes
            self?.updateAdditionalTypes(remove: ["Stringer"]) { _ in }
            DispatchQueue.main.async { self?.fetchStringers() }
            completion?(nil)
        }
    }

    /// Adds a name-only location to the locations collection (no coordinates required).
    func addSimpleLocation(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Check if a location with this name already exists to avoid duplicates
        self.db.collection("locations").whereField("Name", isEqualTo: trimmed).getDocuments { snap, _ in
            if let docs = snap?.documents, !docs.isEmpty { return }
            let data: [String: Any] = [
                "Name": trimmed,
                "createdAt": FieldValue.serverTimestamp()
            ]
            self.db.collection("locations").addDocument(data: data) { err in
                if let err = err {
                    print("addSimpleLocation error: \(err)")
                }
            }
        }
    }

    private func markProfileFetchComplete() {
        pendingProfileFetches -= 1
        if pendingProfileFetches <= 0 {
            profilesLoaded = true
        }
    }

    func fetchCurrentProfiles(for uid: String) {
        DispatchQueue.main.async {
            self.profilesLoaded = false
            self.pendingProfileFetches = 2
        }

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
                    self.markProfileFetchComplete()
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
            let tournamentSoftwareLink = data["tournamentSoftwareLink"] as? String
            let phoneVerified = data["phoneVerified"] as? Bool ?? false

            let photoStr = (data["photoURL"] as? String) ?? (data["PhotoURL"] as? String)
            self.resolvePhotoURL(photoStr) { resolved in
                DispatchQueue.main.async {
                    self.currentClient = Client(id: id, name: name, goals: goals, preferredAvailability: preferredArr, meetingPreference: meetingPref, skillLevel: data["skillLevel"] as? String, zipCode: zip, city: city, bio: bio, tournamentSoftwareLink: tournamentSoftwareLink, phoneVerified: phoneVerified)
                    self.currentClientPhotoURL = resolved
                    if let r = resolved {
                        print("fetchCurrentProfiles: client photo resolved for \(id): \(r.absoluteString)")
                        self.fetchAndCacheTabImage(from: r)
                    } else {
                        print("fetchCurrentProfiles: no client photo for \(id)")
                        self.currentUserTabImage = nil
                    }
                    self.markProfileFetchComplete()
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
                    self.markProfileFetchComplete()
                }
                return
            }

            let id = snap?.documentID ?? uid
            let first = (data["FirstName"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let last = (data["LastName"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let name = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
            let specialties = data["Specialties"] as? [String] ?? []
            let experience = data["ExperienceYears"] as? Int ?? (data["ExperienceYears"] as? Double).flatMap { Int($0) } ?? 0
            let availability = data["Availability"] as? [String] ?? []
            let bio = data["Bio"] as? String
            let meetingPref = data["meetingPreference"] as? String
            let hourlyRate = data["HourlyRate"] as? Double
            let rateRange = data["RateRange"] as? [Double]
            let coachTournamentSoftwareLink = data["tournamentSoftwareLink"] as? String
            let coachTierRaw = data["subscriptionTier"] as? String ?? "free"
            let coachSubscriptionTier = CoachTier(rawValue: coachTierRaw) ?? .free
            let coachPhoneVerified = data["phoneVerified"] as? Bool ?? false
            let coachLinkedPlaceIds = data["linkedPlaceIds"] as? [String] ?? []

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

                    self.currentCoach = Coach(id: id, name: name, specialties: specialties, experienceYears: experience, availability: availability, bio: bio, hourlyRate: hourlyRate, meetingPreference: meetingPref, payments: paymentsMap, rateRange: rateRange, tournamentSoftwareLink: coachTournamentSoftwareLink, subscriptionTier: coachSubscriptionTier, phoneVerified: coachPhoneVerified, linkedPlaceIds: coachLinkedPlaceIds, cancellationWindowHours: data["cancellationWindowHours"] as? Int ?? 0)
                    self.currentCoachPhotoURL = resolved
                    if let r = resolved {
                        print("fetchCurrentProfiles: coach photo resolved for \(id): \(r.absoluteString)")
                        self.fetchAndCacheTabImage(from: r)
                    } else {
                        print("fetchCurrentProfiles: no coach photo for \(id)")
                        self.currentUserTabImage = nil
                    }
                    self.markProfileFetchComplete()
                }
            }
        }
    }

    // MARK: - Subscription Tier Sync

    private var subscriptionListener: ListenerRegistration?

    /// Listen for real-time updates to the coach's subscriptionTier field
    func startSubscriptionListener(for uid: String) {
        stopSubscriptionListener()
        subscriptionListener = db.collection("coaches").document(uid).addSnapshotListener { [weak self] snap, err in
            guard let self = self, let data = snap?.data() else { return }
            let tierRaw = data["subscriptionTier"] as? String ?? "free"
            let tier = CoachTier(rawValue: tierRaw) ?? .free
            DispatchQueue.main.async {
                if let current = self.currentCoach, current.subscriptionTier != tier {
                    // Update the coach with the new tier
                    let updated = Coach(
                        id: current.id,
                        name: current.name,
                        specialties: current.specialties,
                        experienceYears: current.experienceYears,
                        availability: current.availability,
                        bio: current.bio,
                        hourlyRate: current.hourlyRate,
                        meetingPreference: current.meetingPreference,
                        payments: current.payments,
                        rateRange: current.rateRange,
                        subscriptionTier: tier,
                        linkedPlaceIds: current.linkedPlaceIds
                    )
                    self.currentCoach = updated
                    // Sync the new tier into the coaches discovery list so
                    // MatchResultsView reflects the change without an app restart
                    if let idx = self.coaches.firstIndex(where: { $0.id == current.id }) {
                        self.coaches[idx] = updated
                    }
                }
            }
        }
    }

    func stopSubscriptionListener() {
        subscriptionListener?.remove()
        subscriptionListener = nil
    }

    /// Manually sync subscription tier from Stripe's customers/{uid}/subscriptions collection.
    /// Use this as a fallback if the Cloud Function hasn't updated the coach document yet.
    func syncSubscriptionTierFromStripe(for uid: String, completion: ((CoachTier) -> Void)? = nil) {
        print("syncSubscriptionTierFromStripe: starting for uid \(uid)")

        // First, get ALL subscriptions without filtering to debug
        let subsRef = db.collection("customers").document(uid).collection("subscriptions")
        subsRef.getDocuments { [weak self] snap, err in
            guard let self = self else { return }
            if let err = err {
                print("syncSubscriptionTierFromStripe error: \(err)")
                completion?(.free)
                return
            }

            let docs = snap?.documents ?? []
            print("syncSubscriptionTierFromStripe: found \(docs.count) subscription documents")

            let productTierMap: [String: CoachTier] = [
                "prod_Tv0RF9Dm4KZjT2": .free,
                "prod_Tv0JQpKyAVQGqT": .plus,
                "prod_Tv6632i5cd5MFL": .pro
            ]

            var highestTier: CoachTier = .free
            for doc in docs {
                let data = doc.data()
                let status = data["status"] as? String ?? "unknown"
                print("syncSubscriptionTierFromStripe: doc \(doc.documentID) status=\(status) data=\(data)")

                // Only consider active/trialing subscriptions
                guard status == "active" || status == "trialing" else { continue }

                // Product can be a string ID or a reference
                var productId: String? = nil
                if let p = data["product"] as? String {
                    productId = p
                } else if let ref = data["product"] as? DocumentReference {
                    productId = ref.documentID
                }
                // Also check items array
                if productId == nil, let items = data["items"] as? [[String: Any]], let first = items.first {
                    if let price = first["price"] as? [String: Any], let prod = price["product"] as? String {
                        productId = prod
                    }
                }

                print("syncSubscriptionTierFromStripe: extracted productId=\(productId ?? "nil")")

                if let pid = productId, let tier = productTierMap[pid] {
                    print("syncSubscriptionTierFromStripe: mapped to tier \(tier.rawValue)")
                    // Take the highest tier found
                    if tier == .pro { highestTier = .pro }
                    else if tier == .plus && highestTier != .pro { highestTier = .plus }
                }
            }

            print("syncSubscriptionTierFromStripe: final tier = \(highestTier.rawValue)")

            // Update coach document
            self.db.collection("coaches").document(uid).updateData(["subscriptionTier": highestTier.rawValue]) { err in
                if let err = err {
                    print("syncSubscriptionTierFromStripe: failed to update coach: \(err)")
                } else {
                    print("syncSubscriptionTierFromStripe: updated coach \(uid) to tier \(highestTier.rawValue)")
                    // Refresh the current coach
                    DispatchQueue.main.async {
                        self.fetchCurrentProfiles(for: uid)
                    }
                }
            }

            completion?(highestTier)
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
    func saveClient(id: String, name: String, goals: [String], preferredAvailability: [String], meetingPreference: String? = nil, meetingPreferenceClear: Bool = false, skillLevel: String? = nil, zipCode: String? = nil, city: String? = nil, bio: String? = nil, tournamentSoftwareLink: String? = nil, photoURL: String?, completion: @escaping (Error?) -> Void) {
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
        if let tsl = tournamentSoftwareLink { updateData["tournamentSoftwareLink"] = tsl }
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
    func saveCoachWithSchema(id: String, firstName: String, lastName: String, specialties: [String], availability: [String], experienceYears: Int, hourlyRate: Double?, meetingPreference: String? = nil, photoURL: String?, bio: String? = nil, zipCode: String? = nil, city: String? = nil, rateRange: [Double]? = nil, tournamentSoftwareLink: String? = nil, linkedPlaceIds: [String] = [], cancellationWindowHours: Int = 0, active: Bool = true, overwrite: Bool = false, completion: @escaping (Error?) -> Void) {
        // Base payload (do not include createdAt here yet so we can control whether it is written)
        var baseData: [String: Any] = [
            "FirstName": firstName,
            "LastName": lastName,
            "Specialties": specialties,
            "Availability": availability,
            "ExperienceYears": experienceYears,
            "Active": active,
            "linkedPlaceIds": linkedPlaceIds,
            "cancellationWindowHours": cancellationWindowHours
        ]
        if let hr = hourlyRate { baseData["HourlyRate"] = hr }
        if let p = photoURL { baseData["PhotoURL"] = p }
        if let b = bio { baseData["Bio"] = b }
        if let z = zipCode { baseData["ZipCode"] = z }
        if let c = city { baseData["City"] = c }
        if let mp = meetingPreference { baseData["meetingPreference"] = mp }
        if let rr = rateRange { baseData["RateRange"] = rr }
        if let tsl = tournamentSoftwareLink { baseData["tournamentSoftwareLink"] = tsl }

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

    /// Mark the current user's profile as phone-verified.
    /// Saves to userType/{uid} (user-level, always persists) plus any existing coach/client profiles.
    func setPhoneVerified(completion: ((Error?) -> Void)? = nil) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion?(NSError(domain: "FirestoreManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]))
            return
        }
        let data: [String: Any] = ["phoneVerified": true]
        let group = DispatchGroup()
        var lastError: Error?

        // Always write to userType/{uid} so verification persists at the user level
        group.enter()
        db.collection("userType").document(uid).setData(data, merge: true) { err in
            if let err = err { lastError = err }
            group.leave()
        }

        // Also write to whichever profile(s) exist
        if currentCoach != nil {
            group.enter()
            db.collection("coaches").document(uid).setData(data, merge: true) { err in
                if let err = err { lastError = err }
                group.leave()
            }
        }
        if currentClient != nil {
            group.enter()
            db.collection("clients").document(uid).setData(data, merge: true) { err in
                if let err = err { lastError = err }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            self?.currentUserPhoneVerified = true
            self?.fetchCurrentProfiles(for: uid)
            completion?(lastError)
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
                                let coachNote = data["CoachNote"] as? String
                                let status = data["Status"] as? String
                                let paymentStatus = data["PaymentStatus"] as? String
                                let rate = (data["RateUSD"] as? Double) ?? ((data["RateUSD"] as? Int).map { Double($0) })
                                // Group booking fields
                                let clientIDs = data["ClientIDs"] as? [String]
                                let clientNamesArr = data["ClientNames"] as? [String]
                                let coachIDs = data["CoachIDs"] as? [String]
                                let coachNamesArr = data["CoachNames"] as? [String]
                                let isGroupBooking = data["isGroupBooking"] as? Bool
                                let creatorID = data["creatorID"] as? String
                                let creatorType = data["creatorType"] as? String
                                let coachAcceptances = data["CoachAcceptances"] as? [String: Bool]
                                let clientConfirmations = data["ClientConfirmations"] as? [String: Bool]
                                let coachRates = data["CoachRates"] as? [String: Double]
                                let rejectionReason = data["rejectionReason"] as? String
                                let rejectedBy = data["rejectedBy"] as? String
                                let clientDeclineReason = data["clientDeclineReason"] as? String
                                let requiresPaymentUpfront = data["requiresPaymentUpfront"] as? Bool
                                let item = BookingItem(id: doc.documentID, clientID: clientID, clientName: clientName, coachID: coachID, coachName: coachName, startAt: startAt, endAt: endAt, location: location, notes: notes, status: status, paymentStatus: paymentStatus, RateUSD: rate, clientIDs: clientIDs, clientNames: clientNamesArr, coachIDs: coachIDs, coachNames: coachNamesArr, isGroupBooking: isGroupBooking, creatorID: creatorID, creatorType: creatorType, coachAcceptances: coachAcceptances, clientConfirmations: clientConfirmations, coachRates: coachRates, coachNote: coachNote, rejectionReason: rejectionReason, rejectedBy: rejectedBy, clientDeclineReason: clientDeclineReason, requiresPaymentUpfront: requiresPaymentUpfront, sessionRecap: data["sessionRecap"] as? String)
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
                            let coachNote = data["CoachNote"] as? String
                            let status = data["Status"] as? String
                            let paymentStatus = data["PaymentStatus"] as? String
                            let rate = (data["RateUSD"] as? Double) ?? ((data["RateUSD"] as? Int).map { Double($0) })
                            // Group booking fields
                            let clientIDs = data["ClientIDs"] as? [String]
                            let clientNamesArr = data["ClientNames"] as? [String]
                            let coachIDs = data["CoachIDs"] as? [String]
                            let coachNamesArr = data["CoachNames"] as? [String]
                            let isGroupBooking = data["isGroupBooking"] as? Bool
                            let creatorID = data["creatorID"] as? String
                            let creatorType = data["creatorType"] as? String
                            let coachAcceptances = data["CoachAcceptances"] as? [String: Bool]
                            let clientConfirmations = data["ClientConfirmations"] as? [String: Bool]
                            let coachRates = data["CoachRates"] as? [String: Double]
                            let rejectionReason = data["rejectionReason"] as? String
                            let rejectedBy = data["rejectedBy"] as? String
                            let clientDeclineReason = data["clientDeclineReason"] as? String
                            let requiresPaymentUpfront = data["requiresPaymentUpfront"] as? Bool
                            let item = BookingItem(id: doc.documentID, clientID: clientID, clientName: clientName, coachID: coachID, coachName: coachName, startAt: startAt, endAt: endAt, location: location, notes: notes, status: status, paymentStatus: paymentStatus, RateUSD: rate, clientIDs: clientIDs, clientNames: clientNamesArr, coachIDs: coachIDs, coachNames: coachNamesArr, isGroupBooking: isGroupBooking, creatorID: creatorID, creatorType: creatorType, coachAcceptances: coachAcceptances, clientConfirmations: clientConfirmations, coachRates: coachRates, coachNote: coachNote, rejectionReason: rejectionReason, rejectedBy: rejectedBy, clientDeclineReason: clientDeclineReason, requiresPaymentUpfront: requiresPaymentUpfront, sessionRecap: data["sessionRecap"] as? String)
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
                            let coachNote = data["CoachNote"] as? String
                            let status = data["Status"] as? String
                            let paymentStatus = data["PaymentStatus"] as? String
                            let rate = (data["RateUSD"] as? Double) ?? ((data["RateUSD"] as? Int).map { Double($0) })
                            // Group booking fields
                            let clientIDs = data["ClientIDs"] as? [String]
                            let clientNamesArr = data["ClientNames"] as? [String]
                            let coachIDs = data["CoachIDs"] as? [String]
                            let coachNamesArr = data["CoachNames"] as? [String]
                            let isGroupBooking = data["isGroupBooking"] as? Bool
                            let creatorID = data["creatorID"] as? String
                            let creatorType = data["creatorType"] as? String
                            let coachAcceptances = data["CoachAcceptances"] as? [String: Bool]
                            let clientConfirmations = data["ClientConfirmations"] as? [String: Bool]
                            let coachRates = data["CoachRates"] as? [String: Double]
                            let rejectionReason = data["rejectionReason"] as? String
                            let rejectedBy = data["rejectedBy"] as? String
                let clientDeclineReason = data["clientDeclineReason"] as? String
                            let requiresPaymentUpfront = data["requiresPaymentUpfront"] as? Bool
                            let item = BookingItem(id: doc.documentID, clientID: clientID, clientName: clientName, coachID: coachID, coachName: coachName, startAt: startAt, endAt: endAt, location: location, notes: notes, status: status, paymentStatus: paymentStatus, RateUSD: rate, clientIDs: clientIDs, clientNames: clientNamesArr, coachIDs: coachIDs, coachNames: coachNamesArr, isGroupBooking: isGroupBooking, creatorID: creatorID, creatorType: creatorType, coachAcceptances: coachAcceptances, clientConfirmations: clientConfirmations, coachRates: coachRates, coachNote: coachNote, rejectionReason: rejectionReason, rejectedBy: rejectedBy, clientDeclineReason: clientDeclineReason, requiresPaymentUpfront: requiresPaymentUpfront, sessionRecap: data["sessionRecap"] as? String)
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
                        let coachNote = data["CoachNote"] as? String
                        let status = data["Status"] as? String
                        let paymentStatus = data["PaymentStatus"] as? String
                        let rate = (data["RateUSD"] as? Double) ?? ((data["RateUSD"] as? Int).map { Double($0) })
                        // Group booking fields
                        let clientIDs = data["ClientIDs"] as? [String]
                        let clientNamesArr = data["ClientNames"] as? [String]
                        let coachIDs = data["CoachIDs"] as? [String]
                        let coachNamesArr = data["CoachNames"] as? [String]
                        let isGroupBooking = data["isGroupBooking"] as? Bool
                        let creatorID = data["creatorID"] as? String
                        let creatorType = data["creatorType"] as? String
                        let coachAcceptances = data["CoachAcceptances"] as? [String: Bool]
                        let clientConfirmations = data["ClientConfirmations"] as? [String: Bool]
                        let coachRates = data["CoachRates"] as? [String: Double]
                        let rejectionReason = data["rejectionReason"] as? String
                        let rejectedBy = data["rejectedBy"] as? String
                let clientDeclineReason = data["clientDeclineReason"] as? String
                        let requiresPaymentUpfront = data["requiresPaymentUpfront"] as? Bool
                        let item = BookingItem(id: doc.documentID, clientID: clientID, clientName: clientName, coachID: coachID, coachName: coachName, startAt: startAt, endAt: endAt, location: location, notes: notes, status: status, paymentStatus: paymentStatus, RateUSD: rate, clientIDs: clientIDs, clientNames: clientNamesArr, coachIDs: coachIDs, coachNames: coachNamesArr, isGroupBooking: isGroupBooking, creatorID: creatorID, creatorType: creatorType, coachAcceptances: coachAcceptances, clientConfirmations: clientConfirmations, coachRates: coachRates, coachNote: coachNote, rejectionReason: rejectionReason, rejectedBy: rejectedBy, clientDeclineReason: clientDeclineReason, requiresPaymentUpfront: requiresPaymentUpfront, sessionRecap: data["sessionRecap"] as? String)
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
                let coachNote = data["CoachNote"] as? String
                let paymentStatus = data["PaymentStatus"] as? String
                let rate = (data["RateUSD"] as? Double) ?? ((data["RateUSD"] as? Int).map { Double($0) })
                // Prefer denormalized coach name stored on booking doc
                let coachName = (data["CoachName"] as? String)
                    ?? (data["coachName"] as? String)
                    ?? (data["coach_name"] as? String)
                // Extract client name from booking doc
                let clientName = (data["ClientName"] as? String)
                    ?? (data["clientName"] as? String)
                    ?? (data["client_name"] as? String)
                // Group booking fields
                let clientIDs = data["ClientIDs"] as? [String]
                let clientNames = data["ClientNames"] as? [String]
                let coachIDs = data["CoachIDs"] as? [String]
                let coachNames = data["CoachNames"] as? [String]
                let isGroupBooking = data["isGroupBooking"] as? Bool
                let creatorID = data["creatorID"] as? String
                let creatorType = data["creatorType"] as? String
                let coachAcceptances = data["CoachAcceptances"] as? [String: Bool]
                let clientConfirmations = data["ClientConfirmations"] as? [String: Bool]
                let coachRates = data["CoachRates"] as? [String: Double]
                let rejectionReason = data["rejectionReason"] as? String
                let rejectedBy = data["rejectedBy"] as? String
                let clientDeclineReason = data["clientDeclineReason"] as? String
                let requiresPaymentUpfront = data["requiresPaymentUpfront"] as? Bool
                return BookingItem(id: id, clientID: clientID, clientName: clientName, coachID: coachId, coachName: coachName, startAt: startAt, endAt: endAt, location: location, notes: notes, status: status, paymentStatus: paymentStatus, RateUSD: rate, clientIDs: clientIDs, clientNames: clientNames, coachIDs: coachIDs, coachNames: coachNames, isGroupBooking: isGroupBooking, creatorID: creatorID, creatorType: creatorType, coachAcceptances: coachAcceptances, clientConfirmations: clientConfirmations, coachRates: coachRates, coachNote: coachNote, rejectionReason: rejectionReason, rejectedBy: rejectedBy, clientDeclineReason: clientDeclineReason, requiresPaymentUpfront: requiresPaymentUpfront, sessionRecap: data["sessionRecap"] as? String)
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
                let coachNote = data["CoachNote"] as? String
                let paymentStatus = data["PaymentStatus"] as? String
                let rate = (data["RateUSD"] as? Double) ?? ((data["RateUSD"] as? Int).map { Double($0) })
                // Prefer denormalized coach name stored on booking doc
                let coachName = (data["CoachName"] as? String)
                    ?? (data["coachName"] as? String)
                    ?? (data["coach_name"] as? String)
                // Extract client name from booking doc
                let clientName = (data["ClientName"] as? String)
                    ?? (data["clientName"] as? String)
                    ?? (data["client_name"] as? String)
                // Group booking fields
                let clientIDs = data["ClientIDs"] as? [String]
                let clientNames = data["ClientNames"] as? [String]
                let coachIDs = data["CoachIDs"] as? [String]
                let coachNames = data["CoachNames"] as? [String]
                let isGroupBooking = data["isGroupBooking"] as? Bool
                let creatorID = data["creatorID"] as? String
                let creatorType = data["creatorType"] as? String
                let coachAcceptances = data["CoachAcceptances"] as? [String: Bool]
                let clientConfirmations = data["ClientConfirmations"] as? [String: Bool]
                let coachRates = data["CoachRates"] as? [String: Double]
                let rejectionReason = data["rejectionReason"] as? String
                let rejectedBy = data["rejectedBy"] as? String
                let clientDeclineReason = data["clientDeclineReason"] as? String
                let requiresPaymentUpfront = data["requiresPaymentUpfront"] as? Bool
                return BookingItem(id: id, clientID: clientId, clientName: clientName, coachID: coachID, coachName: coachName, startAt: startAt, endAt: endAt, location: location, notes: notes, status: status, paymentStatus: paymentStatus, RateUSD: rate, clientIDs: clientIDs, clientNames: clientNames, coachIDs: coachIDs, coachNames: coachNames, isGroupBooking: isGroupBooking, creatorID: creatorID, creatorType: creatorType, coachAcceptances: coachAcceptances, clientConfirmations: clientConfirmations, coachRates: coachRates, coachNote: coachNote, rejectionReason: rejectionReason, rejectedBy: rejectedBy, clientDeclineReason: clientDeclineReason, requiresPaymentUpfront: requiresPaymentUpfront, sessionRecap: data["sessionRecap"] as? String)
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
            if let name = clientName { data["ClientName"] = name }
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

    /// Save a group booking with multiple coaches and/or multiple clients.
    /// Mirrors the booking to all participants' subcollections and updates all coaches' calendar arrays.
    func saveGroupBookingAndMirror(
        coachIds: [String],
        clientIds: [String],
        startAt: Date,
        endAt: Date,
        status: String = "requested",
        location: String? = nil,
        notes: String? = nil,
        creatorID: String,
        creatorType: String,
        completion: @escaping (Error?) -> Void
    ) {
        guard !coachIds.isEmpty, !clientIds.isEmpty else {
            completion(NSError(domain: "FirestoreManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "At least one coach and one client required"]))
            return
        }

        let bookingRef = self.db.collection("bookings").document()
        let bookingId = bookingRef.documentID

        // Fetch all coach and client names concurrently
        let group = DispatchGroup()
        var coachNames: [String: String] = [:]
        var clientNames: [String: String] = [:]

        for coachId in coachIds {
            group.enter()
            self.db.collection("coaches").document(coachId).getDocument { snap, _ in
                if let data = snap?.data() {
                    let firstName = data["FirstName"] as? String ?? ""
                    let lastName = data["LastName"] as? String ?? ""
                    let fullName = [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
                    if !fullName.isEmpty { coachNames[coachId] = fullName }
                }
                group.leave()
            }
        }

        for clientId in clientIds {
            group.enter()
            self.db.collection("clients").document(clientId).getDocument { snap, _ in
                if let data = snap?.data() {
                    let firstName = data["FirstName"] as? String ?? ""
                    let lastName = data["LastName"] as? String ?? ""
                    var fullName = [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
                    if fullName.isEmpty {
                        fullName = data["name"] as? String ?? ""
                    }
                    if !fullName.isEmpty { clientNames[clientId] = fullName }
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }

            // Build ordered arrays of names
            let coachNamesArray = coachIds.map { coachNames[$0] ?? $0 }
            let clientNamesArray = clientIds.map { clientNames[$0] ?? $0 }

            // Initialize coach acceptances - all false initially
            let coachAcceptances = Dictionary(uniqueKeysWithValues: coachIds.map { ($0, false) })

            // Initialize client confirmations - all false initially (for multi-client bookings)
            let clientConfirmations = Dictionary(uniqueKeysWithValues: clientIds.map { ($0, false) })

            // Determine if this is a group booking
            let isGroupBooking = coachIds.count > 1 || clientIds.count > 1

            // Primary coach and client for backward compatibility
            let primaryCoachId = coachIds[0]
            let primaryClientId = clientIds[0]
            let primaryCoachRef = self.db.collection("coaches").document(primaryCoachId)
            let primaryClientRef = self.db.collection("clients").document(primaryClientId)

            var data: [String: Any] = [
                "CoachID": primaryCoachRef,
                "ClientID": primaryClientRef,
                "CoachIDs": coachIds,
                "ClientIDs": clientIds,
                "CoachNames": coachNamesArray,
                "ClientNames": clientNamesArray,
                "CoachName": coachNamesArray.first ?? "",
                "ClientName": clientNamesArray.first ?? "",
                "StartAt": Timestamp(date: startAt),
                "EndAt": Timestamp(date: endAt),
                "Location": location ?? "",
                "Notes": notes ?? "",
                "Status": status,
                "PaymentStatus": "unpaid",
                "isGroupBooking": isGroupBooking,
                "creatorID": creatorID,
                "creatorType": creatorType,
                "CoachAcceptances": coachAcceptances,
                "ClientConfirmations": clientConfirmations,
                "createdAt": FieldValue.serverTimestamp()
            ]

            print("[FirestoreManager] saveGroupBookingAndMirror begin: bookingId=\(bookingId) coaches=\(coachIds) clients=\(clientIds)")

            let batch = self.db.batch()

            // Set root booking document
            batch.setData(data, forDocument: bookingRef)

            // Mirror to ALL coaches' subcollections and update their calendar arrays
            for coachId in coachIds {
                let coachRef = self.db.collection("coaches").document(coachId)
                let coachBookingRef = coachRef.collection("bookings").document(bookingId)
                batch.setData(data, forDocument: coachBookingRef)

                // Build calendar summary for this coach
                let bookingSummary: [String: Any] = [
                    "id": bookingId,
                    "ClientIDs": clientIds,
                    "CoachIDs": coachIds,
                    "StartAt": Timestamp(date: startAt),
                    "EndAt": Timestamp(date: endAt),
                    "Location": location ?? "",
                    "Notes": notes ?? "",
                    "Status": status,
                    "isGroupBooking": isGroupBooking,
                    "createdAt": Timestamp(date: Date())
                ]
                batch.updateData(["calendar": FieldValue.arrayUnion([bookingSummary])], forDocument: coachRef)
            }

            // Mirror to ALL clients' subcollections
            for clientId in clientIds {
                let clientBookingRef = self.db.collection("clients").document(clientId).collection("bookings").document(bookingId)
                batch.setData(data, forDocument: clientBookingRef)
            }

            batch.commit { err in
                if let err = err {
                    print("[FirestoreManager] saveGroupBookingAndMirror commit error: \(err)")
                    completion(err)
                    return
                }
                print("[FirestoreManager] saveGroupBookingAndMirror commit succeeded for booking \(bookingId)")

                // Send notifications to all coaches (if status is requested)
                if status.lowercased() == "requested" {
                    let creatorName = creatorType == "client" ? (clientNames[creatorID] ?? "A client") : (coachNames[creatorID] ?? "A coach")
                    for coachId in coachIds {
                        // Don't notify the creator if they're a coach
                        if coachId == creatorID { continue }

                        let notifRef = self.db.collection("pendingNotifications").document(coachId).collection("notifications").document()
                        let notifPayload: [String: Any] = [
                            "title": "Group Booking Requested",
                            "body": "\(creatorName) requested a group session - Action Required",
                            "bookingId": bookingId,
                            "senderId": creatorID,
                            "isGroupBooking": true,
                            "createdAt": FieldValue.serverTimestamp(),
                            "delivered": false
                        ]
                        notifRef.setData(notifPayload) { nerr in
                            if let nerr = nerr {
                                print("[FirestoreManager] Failed to write group booking notification for coach \(coachId): \(nerr)")
                            }
                        }
                    }

                    // Notify other clients that they've been added to a group session
                    if clientIds.count > 1 {
                        for clientId in clientIds {
                            // Don't notify the creator
                            if clientId == creatorID { continue }

                            let notifRef = self.db.collection("pendingNotifications").document(clientId).collection("notifications").document()
                            let notifPayload: [String: Any] = [
                                "title": "Added to Group Session",
                                "body": "\(creatorName) added you to a group session",
                                "bookingId": bookingId,
                                "senderId": creatorID,
                                "isGroupBooking": true,
                                "createdAt": FieldValue.serverTimestamp(),
                                "delivered": false
                            ]
                            notifRef.setData(notifPayload) { nerr in
                                if let nerr = nerr {
                                    print("[FirestoreManager] Failed to write group booking notification for client \(clientId): \(nerr)")
                                }
                            }
                        }
                    }
                }

                completion(nil)
            }
        }
    }

    /// Convenience wrapper for group bookings from UI.
    func saveGroupBooking(
        coachIds: [String],
        clientIds: [String],
        startAt: Date,
        endAt: Date,
        location: String?,
        notes: String?,
        creatorID: String,
        creatorType: String,
        completion: @escaping (Error?) -> Void
    ) {
        saveGroupBookingAndMirror(
            coachIds: coachIds,
            clientIds: clientIds,
            startAt: startAt,
            endAt: endAt,
            status: "requested",
            location: location,
            notes: notes,
            creatorID: creatorID,
            creatorType: creatorType,
            completion: completion
        )
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

    @Published var toastMessage: String? = nil

    func showToast(_ message: String) {
        toastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            if self?.toastMessage == message {
                self?.toastMessage = nil
            }
        }
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
        fetchBookingsForClient(clientId: clientId) { [weak self] items in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.bookings = items.sorted { (a,b) in
                    (a.startAt ?? Date.distantPast) > (b.startAt ?? Date.distantPast)
                }
                self.bookingsDebug += "\nFetched \(items.count) bookings from clients/\(clientId)/bookings"

                guard let currentUserId = Auth.auth().currentUser?.uid,
                      currentUserId == clientId else { return }

                // Auto-remove calendar events for cancelled/rejected/declined bookings
                let cancelledStatuses = ["cancelled", "rejected", "declined", "declined_by_client"]
                let cancelledBookings = items.filter {
                    cancelledStatuses.contains(($0.status ?? "").lowercased())
                }
                for booking in cancelledBookings {
                    self.removeBookingFromAppleCalendar(bookingId: booking.id) { _ in }
                }

                // Auto-add confirmed upcoming bookings to calendar if enabled
                guard self.autoAddToCalendar else { return }

                let confirmedUpcoming = items.filter {
                    ($0.status ?? "").lowercased() == "confirmed" &&
                    ($0.endAt ?? Date.distantPast) > Date() &&
                    // Verify current user is actually a client in this booking
                    ($0.clientID == currentUserId || ($0.clientIDs ?? []).contains(currentUserId))
                }
                for booking in confirmedUpcoming {
                    // Skip if already being processed (race condition prevention)
                    guard !self.calendarAddInProgress.contains(booking.id) else { continue }
                    self.calendarAddInProgress.insert(booking.id)

                    let coachNames = booking.allCoachNames.joined(separator: ", ")
                    let title = booking.isGroupBooking == true
                        ? "Group Session with \(coachNames.isEmpty ? "Coaches" : coachNames)"
                        : "Session with \(booking.coachName ?? "Coach")"
                    let start = booking.startAt ?? Date()
                    let end = booking.endAt ?? Calendar.current.date(byAdding: .hour, value: 1, to: start) ?? Date()
                    self.addBookingToAppleCalendar(
                        title: title,
                        start: start,
                        end: end,
                        location: booking.location,
                        notes: booking.notes,
                        bookingId: booking.id
                    ) { res in
                        switch res {
                        case .success(let eventId):
                            print("Auto-added client booking to calendar: \(eventId)")
                        case .failure(let err):
                            print("Failed to auto-add client booking to calendar: \(err)")
                        }
                    }
                }
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
                        let coachNote = data["CoachNote"] as? String
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

                        // Group booking fields
                        let clientIDs = data["ClientIDs"] as? [String]
                        let clientNames = data["ClientNames"] as? [String]
                        let coachIDs = data["CoachIDs"] as? [String]
                        let coachNames = data["CoachNames"] as? [String]
                        let isGroupBooking = data["isGroupBooking"] as? Bool
                        let creatorID = data["creatorID"] as? String
                        let creatorType = data["creatorType"] as? String
                        let coachAcceptances = data["CoachAcceptances"] as? [String: Bool]
                        let clientConfirmations = data["ClientConfirmations"] as? [String: Bool]
                        let coachRates = data["CoachRates"] as? [String: Double]
                        let rejectionReason = data["rejectionReason"] as? String
                        let rejectedBy = data["rejectedBy"] as? String
                let clientDeclineReason = data["clientDeclineReason"] as? String
                        let requiresPaymentUpfront = data["requiresPaymentUpfront"] as? Bool
                        let item = BookingItem(id: id, clientID: clientID, clientName: clientName, coachID: coachId, coachName: coachName.isEmpty ? coachId : coachName, startAt: startAt, endAt: endAt, location: location, notes: notes, status: status, paymentStatus: nil, RateUSD: nil, clientIDs: clientIDs, clientNames: clientNames, coachIDs: coachIDs, coachNames: coachNames, isGroupBooking: isGroupBooking, creatorID: creatorID, creatorType: creatorType, coachAcceptances: coachAcceptances, clientConfirmations: clientConfirmations, coachRates: coachRates, coachNote: coachNote, rejectionReason: rejectionReason, rejectedBy: rejectedBy, clientDeclineReason: clientDeclineReason, requiresPaymentUpfront: requiresPaymentUpfront, sessionRecap: data["sessionRecap"] as? String)
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
        fetchBookingsForCoach(coachId: coachId) { [weak self] items in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.coachBookings = items.sorted { (a,b) in
                    (a.startAt ?? Date.distantPast) > (b.startAt ?? Date.distantPast)
                }
                self.coachBookingsDebug += "\nFetched \(items.count) bookings from coaches/\(coachId)/bookings"

                guard let currentUserId = Auth.auth().currentUser?.uid,
                      currentUserId == coachId else { return }

                // Auto-remove calendar events for cancelled/rejected/declined bookings
                let cancelledStatuses = ["cancelled", "rejected", "declined", "declined_by_client"]
                let cancelledBookings = items.filter {
                    cancelledStatuses.contains(($0.status ?? "").lowercased())
                }
                for booking in cancelledBookings {
                    self.removeBookingFromAppleCalendar(bookingId: booking.id) { _ in }
                }

                // Auto-add confirmed upcoming bookings to calendar if enabled
                guard self.autoAddToCalendar else { return }

                let confirmedUpcoming = items.filter {
                    ($0.status ?? "").lowercased() == "confirmed" &&
                    ($0.endAt ?? Date.distantPast) > Date() &&
                    // Verify current user is actually a coach in this booking
                    ($0.coachID == currentUserId || ($0.coachIDs ?? []).contains(currentUserId))
                }
                for booking in confirmedUpcoming {
                    // Skip if already being processed (race condition prevention)
                    guard !self.calendarAddInProgress.contains(booking.id) else { continue }
                    self.calendarAddInProgress.insert(booking.id)

                    let clientNames = booking.allClientNames.joined(separator: ", ")
                    let title = booking.isGroupBooking == true
                        ? "Group Session with \(clientNames.isEmpty ? "Clients" : clientNames)"
                        : "Session with \(booking.clientName ?? "Client")"
                    let start = booking.startAt ?? Date()
                    let end = booking.endAt ?? Calendar.current.date(byAdding: .hour, value: 1, to: start) ?? Date()
                    self.addBookingToAppleCalendar(
                        title: title,
                        start: start,
                        end: end,
                        location: booking.location,
                        notes: booking.notes,
                        bookingId: booking.id
                    ) { res in
                        switch res {
                        case .success(let eventId):
                            print("Auto-added coach booking to calendar: \(eventId)")
                        case .failure(let err):
                            print("Failed to auto-add coach booking to calendar: \(err)")
                        }
                    }
                }
            }
        }
    }

    /// Convenience: fetch bookings for the currently authenticated user treating them as a coach.
    /// Batch-write the coach's private session notes to all 3 booking mirrors.
    /// Read a coach's cancellation-policy window (hours) for the client cancel flow.
    func fetchCoachCancellationWindow(coachId: String, completion: @escaping (Int) -> Void) {
        db.collection("coaches").document(coachId).getDocument { snap, _ in
            completion(snap?.data()?["cancellationWindowHours"] as? Int ?? 0)
        }
    }

    /// Flag a booking's deposit as forfeited after a late client cancellation.
    func markDepositForfeited(bookingId: String, coachId: String, clientId: String) {
        let payload: [String: Any] = ["depositForfeited": true]
        let batch = db.batch()
        batch.updateData(payload, forDocument: db.collection("bookings").document(bookingId))
        if !coachId.isEmpty {
            batch.updateData(payload, forDocument: db.collection("coaches").document(coachId).collection("bookings").document(bookingId))
        }
        if !clientId.isEmpty {
            batch.updateData(payload, forDocument: db.collection("clients").document(clientId).collection("bookings").document(bookingId))
        }
        batch.commit { _ in }
    }

    /// Coach-written, client-visible recap of the session (mirrors saveSessionNotes).
    func saveSessionRecap(bookingId: String, coachId: String, clientId: String, recap: String, completion: @escaping (Error?) -> Void) {
        let batch = db.batch()
        let payload: [String: Any] = ["sessionRecap": recap]
        batch.updateData(payload, forDocument: db.collection("bookings").document(bookingId))
        batch.updateData(payload, forDocument: db.collection("coaches").document(coachId).collection("bookings").document(bookingId))
        if !clientId.isEmpty {
            batch.updateData(payload, forDocument: db.collection("clients").document(clientId).collection("bookings").document(bookingId))
        }
        batch.commit(completion: completion)
    }

    func saveSessionNotes(bookingId: String, coachId: String, clientId: String, notes: String, completion: @escaping (Error?) -> Void) {
        let batch = db.batch()
        let payload: [String: Any] = ["coachNote": notes]
        batch.updateData(payload, forDocument: db.collection("bookings").document(bookingId))
        batch.updateData(payload, forDocument: db.collection("coaches").document(coachId).collection("bookings").document(bookingId))
        if !clientId.isEmpty {
            batch.updateData(payload, forDocument: db.collection("clients").document(clientId).collection("bookings").document(bookingId))
        }
        batch.commit(completion: completion)
    }

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
                DispatchQueue.main.async { self.currentUserType = nil; self.currentAdditionalTypes = []; self.currentUserPhoneVerified = false; self.userTypeLoaded = true; completion?() }
                return
            }
            guard let data = snap?.data() else {
                DispatchQueue.main.async { self.currentUserType = nil; self.currentAdditionalTypes = []; self.currentUserPhoneVerified = false; self.userTypeLoaded = true; completion?() }
                return
            }
            let t = (data["type"] as? String)?.uppercased()
            let additional = data["additionalTypes"] as? [String] ?? []
            let phoneVerified = data["phoneVerified"] as? Bool ?? false
            DispatchQueue.main.async { self.currentUserType = t; self.currentAdditionalTypes = additional; self.currentUserPhoneVerified = phoneVerified; self.userTypeLoaded = true; completion?() }
        }
    }

    /// Update the additionalTypes array for the current user using arrayUnion/arrayRemove.
    func updateAdditionalTypes(add: [String] = [], remove: [String] = [], completion: @escaping (Error?) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(NSError(domain: "FirestoreManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]))
            return
        }
        let docRef = db.collection("userType").document(uid)
        var updates: [String: Any] = [:]
        if !add.isEmpty { updates["additionalTypes"] = FieldValue.arrayUnion(add) }
        if !remove.isEmpty { updates["additionalTypes"] = FieldValue.arrayRemove(remove) }
        guard !updates.isEmpty else { completion(nil); return }

        // If both add and remove are needed, do remove first then add
        if !add.isEmpty && !remove.isEmpty {
            docRef.updateData(["additionalTypes": FieldValue.arrayRemove(remove)]) { [weak self] err in
                if let err = err { completion(err); return }
                docRef.updateData(["additionalTypes": FieldValue.arrayUnion(add)]) { err in
                    if let err = err { completion(err); return }
                    self?.fetchUserType(for: uid) { completion(nil) }
                }
            }
        } else {
            docRef.setData(updates, merge: true) { [weak self] err in
                if let err = err { completion(err); return }
                self?.fetchUserType(for: uid) { completion(nil) }
            }
        }
    }

    /// Fetch additional types for any user (not just current user).
    func fetchAdditionalTypesForUser(userId: String, completion: @escaping ([String]) -> Void) {
        let docRef = db.collection("userType").document(userId)
        docRef.getDocument { snap, err in
            if let err = err {
                print("fetchAdditionalTypesForUser error: \(err)")
                completion([])
                return
            }
            let additionalTypes = snap?.data()?["additionalTypes"] as? [String] ?? []
            completion(additionalTypes)
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
                    // If cancelled, remove from Apple Calendar to free up coach availability
                    if status.lowercased() == "cancelled" {
                        self.removeBookingFromAppleCalendar(bookingId: bookingId) { calErr in
                            if let calErr = calErr {
                                print("updateBookingStatus: failed to remove calendar event: \(calErr)")
                            }
                            // Complete regardless of calendar removal result
                            completion(nil)
                        }
                    } else {
                        completion(nil)
                    }
                }
            }
        }
    }

    /// Accept a group booking as a specific coach.
    /// Updates this coach's acceptance in CoachAcceptances map and determines overall status.
    func acceptGroupBookingAsCoach(
        bookingId: String,
        coachId: String,
        rateUSD: Double?,
        coachNote: String?,
        completion: @escaping (Error?) -> Void
    ) {
        let bookingRef = self.db.collection("bookings").document(bookingId)

        bookingRef.getDocument { [weak self] snap, err in
            guard let self = self else { return }

            if let err = err {
                print("acceptGroupBookingAsCoach: failed to read booking: \(err)")
                completion(err)
                return
            }

            guard let data = snap?.data() else {
                completion(NSError(domain: "FirestoreManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Booking not found"]))
                return
            }

            // Get existing acceptances or create new map
            var acceptances = data["CoachAcceptances"] as? [String: Bool] ?? [:]
            var coachRates = data["CoachRates"] as? [String: Double] ?? [:]
            let coachIds = data["CoachIDs"] as? [String] ?? []
            let clientIds = data["ClientIDs"] as? [String] ?? []
            let creatorID = data["creatorID"] as? String

            // Mark this coach as accepted
            acceptances[coachId] = true

            // Store this coach's rate in the rates dictionary
            if let rate = rateUSD {
                coachRates[coachId] = rate
            }

            // Check if all coaches have now accepted
            let allAccepted = coachIds.allSatisfy { acceptances[$0] == true }

            // Determine new status
            let newStatus = allAccepted ? "Pending Acceptance" : "partially_accepted"

            var updateData: [String: Any] = [
                "CoachAcceptances": acceptances,
                "CoachRates": coachRates,
                "Status": newStatus
            ]
            // Also store in RateUSD for backwards compatibility (will be last coach's rate)
            if let rate = rateUSD {
                updateData["RateUSD"] = rate
            }
            if let note = coachNote, !note.isEmpty {
                updateData["CoachNote"] = note
            }

            let batch = self.db.batch()

            // Update root booking
            batch.updateData(updateData, forDocument: bookingRef)

            // Update ALL coach mirrors
            for cId in coachIds {
                let coachBookingRef = self.db.collection("coaches").document(cId).collection("bookings").document(bookingId)
                batch.updateData(updateData, forDocument: coachBookingRef)
            }

            // Update ALL client mirrors
            for clId in clientIds {
                let clientBookingRef = self.db.collection("clients").document(clId).collection("bookings").document(bookingId)
                batch.updateData(updateData, forDocument: clientBookingRef)
            }

            batch.commit { err in
                if let err = err {
                    print("acceptGroupBookingAsCoach: batch commit failed: \(err)")
                    completion(err)
                    return
                }

                print("acceptGroupBookingAsCoach: coach \(coachId) accepted booking \(bookingId), status=\(newStatus)")

                // Resolve accepting coach's name for notifications
                let coachName = self.currentCoach?.name ?? self.coaches.first(where: { $0.id == coachId })?.name ?? "A coach"

                // Send notifications
                // Notify ALL clients when all coaches have accepted
                if allAccepted {
                    for clientId in clientIds {
                        let notifRef = self.db.collection("pendingNotifications").document(clientId).collection("notifications").document()
                        let notifPayload: [String: Any] = [
                            "title": "Group Booking Ready",
                            "body": "All coaches have accepted your group session - Please confirm",
                            "bookingId": bookingId,
                            "senderId": coachId,
                            "isGroupBooking": true,
                            "createdAt": FieldValue.serverTimestamp(),
                            "delivered": false
                        ]
                        notifRef.setData(notifPayload) { _ in }
                    }
                } else {
                    // Notify clients that this specific coach accepted (not all yet)
                    for clientId in clientIds {
                        let notifRef = self.db.collection("pendingNotifications").document(clientId).collection("notifications").document()
                        let notifPayload: [String: Any] = [
                            "title": "Coach Accepted",
                            "body": "\(coachName) has accepted your group session",
                            "bookingId": bookingId,
                            "senderId": coachId,
                            "isGroupBooking": true,
                            "createdAt": FieldValue.serverTimestamp(),
                            "delivered": false
                        ]
                        notifRef.setData(notifPayload) { _ in }
                    }
                }

                // Notify other coaches that this coach accepted
                for otherCoachId in coachIds where otherCoachId != coachId {
                    let notifRef = self.db.collection("pendingNotifications").document(otherCoachId).collection("notifications").document()
                    let notifPayload: [String: Any] = [
                        "title": "Coach Accepted",
                        "body": "\(coachName) has accepted the group session",
                        "bookingId": bookingId,
                        "senderId": coachId,
                        "isGroupBooking": true,
                        "createdAt": FieldValue.serverTimestamp(),
                        "delivered": false
                    ]
                    notifRef.setData(notifPayload) { _ in }
                }

                completion(nil)
            }
        }
    }

    /// Confirm a group booking as a client (after all coaches have accepted).
    /// For multi-client bookings, tracks per-client confirmations.
    func confirmGroupBookingAsClient(bookingId: String, clientId: String, completion: @escaping (Error?) -> Void) {
        let bookingRef = self.db.collection("bookings").document(bookingId)

        bookingRef.getDocument { [weak self] snap, err in
            guard let self = self else { return }

            if let err = err {
                print("confirmGroupBookingAsClient: failed to read booking: \(err)")
                completion(err)
                return
            }

            guard let data = snap?.data() else {
                completion(NSError(domain: "FirestoreManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Booking not found"]))
                return
            }

            let coachIds = data["CoachIDs"] as? [String] ?? []
            let clientIds = data["ClientIDs"] as? [String] ?? []

            // Get existing confirmations or create new map
            var confirmations = data["ClientConfirmations"] as? [String: Bool] ?? [:]

            // Mark this client as confirmed
            confirmations[clientId] = true

            // Check if all clients have now confirmed
            let allConfirmed = clientIds.allSatisfy { confirmations[$0] == true }

            // Determine new status
            let newStatus = allConfirmed ? "confirmed" : "partially_confirmed"

            var updateData: [String: Any] = [
                "ClientConfirmations": confirmations,
                "Status": newStatus
            ]

            // Only set confirmedAt when fully confirmed
            if allConfirmed {
                updateData["confirmedAt"] = FieldValue.serverTimestamp()
            }

            let batch = self.db.batch()

            // Update root booking
            batch.updateData(updateData, forDocument: bookingRef)

            // Update ALL coach mirrors
            for cId in coachIds {
                let coachBookingRef = self.db.collection("coaches").document(cId).collection("bookings").document(bookingId)
                batch.updateData(updateData, forDocument: coachBookingRef)
            }

            // Update ALL client mirrors
            for clId in clientIds {
                let clientBookingRef = self.db.collection("clients").document(clId).collection("bookings").document(bookingId)
                batch.updateData(updateData, forDocument: clientBookingRef)
            }

            batch.commit { err in
                if let err = err {
                    print("confirmGroupBookingAsClient: batch commit failed: \(err)")
                    completion(err)
                    return
                }

                print("confirmGroupBookingAsClient: client \(clientId) confirmed booking \(bookingId), status=\(newStatus)")

                // Only notify coaches when ALL clients have confirmed (fully confirmed)
                if allConfirmed {
                    for coachId in coachIds {
                        let notifRef = self.db.collection("pendingNotifications").document(coachId).collection("notifications").document()
                        let notifPayload: [String: Any] = [
                            "title": "Group Booking Confirmed",
                            "body": "All clients have confirmed the group session",
                            "bookingId": bookingId,
                            "senderId": clientId,
                            "type": "booking_confirmed",
                            "isGroupBooking": true,
                            "createdAt": FieldValue.serverTimestamp(),
                            "delivered": false
                        ]
                        notifRef.setData(notifPayload) { _ in }
                    }

                    // Notify other clients that the booking is fully confirmed
                    for otherClientId in clientIds where otherClientId != clientId {
                        let notifRef = self.db.collection("pendingNotifications").document(otherClientId).collection("notifications").document()
                        let notifPayload: [String: Any] = [
                            "title": "Group Session Confirmed",
                            "body": "All participants have confirmed - your group session is now booked!",
                            "bookingId": bookingId,
                            "senderId": clientId,
                            "isGroupBooking": true,
                            "createdAt": FieldValue.serverTimestamp(),
                            "delivered": false
                        ]
                        notifRef.setData(notifPayload) { _ in }
                    }
                } else {
                    // Notify other clients that this client has confirmed (waiting for them)
                    let clientName = data["ClientNames"] as? [String] ?? []
                    let confirmingClientName = clientIds.firstIndex(of: clientId).flatMap { idx in
                        idx < clientName.count ? clientName[idx] : nil
                    } ?? "A participant"

                    for otherClientId in clientIds where otherClientId != clientId && confirmations[otherClientId] != true {
                        let notifRef = self.db.collection("pendingNotifications").document(otherClientId).collection("notifications").document()
                        let notifPayload: [String: Any] = [
                            "title": "Action Required: Confirm Group Session",
                            "body": "\(confirmingClientName) has confirmed. Please review and confirm the group session.",
                            "bookingId": bookingId,
                            "senderId": clientId,
                            "isGroupBooking": true,
                            "createdAt": FieldValue.serverTimestamp(),
                            "delivered": false
                        ]
                        notifRef.setData(notifPayload) { _ in }
                    }
                }

                completion(nil)
            }
        }
    }

    /// Update booking status for group bookings - updates all participant mirrors.
    func updateGroupBookingStatus(bookingId: String, status: String, completion: @escaping (Error?) -> Void) {
        let bookingRef = self.db.collection("bookings").document(bookingId)

        bookingRef.getDocument { [weak self] snap, err in
            guard let self = self else { return }

            if let err = err {
                completion(err)
                return
            }

            guard let data = snap?.data() else {
                completion(NSError(domain: "FirestoreManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Booking not found"]))
                return
            }

            let coachIds = data["CoachIDs"] as? [String] ?? []
            let clientIds = data["ClientIDs"] as? [String] ?? []

            // Fall back to single coach/client if arrays are empty
            var allCoachIds = coachIds
            var allClientIds = clientIds
            if allCoachIds.isEmpty {
                if let ref = data["CoachID"] as? DocumentReference {
                    allCoachIds = [ref.documentID]
                } else if let s = data["CoachID"] as? String {
                    allCoachIds = [s.split(separator: "/").last.map(String.init) ?? s]
                }
            }
            if allClientIds.isEmpty {
                if let ref = data["ClientID"] as? DocumentReference {
                    allClientIds = [ref.documentID]
                } else if let s = data["ClientID"] as? String {
                    allClientIds = [s.split(separator: "/").last.map(String.init) ?? s]
                }
            }

            let batch = self.db.batch()

            // Update root booking
            batch.updateData(["Status": status], forDocument: bookingRef)

            // Update ALL coach mirrors
            for cId in allCoachIds {
                let coachBookingRef = self.db.collection("coaches").document(cId).collection("bookings").document(bookingId)
                batch.updateData(["Status": status], forDocument: coachBookingRef)
            }

            // Update ALL client mirrors
            for clId in allClientIds {
                let clientBookingRef = self.db.collection("clients").document(clId).collection("bookings").document(bookingId)
                batch.updateData(["Status": status], forDocument: clientBookingRef)
            }

            batch.commit { [weak self] err in
                if let err = err {
                    print("updateGroupBookingStatus: batch commit failed: \(err)")
                    completion(err)
                } else {
                    print("updateGroupBookingStatus: booking \(bookingId) status updated to \(status)")
                    // If cancelled, remove from Apple Calendar to free up coach availability
                    if status.lowercased() == "cancelled" {
                        self?.removeBookingFromAppleCalendar(bookingId: bookingId) { calErr in
                            if let calErr = calErr {
                                print("updateGroupBookingStatus: failed to remove calendar event: \(calErr)")
                            }
                            // Complete regardless of calendar removal result
                            completion(nil)
                        }
                    } else {
                        completion(nil)
                    }
                }
            }
        }
    }

    /// Reschedule a booking by updating StartAt, EndAt, and Status across root and mirrored subcollections.
    func rescheduleBooking(bookingId: String, newStart: Date, newEnd: Date, newStatus: String, completion: @escaping (Error?) -> Void) {
        let bookingRef = self.db.collection("bookings").document(bookingId)

        bookingRef.getDocument { snap, err in
            if let err = err {
                print("rescheduleBooking: failed to read booking \(bookingId): \(err)")
                completion(err)
                return
            }

            guard let data = snap?.data() else {
                print("rescheduleBooking: booking \(bookingId) not found")
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
            let updateFields: [String: Any] = [
                "StartAt": Timestamp(date: newStart),
                "EndAt": Timestamp(date: newEnd),
                "Status": newStatus
            ]

            batch.updateData(updateFields, forDocument: bookingRef)

            if let cId = coachId {
                let coachBookingRef = self.db.collection("coaches").document(cId).collection("bookings").document(bookingId)
                batch.updateData(updateFields, forDocument: coachBookingRef)
            }

            if let clId = clientId {
                let clientBookingRef = self.db.collection("clients").document(clId).collection("bookings").document(bookingId)
                batch.updateData(updateFields, forDocument: clientBookingRef)
            }

            batch.commit { err in
                if let err = err {
                    print("rescheduleBooking: batch commit failed: \(err)")
                    completion(err)
                } else {
                    print("rescheduleBooking: booking \(bookingId) rescheduled to \(newStart)-\(newEnd), status=\(newStatus)")
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

    /// Acknowledge payment for a group booking - updates root and all participant mirrors
    func acknowledgeGroupBookingPayment(bookingId: String, paymentStatus: String, completion: @escaping (Error?) -> Void) {
        let bookingRef = self.db.collection("bookings").document(bookingId)

        bookingRef.getDocument { snap, err in
            if let err = err {
                print("acknowledgeGroupBookingPayment: failed to read booking \(bookingId): \(err)")
                completion(err)
                return
            }

            guard let data = snap?.data() else {
                print("acknowledgeGroupBookingPayment: booking \(bookingId) not found")
                completion(NSError(domain: "FirestoreManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Booking not found"]))
                return
            }

            // Get all coach and client IDs for group booking
            let coachIDs = data["CoachIDs"] as? [String] ?? []
            let clientIDs = data["ClientIDs"] as? [String] ?? []

            // Fallback to single coach/client if arrays are empty
            var allCoachIds = coachIDs
            var allClientIds = clientIDs

            if allCoachIds.isEmpty {
                if let ref = data["CoachID"] as? DocumentReference {
                    allCoachIds = [ref.documentID]
                } else if let s = data["CoachID"] as? String {
                    allCoachIds = [s.split(separator: "/").last.map(String.init) ?? s]
                }
            }

            if allClientIds.isEmpty {
                if let ref = data["ClientID"] as? DocumentReference {
                    allClientIds = [ref.documentID]
                } else if let s = data["ClientID"] as? String {
                    allClientIds = [s.split(separator: "/").last.map(String.init) ?? s]
                }
            }

            let batch = self.db.batch()

            // Update root booking
            batch.updateData(["PaymentStatus": paymentStatus], forDocument: bookingRef)

            // Update all coach mirrors
            for coachId in allCoachIds {
                let coachBookingRef = self.db.collection("coaches").document(coachId).collection("bookings").document(bookingId)
                batch.updateData(["PaymentStatus": paymentStatus], forDocument: coachBookingRef)
            }

            // Update all client mirrors
            for clientId in allClientIds {
                let clientBookingRef = self.db.collection("clients").document(clientId).collection("bookings").document(bookingId)
                batch.updateData(["PaymentStatus": paymentStatus], forDocument: clientBookingRef)
            }

            batch.commit { err in
                if let err = err {
                    print("acknowledgeGroupBookingPayment: batch commit failed: \(err)")
                    completion(err)
                } else {
                    print("acknowledgeGroupBookingPayment: booking \(bookingId) payment status updated to \(paymentStatus) for \(allCoachIds.count) coaches and \(allClientIds.count) clients")
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
                let coachNote = data["CoachNote"] as? String
                let paymentStatus = data["PaymentStatus"] as? String
                let rate = (data["RateUSD"] as? Double) ?? ((data["RateUSD"] as? Int).map { Double($0) })
                // Extract client and coach names from booking doc
                let clientName = (data["ClientName"] as? String)
                    ?? (data["clientName"] as? String)
                    ?? (data["client_name"] as? String)
                let coachName = (data["CoachName"] as? String)
                    ?? (data["coachName"] as? String)
                    ?? (data["coach_name"] as? String)
                // Group booking fields
                let clientIDs = data["ClientIDs"] as? [String]
                let clientNames = data["ClientNames"] as? [String]
                let coachIDs = data["CoachIDs"] as? [String]
                let coachNames = data["CoachNames"] as? [String]
                let isGroupBooking = data["isGroupBooking"] as? Bool
                let creatorID = data["creatorID"] as? String
                let creatorType = data["creatorType"] as? String
                let coachAcceptances = data["CoachAcceptances"] as? [String: Bool]
                let clientConfirmations = data["ClientConfirmations"] as? [String: Bool]
                let coachRates = data["CoachRates"] as? [String: Double]
                let rejectionReason = data["rejectionReason"] as? String
                let rejectedBy = data["rejectedBy"] as? String
                let clientDeclineReason = data["clientDeclineReason"] as? String
                let requiresPaymentUpfront = data["requiresPaymentUpfront"] as? Bool
                let item = BookingItem(id: id, clientID: clientID, clientName: clientName, coachID: coachId, coachName: coachName, startAt: startAt, endAt: endAt, location: location, notes: notes, status: status, paymentStatus: paymentStatus, RateUSD: rate, clientIDs: clientIDs, clientNames: clientNames, coachIDs: coachIDs, coachNames: coachNames, isGroupBooking: isGroupBooking, creatorID: creatorID, creatorType: creatorType, coachAcceptances: coachAcceptances, clientConfirmations: clientConfirmations, coachRates: coachRates, coachNote: coachNote, rejectionReason: rejectionReason, rejectedBy: rejectedBy, clientDeclineReason: clientDeclineReason, requiresPaymentUpfront: requiresPaymentUpfront, sessionRecap: data["sessionRecap"] as? String)
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

                // Denormalize each participant's display name and photo onto the
                // chat doc so the other side can always render them (the coach's
                // list previously showed a raw UID / blank avatar when the live
                // profile lookup failed).
                var participantNamesMap: [String: String] = [:]
                var participantPhotosMap: [String: String] = [:]
                let infoGroup = DispatchGroup()
                for id in uids {
                    infoGroup.enter()
                    self.fetchUserDisplayInfo(uid: id) { name, photo in
                        if let n = name, !n.isEmpty { participantNamesMap[id] = n }
                        if let p = photo, !p.isEmpty { participantPhotosMap[id] = p }
                        infoGroup.leave()
                    }
                }

                infoGroup.notify(queue: .main) {

                // Only write participantRefs now; do not write the legacy participants string array.
                let data: [String: Any] = [
                    "participantRefs": participantRefs,
                    "participantNames": participantNamesMap,
                    "participantPhotoURLs": participantPhotosMap,
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
                } // end infoGroup.notify
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
    /// Remove a booking event from Apple Calendar when cancelled.
    /// Reads the calendarEventId from the booking document and deletes the corresponding calendar event.
    func removeBookingFromAppleCalendar(bookingId: String, completion: @escaping (Error?) -> Void) {
        let bookingRef = self.db.collection("bookings").document(bookingId)

        // First read the booking to get the calendarEventId
        bookingRef.getDocument { snap, err in
            if let err = err {
                print("removeBookingFromAppleCalendar: failed to read booking: \(err)")
                completion(err)
                return
            }

            guard let data = snap?.data() else {
                print("removeBookingFromAppleCalendar: no booking data for \(bookingId)")
                completion(nil)
                return
            }

            // Look up per-user event ID first, fall back to legacy global field
            let currentUid = Auth.auth().currentUser?.uid ?? ""
            let eventId: String? = {
                if let perUser = data["calendarEventIds"] as? [String: String],
                   let uid = perUser[currentUid], !uid.isEmpty {
                    return uid
                }
                if let global = data["calendarEventId"] as? String, !global.isEmpty {
                    return global
                }
                return nil
            }()

            guard let eventId = eventId, !eventId.isEmpty else {
                print("removeBookingFromAppleCalendar: no calendarEventId found for booking \(bookingId)")
                completion(nil)
                return
            }

            let handleAccessResponse: (Bool, Error?) -> Void = { granted, error in
                let eventStore = EKEventStore()

                if let err = error {
                    print("removeBookingFromAppleCalendar: requestAccess error: \(err)")
                    completion(err)
                    return
                }

                if !granted {
                    let err = NSError(domain: "FirestoreManager", code: 403, userInfo: [NSLocalizedDescriptionKey: "Calendar access not granted"])
                    print("removeBookingFromAppleCalendar: calendar access denied by user")
                    completion(err)
                    return
                }

                // Find and delete the event
                if let event = eventStore.event(withIdentifier: eventId) {
                    do {
                        try eventStore.remove(event, span: .thisEvent)
                        print("removeBookingFromAppleCalendar: successfully removed calendar event \(eventId)")

                        // Clear the calendarEventId from the booking document
                        bookingRef.updateData([
                            "calendarEventId": FieldValue.delete(),
                            "calendarRemovedAt": FieldValue.serverTimestamp(),
                            "calendarRemovedBy": Auth.auth().currentUser?.uid ?? NSNull()
                        ]) { err in
                            if let err = err {
                                print("removeBookingFromAppleCalendar: failed to clear calendarEventId: \(err)")
                            }
                            DispatchQueue.main.async { completion(nil) }
                        }
                    } catch {
                        print("removeBookingFromAppleCalendar: failed to remove event: \(error)")
                        DispatchQueue.main.async { completion(error) }
                    }
                } else {
                    // Event not found on this device (may have been added on another device)
                    print("removeBookingFromAppleCalendar: event \(eventId) not found on this device")
                    DispatchQueue.main.async { completion(nil) }
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
    }

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

            // Avoid duplicates: check per-user calendarEventIds map on the booking doc
            let currentUid = Auth.auth().currentUser?.uid ?? ""
            let bookingRef = self.db.collection("bookings").document(bookingId)
            bookingRef.getDocument { snap, err in
                if let err = err {
                    print("addBookingToAppleCalendar: failed to read booking doc: \(err)")
                }
                if let data = snap?.data() {
                    // Check per-user map first
                    if let perUser = data["calendarEventIds"] as? [String: String],
                       let existing = perUser[currentUid], !existing.isEmpty {
                        DispatchQueue.main.async { completion(.success(existing)) }
                        return
                    }
                    // Legacy: check global calendarEventId only if it was added by this user
                    if let existingEventId = data["calendarEventId"] as? String, !existingEventId.isEmpty,
                       let addedBy = data["calendarAddedBy"] as? String, addedBy == currentUid {
                        DispatchQueue.main.async { completion(.success(existingEventId)) }
                        return
                    }
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
                    // Persist per-user calendar event id to avoid duplicates across users
                    let updateData: [String: Any] = [
                        "calendarEventIds.\(currentUid)": eventId,
                        "calendarAddedAt": FieldValue.serverTimestamp(),
                        "calendarAddedBy": currentUid
                    ]
                    bookingRef.setData(updateData, merge: true) { err in
                        if let err = err {
                            print("addBookingToAppleCalendar: failed to persist calendarEventId: \(err)")
                        }
                        DispatchQueue.main.async { completion(.success(eventId)) }
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
    func updateCurrentCoachAvailability(_ availability: [String], completion: ((Error?) -> Void)? = nil) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion?(NSError(domain: "FirestoreManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]))
            return
        }
        let ref = db.collection("coaches").document(uid)
        ref.setData(["availability": availability, "updatedAt": FieldValue.serverTimestamp()], merge: true) { err in
            if let err = err {
                print("updateCurrentCoachAvailability error: \(err)")
                completion?(err)
                return
            }
            if let cur = self.currentCoach {
                let updated = Coach(id: cur.id,
                                    name: cur.name,
                                    specialties: cur.specialties,
                                    experienceYears: cur.experienceYears,
                                    availability: availability,
                                    bio: cur.bio,
                                    hourlyRate: cur.hourlyRate,
                                    photoURLString: cur.photoURLString,
                                    meetingPreference: cur.meetingPreference,
                                    zipCode: cur.zipCode,
                                    city: cur.city,
                                    payments: cur.payments,
                                    rateRange: cur.rateRange,
                                    tournamentSoftwareLink: cur.tournamentSoftwareLink,
                                    subscriptionTier: cur.subscriptionTier,
                                    linkedPlaceIds: cur.linkedPlaceIds)
                self.currentCoach = updated
            }
            completion?(nil)
        }
    }

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
                                    payments: payments,
                                    rateRange: cur.rateRange,
                                    tournamentSoftwareLink: cur.tournamentSoftwareLink,
                                    subscriptionTier: cur.subscriptionTier,
                                    linkedPlaceIds: cur.linkedPlaceIds)
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
            let first = (data["FirstName"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let last = (data["LastName"] as? String ?? "").trimmingCharacters(in: .whitespaces)
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
        let coachId: String?  // Added to track which coach the away time belongs to
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
                return AwayTimeItem(id: d.documentID, startAt: s, endAt: e, notes: notes, coachId: coachId)
            }
            completion(items)
        }
    }

    // MARK: - Stringer Reviews

    func fetchStringerReviews(stringerId: String) {
        self.db.collection("stringerReviews")
            .whereField("stringerId", isEqualTo: stringerId)
            .getDocuments { snap, err in
                if let err = err {
                    print("fetchStringerReviews error: \(err)")
                    return
                }
                let docs = snap?.documents ?? []
                let results: [StringerReview] = docs.compactMap { d in
                    let data = d.data()
                    let stringerId = data["stringerId"] as? String ?? ""
                    let reviewerName = data["reviewerName"] as? String ?? "Anonymous"
                    let rating = data["rating"] as? Int ?? 5
                    let comment = data["comment"] as? String ?? ""
                    let createdBy = data["createdBy"] as? String ?? ""
                    let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                    return StringerReview(id: d.documentID, stringerId: stringerId, reviewerName: reviewerName, rating: rating, comment: comment, createdBy: createdBy, createdAt: createdAt)
                }.sorted { $0.createdAt > $1.createdAt }
                DispatchQueue.main.async {
                    self.stringerReviews = results
                }
            }
    }

    func addStringerReview(stringerId: String, rating: Int, comment: String, completion: @escaping (Error?) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(NSError(domain: "FirestoreManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]))
            return
        }
        let reviewerName: String = {
            if let name = self.currentClient?.name, !name.isEmpty { return name }
            if let coach = self.currentCoach, !coach.name.isEmpty { return coach.name }
            return "Anonymous"
        }()
        let data: [String: Any] = [
            "stringerId": stringerId,
            "reviewerName": reviewerName,
            "rating": rating,
            "comment": comment,
            "createdBy": uid,
            "createdAt": FieldValue.serverTimestamp()
        ]
        self.db.collection("stringerReviews").addDocument(data: data) { err in
            if let err = err {
                print("addStringerReview error: \(err)")
                completion(err)
                return
            }
            DispatchQueue.main.async { self.fetchStringerReviews(stringerId: stringerId) }
            completion(nil)
        }
    }

    // MARK: - Stringer Orders

    func submitStringerOrder(stringerId: String, racketName: String, hasOwnString: Bool, selectedString: String?, stringCost: String?, laborCost: String?, orderTotal: String?, tension: Int, timelinePreference: String, stringerCreatedBy: String, completion: @escaping (Error?) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(NSError(domain: "FirestoreManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]))
            return
        }
        let buyerName: String = {
            if let name = self.currentClient?.name, !name.isEmpty { return name }
            if let coach = self.currentCoach, !coach.name.isEmpty { return coach.name }
            return "Someone"
        }()
        var data: [String: Any] = [
            "stringerId": stringerId,
            "racketName": racketName,
            "hasOwnString": hasOwnString,
            "tension": tension,
            "timelinePreference": timelinePreference,
            "createdBy": uid,
            "createdAt": FieldValue.serverTimestamp(),
            "status": "placed",
            "buyerName": buyerName
        ]
        if let s = selectedString { data["selectedString"] = s }
        if let c = stringCost { data["stringCost"] = c }
        if let l = laborCost { data["laborCost"] = l }
        if let t = orderTotal { data["orderTotal"] = t }
        let newDocRef = self.db.collection("stringerOrders").document()
        newDocRef.setData(data) { err in
            if let err = err {
                print("submitStringerOrder error: \(err)")
                completion(err)
                return
            }
            // Send notification to the stringer owner
            let notifRef = self.db.collection("pendingNotifications")
                .document(stringerCreatedBy)
                .collection("notifications")
                .document()
            let notifData: [String: Any] = [
                "title": "New Stringing Order",
                "body": "\(buyerName) placed a stringing order for \(racketName)",
                "type": "stringer_order_placed",
                "stringerOrderId": newDocRef.documentID,
                "senderId": uid,
                "createdAt": FieldValue.serverTimestamp(),
                "delivered": false
            ]
            notifRef.setData(notifData) { nerr in
                if let nerr = nerr {
                    print("submitStringerOrder notification error: \(nerr)")
                }
            }
            completion(nil)
        }
    }

    // MARK: - Stringer Order Tracking

    func fetchOrdersForStringer(stringerId: String) {
        self.db.collection("stringerOrders")
            .whereField("stringerId", isEqualTo: stringerId)
            .getDocuments { snap, err in
                if let err = err {
                    print("fetchOrdersForStringer error: \(err)")
                    return
                }
                let docs = snap?.documents ?? []
                let results: [StringerOrder] = docs.compactMap { d in
                    self.parseStringerOrder(d)
                }.sorted { $0.createdAt > $1.createdAt }
                DispatchQueue.main.async {
                    self.stringerIncomingOrders = results
                }
            }
    }

    func fetchOrdersForBuyer() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        self.db.collection("stringerOrders")
            .whereField("createdBy", isEqualTo: uid)
            .getDocuments { snap, err in
                if let err = err {
                    print("fetchOrdersForBuyer error: \(err)")
                    return
                }
                let docs = snap?.documents ?? []
                let results: [StringerOrder] = docs.compactMap { d in
                    self.parseStringerOrder(d)
                }.sorted { $0.createdAt > $1.createdAt }
                DispatchQueue.main.async {
                    self.myStringerOrders = results
                }
            }
    }

    func updateStringerOrderStatus(orderId: String, status: String, buyerUid: String, stringerName: String, completion: @escaping (Error?) -> Void) {
        self.db.collection("stringerOrders").document(orderId).updateData([
            "status": status,
            // timestamped per stage so both apps can render an order timeline
            "statusHistory.\(status)": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]) { err in
            if let err = err {
                print("updateStringerOrderStatus error: \(err)")
                completion(err)
                return
            }
            // Notify the buyer of the status change
            let notifRef = self.db.collection("pendingNotifications")
                .document(buyerUid)
                .collection("notifications")
                .document()
            let displayStatus: String = {
                switch status {
                case "ready_for_pickup": return "Ready For Pickup"
                case "picked_up": return "Picked Up"
                default: return status.capitalized
                }
            }()
            let notifData: [String: Any] = [
                "title": "Stringing Order Update",
                "body": "\(stringerName) updated your order status to \(displayStatus)",
                "type": "stringer_order_update",
                "stringerOrderId": orderId,
                "createdAt": FieldValue.serverTimestamp(),
                "delivered": false
            ]
            notifRef.setData(notifData) { nerr in
                if let nerr = nerr {
                    print("updateStringerOrderStatus notification error: \(nerr)")
                }
            }
            completion(nil)
        }
    }

    /// Update a stringing order status as the buyer (e.g. marking as picked up) and notify the stringer.
    func updateStringerOrderStatusAsBuyer(orderId: String, status: String, stringerUid: String, buyerName: String, completion: @escaping (Error?) -> Void) {
        self.db.collection("stringerOrders").document(orderId).updateData([
            "status": status,
            "statusHistory.\(status)": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]) { err in
            if let err = err {
                print("updateStringerOrderStatusAsBuyer error: \(err)")
                completion(err)
                return
            }
            // Notify the stringer of the status change
            let notifRef = self.db.collection("pendingNotifications")
                .document(stringerUid)
                .collection("notifications")
                .document()
            let displayStatus = status == "picked_up" ? "Picked Up" : status.replacingOccurrences(of: "_", with: " ").capitalized
            let notifData: [String: Any] = [
                "title": "Stringing Order Update",
                "body": "\(buyerName) marked their order as \(displayStatus)",
                "type": "stringer_order_update",
                "stringerOrderId": orderId,
                "createdAt": FieldValue.serverTimestamp(),
                "delivered": false
            ]
            notifRef.setData(notifData) { nerr in
                if let nerr = nerr {
                    print("updateStringerOrderStatusAsBuyer notification error: \(nerr)")
                }
            }
            completion(nil)
        }
    }

    private func parseStringerOrder(_ d: QueryDocumentSnapshot) -> StringerOrder? {
        let data = d.data()
        let racketName = data["racketName"] as? String ?? ""
        guard !racketName.isEmpty else { return nil }
        return StringerOrder(
            id: d.documentID,
            stringerId: data["stringerId"] as? String ?? "",
            racketName: racketName,
            hasOwnString: data["hasOwnString"] as? Bool ?? false,
            selectedString: data["selectedString"] as? String,
            stringCost: data["stringCost"] as? String,
            laborCost: data["laborCost"] as? String,
            orderTotal: data["orderTotal"] as? String,
            tension: data["tension"] as? Int ?? 24,
            timelinePreference: data["timelinePreference"] as? String ?? "",
            createdBy: data["createdBy"] as? String ?? "",
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
            status: data["status"] as? String ?? "placed",
            buyerName: data["buyerName"] as? String ?? "Unknown",
            statusHistory: {
                var history: [String: Date] = [:]
                if let raw = data["statusHistory"] as? [String: Timestamp] {
                    for (k, v) in raw { history[k] = v.dateValue() }
                }
                return history
            }()
        )
    }
}
