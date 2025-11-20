// FirestoreService.swift
// Provides simple helpers to load Coach and Client data from Firestore

import Foundation
import FirebaseCore
import FirebaseFirestore

// NOTE: Make sure you've added Firebase SDK to the project (FirebaseCore, FirebaseAuth, FirebaseFirestore)
// and called `FirebaseApp.configure()` in your App entry (AthleteBridgeApp).

final class FirestoreService: ObservableObject {
    @Published var coaches: [Coach] = []
    @Published var currentClient: Client? = nil
    @Published var currentCoach: Coach? = nil

    // helpful debug string you can bind to a UI label to inspect recent logs
    @Published var debugLog: String = ""

    private let db = Firestore.firestore()
    private let debugEnabled: Bool = true

    init() {
        // sanity check: is Firebase configured?
        if let app = FirebaseApp.app() {
            let opts = app.options
            let project = opts.projectID ?? "<no projectID>"
            let client = opts.clientID ?? "<no clientID>"
            let api = opts.apiKey ?? "<no apiKey>"
            log("[init] FirebaseApp present: project=\(project), client=\(client), apiKey=****\(api.suffix(min(4, api.count)))")
        } else {
            log("[init] WARNING: FirebaseApp.app() is nil — make sure FirebaseApp.configure() was called and GoogleService-Info.plist is present and correct.")
        }

        // Run extended configuration checks to help debug missing data
        debugCheckConfiguration()
    }

    private func log(_ message: String) {
        // append timestamped line to debugLog and also print
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "[FirestoreService] \(ts) - \(message)"
        DispatchQueue.main.async {
            // keep a short rolling log (last ~2000 chars)
            self.debugLog = ((self.debugLog + "\n") + line).suffix(4000).description
        }
        if debugEnabled {
            print(line)
        }
    }

    // Print extra diagnostic configuration info: bundle plist, Firestore settings
    private func debugCheckConfiguration() {
        log("debugCheckConfiguration: starting")

        // 1) Check for GoogleService-Info.plist in main bundle
        if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") {
            log("debugCheckConfiguration: found GoogleService-Info.plist at: \(path)")
            if let dict = NSDictionary(contentsOfFile: path) as? [String: Any] {
                // Log a few expected keys (mask secrets)
                let projectID = dict["PROJECT_ID"] as? String ?? "<none>"
                let clientID = dict["CLIENT_ID"] as? String ?? "<none>"
                let apiKey = (dict["API_KEY"] as? String) ?? (dict["GCM_SENDER_ID"] as? String) ?? "<none>"
                // ensure both branches return String (suffix returns Substring)
                let apiTail = apiKey.count > 4 ? String(apiKey.suffix(4)) : apiKey
                log("GoogleService-Info keys: PROJECT_ID=\(projectID), CLIENT_ID=\(clientID), API_KEY=****\(apiTail)")
            } else {
                log("debugCheckConfiguration: unable to read plist dictionary from path")
            }
        } else {
            log("debugCheckConfiguration: GoogleService-Info.plist NOT FOUND in bundle")
        }

        // 2) Log Firestore settings
        let settings = db.settings
        // `settings.host` is non-optional; avoid nil-coalescing with a non-optional value.
        let host = settings.host
        log("Firestore settings: host=\(host)")

        // 3) App-level Firebase options
        if let app = FirebaseApp.app() {
            let opts = app.options
            log("FirebaseApp.options: projectID=\(opts.projectID ?? "<none>"), bundleID=\(Bundle.main.bundleIdentifier ?? "<none>")")
        }

