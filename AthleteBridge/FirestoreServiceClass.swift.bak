import Foundation
import Firebase
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage
import SwiftUI

@MainActor
class FirestoreManager: ObservableObject {
    // Shared singleton fallback
    static let shared = FirestoreManager()

    // Delay creating Firestore until after Firebase is configured in init
    private var db: Firestore!
    private var authStateListenerHandle: AuthStateDidChangeListenerHandle?

    @Published var coaches: [Coach] = []
    @Published var currentClient: Client? = nil
    @Published var currentClientPhotoURL: URL? = nil
    @Published var currentCoach: Coach? = nil
    @Published var currentCoachPhotoURL: URL? = nil

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
            } else {
                // user signed out - clear cached profiles and photo URLs
                DispatchQueue.main.async {
                    self.currentClient = nil
                    self.currentClientPhotoURL = nil
                    self.currentCoach = nil
                    self.currentCoachPhotoURL = nil
                }
            }
        }

        // Optionally start listening to coaches collection
        fetchCoaches()
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
        self.db.collection("coaches").getDocuments { snapshot, error in
            if let error = error {
                print("FirestoreManager: fetchCoaches error: \(error)")
                return
            }
            guard let docs = snapshot?.documents else { return }
            let mapped: [Coach] = docs.compactMap { d in
                let data = d.data()
                let id = d.documentID
                let first = data["FirstName"] as? String ?? ""
                let last = data["LastName"] as? String ?? ""
                let name = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
                let specialties = data["Specialties"] as? [String] ?? []
                let experience = data["ExperienceYears"] as? Int ?? (data["ExperienceYears"] as? Double).flatMap { Int($0) } ?? 0
                let availability = data["Availability"] as? [String] ?? []
                return Coach(id: id, name: name, specialties: specialties, experienceYears: experience, availability: availability)
            }
            DispatchQueue.main.async {
                self.coaches = mapped
            }
        }
    }

    func fetchCurrentProfiles(for uid: String) {
        // Fetch client document and resolve photo URL
        let clientRef = db.collection("clients").document(uid)
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

            let photoStr = (data["photoURL"] as? String) ?? (data["PhotoURL"] as? String)
            self.resolvePhotoURL(photoStr) { resolved in
                DispatchQueue.main.async {
                    self.currentClient = Client(id: id, name: name, goals: goals, preferredAvailability: preferredArr)
                    self.currentClientPhotoURL = resolved
                    if resolved == nil { print("fetchCurrentProfiles: no client photo for \(id)") }
                }
            }
        }

        // Fetch coach document and resolve photo URL
        let coachRef = db.collection("coaches").document(uid)
        coachRef.getDocument { snap, err in
            if let err = err {
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

            let photoStr = (data["PhotoURL"] as? String) ?? (data["photoUrl"] as? String) ?? (data["photoURL"] as? String)
            self.resolvePhotoURL(photoStr) { resolved in
                DispatchQueue.main.async {
                    self.currentCoach = Coach(id: id, name: name, specialties: specialties, experienceYears: experience, availability: availability)
                    self.currentCoachPhotoURL = resolved
                    if resolved == nil { print("fetchCurrentProfiles: no coach photo for \(id)") }
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

    // Save client document using provided id
    func saveClient(id: String, name: String, goals: [String], preferredAvailability: [String], photoURL: String?, completion: @escaping (Error?) -> Void) {
        var data: [String: Any] = [
            "name": name,
            "goals": goals,
            "preferredAvailability": preferredAvailability,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let p = photoURL { data["photoURL"] = p }
        self.db.collection("clients").document(id).setData(data, merge: true, completion: completion)
    }

    // Save coach with the provided schema to "coaches" collection under document id
    func saveCoachWithSchema(id: String, firstName: String, lastName: String, specialties: [String], availability: [String], experienceYears: Int, hourlyRate: Double?, photoURL: String?, active: Bool = true, overwrite: Bool = false, completion: @escaping (Error?) -> Void) {
        var data: [String: Any] = [
            "FirstName": firstName,
            "LastName": lastName,
            "Specialties": specialties,
            "Availability": availability,
            "ExperienceYears": experienceYears,
            "Active": active,
            "CreatedAt": FieldValue.serverTimestamp()
        ]
        if let hr = hourlyRate { data["HourlyRate"] = hr }
        if let p = photoURL { data["PhotoURL"] = p }

        let docRef = self.db.collection("coaches").document(id)
        if overwrite {
            docRef.setData(data, completion: completion)
        } else {
            docRef.setData(data, merge: true, completion: completion)
        }
    }

    // Save a review document to "reviews" collection
    func saveReview(clientID: String, coachID: String, rating: String, ratingMessage: String, completion: @escaping (Error?) -> Void) {
        let data: [String: Any] = [
            "ClientID": clientID,
            "CoachID": coachID,
            "CreatedAt": FieldValue.serverTimestamp(),
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

        let bookingsColl = db.collection("bookings")
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
                                let item = BookingItem(id: doc.documentID, clientID: clientID, clientName: clientName, coachID: coachID, coachName: coachName, startAt: startAt, endAt: endAt, location: location, notes: notes, status: status)
                                results.append(item)
                                group.leave()
                            }
                        } else {
                            // coach might be string
                            if let coachStr = data["CoachID"] as? String { coachID = coachStr.split(separator: "/").last.map(String.init) ?? coachStr }
                            let startAt = (data["StartAt"] as? Timestamp)?.dateValue()
                            let endAt = (data["EndAt"] as? Timestamp)?.dateValue()
                            let location = data["Location"] as? String
                            let notes = data["Notes"] as? String
                            let status = data["Status"] as? String
                            let item = BookingItem(id: doc.documentID, clientID: clientID, clientName: clientName, coachID: coachID, coachName: coachName, startAt: startAt, endAt: endAt, location: location, notes: notes, status: status)
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
                            let item = BookingItem(id: doc.documentID, clientID: clientID, clientName: clientName, coachID: coachID, coachName: coachName, startAt: startAt, endAt: endAt, location: location, notes: notes, status: status)
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
                        let item = BookingItem(id: doc.documentID, clientID: clientID, clientName: clientName, coachID: coachID, coachName: coachName, startAt: startAt, endAt: endAt, location: location, notes: notes, status: status)
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
                print("[FirestoreManager] debugCreateAndVerifyBooking: booking created and mirrors verified (see above)")
            }
        }
    }

    /// Remove legacy booking arrays from parent documents.
    /// Deletes the `calendar` field on every coach and the `bookings` field on every client.
    /// Works in batched chunks to avoid exceeding the 500-operation per-batch limit.
    func removeBookingArraysFromParents(completion: @escaping (Error?) -> Void) {
        let coachColl = db.collection("coaches")
        let clientColl = db.collection("clients")

        let group = DispatchGroup()
        var firstError: Error? = nil

        func processDocs(_ docs: [QueryDocumentSnapshot], fieldName: String, collectionName: String, finish: @escaping () -> Void) {
            // Partition into batches of 450 updates to be safe
            let batchSize = 450
            var index = 0
            while index < docs.count {
                let end = min(index + batchSize, docs.count)
                let batch = db.batch()
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
                return BookingItem(id: id, clientID: clientID, clientName: nil, coachID: coachId, coachName: nil, startAt: startAt, endAt: endAt, location: location, notes: notes, status: status)
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
                return BookingItem(id: id, clientID: clientId, clientName: nil, coachID: coachID, coachName: nil, startAt: startAt, endAt: endAt, location: location, notes: notes, status: status)
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
                let createdAt = (data["CreatedAt"] as? Timestamp)?.dateValue()

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
                    // attempt to fetch the client doc to get a name
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
                let createdAt = (data["CreatedAt"] as? Timestamp)?.dateValue()

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
        let coll = db.collection("locations")

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
        let batch = db.batch()
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
        let bookingsColl = db.collection("bookings")
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
        let coachRef = db.collection("coaches").document(coachId)
        let clientRef = db.collection("clients").document(clientId)
        let bookingRef = db.collection("bookings").document()
        let coachBookingRef = coachRef.collection("bookings").document(bookingRef.documentID)
        let clientBookingRef = clientRef.collection("bookings").document(bookingRef.documentID)

        var data: [String: Any] = [
            "CoachID": coachRef,
            "ClientID": clientRef,
            "StartAt": Timestamp(date: startAt),
            "EndAt": Timestamp(date: endAt),
            "Location": location ?? "",
            "Notes": notes ?? "",
            "Status": status,
            "CreatedAt": FieldValue.serverTimestamp()
        ]
        if let extra = extra { for (k,v) in extra { data[k] = v } }

        print("[FirestoreManager] saveBookingAndMirror begin: bookingId=\(bookingRef.documentID) coachId=\(coachId) clientId=\(clientId)")

        let batch = db.batch()
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
            // Use a concrete client-side timestamp for array elements; server-side
            // sentinels (FieldValue.serverTimestamp()) aren't allowed inside
            // arrayUnion payloads. The authoritative server timestamp still exists
            // on the root booking document's CreatedAt field.
            "CreatedAt": Timestamp(date: Date())
        ]

        // Use arrayUnion to append without duplicating existing entries.
        batch.updateData(["calendar": FieldValue.arrayUnion([bookingSummary])], forDocument: coachRef)

        // Also mirror the booking under the coach/client subcollections and append a
        // denormalized summary into the coach's `calendar` array for fast lookups.
        // Warning: storing unbounded arrays on documents can grow large; consider
        // migrating to subcollections only if calendar arrays become too large.

        batch.commit { [weak self] err in
            guard let self = self else { completion(err); return }
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
                    completion(nil)
                }
            }
        }
    }

    /// Convenience wrapper used by UI to save a booking. Calls the internal saveBookingAndMirror implementation.
    func saveBooking(clientUid: String, coachUid: String, startAt: Date, endAt: Date, location: String?, notes: String?, status: String = "requested", completion: @escaping (Error?) -> Void) {
        saveBookingAndMirror(coachId: coachUid, clientId: clientUid, startAt: startAt, endAt: endAt, status: status, location: location, notes: notes, extra: nil, completion: completion)
    }

    /// Debug helper to fetch all bookings (root collection) and append a readable dump into bookingsDebug.
    func fetchAllBookingsDebug() {
        DispatchQueue.main.async { self.bookingsDebug = "Starting fetchAllBookingsDebug..." }
        let coll = db.collection("bookings")
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

    /// Fetch all bookings stored under each coach's `bookings` subcollection and populate `coachBookings`.
    func fetchAllCoachBookings() {
        DispatchQueue.main.async { self.coachBookingsDebug = "Starting fetchAllCoachBookings..." }
        let coachColl = db.collection("coaches")
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

                        let item = BookingItem(id: id, clientID: clientID, clientName: clientName, coachID: coachId, coachName: coachName.isEmpty ? coachId : coachName, startAt: startAt, endAt: endAt, location: location, notes: notes, status: status)
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
}
