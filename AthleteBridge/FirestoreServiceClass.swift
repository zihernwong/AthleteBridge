import Foundation
import Firebase
import FirebaseFirestore
import FirebaseAuth
import SwiftUI

@MainActor
class FirestoreManager: ObservableObject {
    // Shared singleton fallback
    static let shared = FirestoreManager()

    // Delay creating Firestore until after Firebase is configured in init
    private var db: Firestore!

    @Published var coaches: [Coach] = []
    @Published var currentClient: Client? = nil
    @Published var currentCoach: Coach? = nil

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

    init() {
        // Ensure Firebase is configured before using Firestore
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
            print("[FirestoreManager] FirebaseApp.configure() called from FirestoreManager.init()")
        }
        self.db = Firestore.firestore()

        // Optionally start listening to coaches collection
        fetchCoaches()
        // Optionally listen for current user's profile
        if let uid = Auth.auth().currentUser?.uid {
            fetchCurrentProfiles(for: uid)
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
        // try client
        self.db.collection("clients").document(uid).getDocument { snap, err in
            if let err = err {
                print("fetchCurrentProfiles client err: \(err)")
            }
            if let data = snap?.data() {
                let id = snap?.documentID ?? uid
                let name = data["name"] as? String ?? ""
                let goals = data["goals"] as? [String] ?? []
                // preferredAvailability may be stored as String or [String]; normalize to [String]
                var preferredArr: [String]
                if let arr = data["preferredAvailability"] as? [String] {
                    preferredArr = arr
                } else if let s = data["preferredAvailability"] as? String {
                    preferredArr = [s]
                } else {
                    preferredArr = ["Morning"]
                }
                DispatchQueue.main.async {
                    self.currentClient = Client(id: id, name: name, goals: goals, preferredAvailability: preferredArr)
                }
            }
        }

        // try coach
        self.db.collection("coaches").document(uid).getDocument { snap, err in
            if let err = err {
                print("fetchCurrentProfiles coach err: \(err)")
            }
            if let data = snap?.data() {
                let id = snap?.documentID ?? uid
                let first = data["FirstName"] as? String ?? ""
                let last = data["LastName"] as? String ?? ""
                let name = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
                let specialties = data["Specialties"] as? [String] ?? []
                let experience = data["ExperienceYears"] as? Int ?? (data["ExperienceYears"] as? Double).flatMap { Int($0) } ?? 0
                let availability = data["Availability"] as? [String] ?? []
                DispatchQueue.main.async {
                    self.currentCoach = Coach(id: id, name: name, specialties: specialties, experienceYears: experience, availability: availability)
                }
            }
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

    /// Debug helper: fetch and print every document in the `bookings` collection.
    /// Useful to confirm what's actually stored in Firestore (raw documents).
    func fetchAllBookingsDebug() {
        let bookingsColl = self.db.collection("bookings")
        bookingsColl.getDocuments { snapshot, error in
            if let error = error {
                let msg = "fetchAllBookingsDebug error: \(error.localizedDescription)"
                print(msg)
                DispatchQueue.main.async { self.bookingsDebug += "\n\(msg)" }
                return
            }

            let docs = snapshot?.documents ?? []
            let header = "fetchAllBookingsDebug: total=\(docs.count)"
            print(header)
            DispatchQueue.main.async { self.bookingsDebug += "\n\(header)" }

            for doc in docs {
                let data = doc.data()
                let line = "doc: \(doc.documentID) -> \(data)"
                print(line)
                DispatchQueue.main.async { self.bookingsDebug += "\n\(line)" }
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

    // Save a booking to `bookings` collection using DocumentReference for client and coach
    func saveBooking(clientRef: DocumentReference, coachRef: DocumentReference, startAt: Date, endAt: Date, location: String?, notes: String?, status: String = "requested", completion: @escaping (Error?) -> Void) {
        var data: [String: Any] = [
            "ClientID": clientRef,
            "CoachID": coachRef,
            "StartAt": Timestamp(date: startAt),
            "EndAt": Timestamp(date: endAt),
            "Location": location ?? "",
            "Notes": notes ?? "",
            "Status": status,
            "CreatedAt": FieldValue.serverTimestamp()
        ]
        db.collection("bookings").addDocument(data: data) { error in
            if let error = error {
                print("saveBooking error: \(error)")
                completion(error)
            } else {
                print("saveBooking: booking created")
                completion(nil)
            }
        }
    }

    // Convenience: Save a booking by client uid and coach uid (stores DocumentReference internally)
    func saveBooking(clientUid: String, coachUid: String, startAt: Date, endAt: Date, location: String?, notes: String?, status: String = "requested", completion: @escaping (Error?) -> Void) {
        let clientRef = db.collection("clients").document(clientUid)
        let coachRef = db.collection("coaches").document(coachUid)
        saveBooking(clientRef: clientRef, coachRef: coachRef, startAt: startAt, endAt: endAt, location: location, notes: notes, status: status, completion: completion)
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
}