        log("debugCheckConfiguration: done")
    }

    private func printErrorDetails(_ error: Error) {
        let ns = error as NSError
        log("Error domain=\(ns.domain) code=\(ns.code) localized=\(ns.localizedDescription)")
        if !ns.userInfo.isEmpty {
            log("Error userInfo: \(ns.userInfo)")
            // log nested underlying error if present
            if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
                log("Underlying NSError: domain=\(underlying.domain) code=\(underlying.code) userInfo=\(underlying.userInfo)")
            }
        }
    }

    // Fetch all coaches once
    func fetchCoaches() {
        // Use the existing lowercase collection name as primary
        let primary = "coaches"
        log("fetchCoaches() -> attempting collection '\(primary)'")

        db.collection(primary).getDocuments { [weak self] snapshot, error in
             if let error = error {
                 self?.log("fetchCoaches error on '\(primary)': \(error.localizedDescription)")
                 self?.printErrorDetails(error)
                 return
             }

             let docs = snapshot?.documents ?? []
             self?.log("fetchCoaches: received \(docs.count) documents from '\(primary)'")

             // log snapshot metadata
             if let meta = snapshot?.metadata {
                 self?.log("snapshot metadata - isFromCache=\(meta.isFromCache), hasPendingWrites=\(meta.hasPendingWrites)")
             }

             if docs.isEmpty {
                 // fallback to capitalized collection name if present
                 let alt = "Coaches"
                 self?.log("fetchCoaches: no docs in '\(primary)' — trying fallback '\(alt)'")
                 self?.db.collection(alt).getDocuments { [weak self] altSnapshot, altError in
                     if let altError = altError {
                         self?.log("fetchCoaches error on '\(alt)': \(altError.localizedDescription)")
                         self?.printErrorDetails(altError)
                         return
                     }
                     let altDocs = altSnapshot?.documents ?? []
                     self?.log("fetchCoaches: received \(altDocs.count) documents from '\(alt)'")
                     if let altMeta = altSnapshot?.metadata {
                         self?.log("alt snapshot metadata - isFromCache=\(altMeta.isFromCache), hasPendingWrites=\(altMeta.hasPendingWrites)")
                     }
                     self?.processCoachDocuments(altDocs)
                 }
                 return
             }

             self?.processCoachDocuments(docs)
         }
     }

    private func processCoachDocuments(_ documents: [QueryDocumentSnapshot]) {
        log("processCoachDocuments: processing \(documents.count) documents")
        let mapped = documents.compactMap { doc -> Coach? in
            let data = doc.data()
            log("doc id=\(doc.documentID) data=\(data)")
            let name = data["FirstName"] as? String ?? data["name"] as? String ?? "Unknown"
            let specialties = data["Specialties"] as? [String] ?? data["specialties"] as? [String] ?? []
            let experienceYears = data["ExperienceYears"] as? Int ?? (data["ExperienceYears"] as? Double).map { Int($0) } ?? (data["experienceYears"] as? Int ?? 0)
            let availability = data["Availability"] as? [String] ?? data["availability"] as? [String] ?? []

            // Validate types and warn if fields unexpected
            if let rawName = data["FirstName"] ?? data["name"], !(rawName is String) {
                log("Warning: coach name field is not a String for doc=\(doc.documentID) raw=\(rawName)")
            }

            // Use Firestore document ID (doc.documentID) as the coach id
            return Coach(id: doc.documentID, name: name, specialties: specialties, experienceYears: experienceYears, availability: availability)
        }

        DispatchQueue.main.async { [weak self] in
            self?.coaches = mapped
            self?.log("processCoachDocuments: updated local coaches array with \(mapped.count) items")
        }
    }

    // Listen for live updates to coaches collection
    func listenToCoaches() -> ListenerRegistration {
        let primary = "coaches"
        log("listenToCoaches() -> adding listener to '\(primary)'")

        let listener = db.collection(primary).addSnapshotListener { [weak self] snapshot, error in
             if let error = error {
                 self?.log("listenToCoaches error on '\(primary)': \(error.localizedDescription)")
                 self?.printErrorDetails(error)
                 return
             }

             let docs = snapshot?.documents ?? []
             self?.log("listenToCoaches: snapshot with \(docs.count) docs from '\(primary)'")

             if let meta = snapshot?.metadata {
                 self?.log("listen snapshot metadata - isFromCache=\(meta.isFromCache), hasPendingWrites=\(meta.hasPendingWrites)")
             }

             if docs.isEmpty {
                 // fallback to capitalized collection name if present
                 let alt = "Coaches"
                 self?.log("listenToCoaches: no docs in '\(primary)' snapshot — attempting listener on '\(alt)'")
                 let altListener = self?.db.collection(alt).addSnapshotListener { [weak self] altSnapshot, altError in
                     if let altError = altError {
                         self?.log("listenToCoaches error on '\(alt)': \(altError.localizedDescription)")
                         self?.printErrorDetails(altError)
                         return
                     }
                     let altDocs = altSnapshot?.documents ?? []
                     self?.log("listenToCoaches: snapshot with \(altDocs.count) docs from '\(alt)'")
                     if let altMeta = altSnapshot?.metadata {
                         self?.log("alt listen snapshot metadata - isFromCache=\(altMeta.isFromCache), hasPendingWrites=\(altMeta.hasPendingWrites)")
                     }
                     self?.processCoachDocuments(altDocs)
                 }
                 // Note: returning here doesn't cancel the primary listener; callers should hold and remove returned listener when appropriate
                 return
             }

             self?.processCoachDocuments(docs)
         }

         return listener
     }

    // Fetch a client document by id (for example, Firestore document id = user uid)
    func fetchClient(withId id: String, completion: ((Client?) -> Void)? = nil) {
        // Use lowercase `clients` as the primary collection to match app's canonical collection
        let primary = "clients"
        log("fetchClient(\(id)) -> attempting '\(primary)/\(id)')")

        db.collection(primary).document(id).getDocument { [weak self] snapshot, error in
            if let error = error {
                self?.log("fetchClient error on '\(primary)/\(id)': \(error.localizedDescription)")
                self?.printErrorDetails(error)
                completion?(nil)
                return
            }

            if let data = snapshot?.data(), !data.isEmpty {
                self?.log("fetchClient: found document in '\(primary)' id=\(id) data=\(data)")
                if let meta = snapshot?.metadata {
                    self?.log("fetchClient snapshot metadata - isFromCache=\(meta.isFromCache), hasPendingWrites=\(meta.hasPendingWrites)")
                }
                self?.processClientData(data: data, docId: id, completion: completion)
                return
            }

            // fallback to capitalized collection name if present (backwards compatibility)
            let alt = "Clients"
            self?.log("fetchClient: no doc in '\(primary)' — trying '\(alt)/\(id)'")
            self?.db.collection(alt).document(id).getDocument { [weak self] altSnapshot, altError in
                if let altError = altError {
                    self?.log("fetchClient error on '\(alt)/\(id)': \(altError.localizedDescription)")
                    self?.printErrorDetails(altError)
                    completion?(nil)
                    return
                }

                if let altData = altSnapshot?.data() {
                    self?.log("fetchClient: found document in '\(alt)' id=\(id) data=\(altData)")
                    if let altMeta = altSnapshot?.metadata {
                        self?.log("alt fetchClient snapshot metadata - isFromCache=\(altMeta.isFromCache), hasPendingWrites=\(altMeta.hasPendingWrites)")
                    }
                    self?.processClientData(data: altData, docId: id, completion: completion)
                } else {
                    self?.log("fetchClient: no document found for id=\(id) in either collection")
                    completion?(nil)
                }
            }
        }
    }

    private func processClientData(data: [String: Any], docId: String, completion: ((Client?) -> Void)? = nil) {
        log("processClientData: data=\(data) docId=\(docId)")
        let name = data["FirstName"] as? String ?? data["name"] as? String ?? "Unnamed"
        let goals = data["Goals"] as? [String] ?? data["goals"] as? [String] ?? []
        let preferredAvailability = data["PreferredAvailability"] as? String ?? data["preferredAvailability"] as? String ?? ""

        let client = Client(id: docId, name: name, goals: goals, preferredAvailability: preferredAvailability)
        DispatchQueue.main.async { [weak self] in
            self?.currentClient = client
            completion?(client)
            self?.log("processClientData: set currentClient=\(client.name) id=\(client.id)")
        }
    }

    /// Save a coach document using the exact schema keys you specified.
    /// - Parameters:
    ///   - id: document id (typically the Auth UID)
    ///   - firstName: coach first name -> written as `FirstName`
    ///   - lastName: coach last name -> written as `LastName`
    ///   - specialties: array of specialties -> written as `Specialties`
    ///   - availability: array of availability strings -> written as `Availability`
    ///   - experienceYears: number -> written as `ExperienceYears`
    ///   - hourlyRate: optional number -> written as `HourlyRate` when provided
    ///   - photoURL: optional string -> written as `PhotoURL`
    ///   - active: boolean -> written as `Active` (defaults to true)
    ///   - overwrite: if true the document will be overwritten; if false the fields will be merged into any existing doc
    ///   - completion: callback with optional Error
    func saveCoachWithSchema(id: String,
                              firstName: String,
                              lastName: String,
                              specialties: [String],
                              availability: [String],
                              experienceYears: Int,
                              hourlyRate: Double? = nil,
                              photoURL: String? = nil,
                              active: Bool = true,
                              overwrite: Bool = true,
                              completion: ((Error?) -> Void)? = nil) {

        // Write into the existing lowercase `coaches` collection (project already uses 'coaches')
        let collection = "coaches"
        log("saveCoachWithSchema: preparing to write doc '\(collection)/\(id)'")

        var data: [String: Any] = [
            "uid": id,
            "FirstName": firstName,
            "LastName": lastName,
            "Specialties": specialties,
            "Availability": availability,
            "ExperienceYears": experienceYears,
            "Active": active,
            "CreatedAt": FieldValue.serverTimestamp()
        ]

        if let rate = hourlyRate {
            data["HourlyRate"] = rate
        }

        // Use empty string if photoURL is nil to match your example (you can change behavior if you prefer nil)
        data["PhotoURL"] = photoURL ?? ""

        log("saveCoachWithSchema: writing data=\(data)")

        if overwrite {
            db.collection(collection).document(id).setData(data) { [weak self] error in
                if let error = error {
                    self?.log("saveCoachWithSchema: error writing document: \(error.localizedDescription)")
                    self?.printErrorDetails(error)
                    completion?(error)
                    return
                }
                self?.log("saveCoachWithSchema: successfully wrote document id=\(id)")
                // Optionally update local model
                let coach = Coach(id: id, name: "\(firstName) \(lastName)", specialties: specialties, experienceYears: experienceYears, availability: availability)
                DispatchQueue.main.async {
                    self?.currentCoach = coach
                }
                completion?(nil)
            }
        } else {
            // merge into existing doc
            db.collection(collection).document(id).setData(data, merge: true) { [weak self] error in
                if let error = error {
                    self?.log("saveCoachWithSchema (merge): error writing document: \(error.localizedDescription)")
                    self?.printErrorDetails(error)
                    completion?(error)
                    return
                }
                self?.log("saveCoachWithSchema (merge): successfully merged document id=\(id)")
                let coach = Coach(id: id, name: "\(firstName) \(lastName)", specialties: specialties, experienceYears: experienceYears, availability: availability)
                DispatchQueue.main.async {
                    self?.currentCoach = coach
                }
                completion?(nil)
            }
        }
    }

    /// Save or update a client document (document id = uid)
    func saveClient(id: String, name: String, goals: [String], preferredAvailability: String, completion: ((Error?) -> Void)? = nil) {
        // Write into the existing lowercase `clients` collection (canonical)
        let primary = "clients"
        let data: [String: Any] = [
            "uid": id,
            "name": name,
            "goals": goals,
            "preferredAvailability": preferredAvailability,
            "createdAt": FieldValue.serverTimestamp()
        ]

        log("saveClient: writing client doc to '\(primary)/\(id)' data=\(data)")
        db.collection(primary).document(id).setData(data) { [weak self] error in
            if let error = error {
                self?.log("saveClient: error writing client doc: \(error.localizedDescription)")
                self?.printErrorDetails(error)
                completion?(error)
                return
            }

            self?.log("saveClient: successfully wrote client document id=\(id)")
            // update local model
            let client = Client(id: id, name: name, goals: goals, preferredAvailability: preferredAvailability)
            DispatchQueue.main.async {
                self?.currentClient = client
            }
            completion?(nil)
        }
    }
}
