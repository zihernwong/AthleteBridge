import Foundation
@preconcurrency import FirebaseFirestore
@preconcurrency import FirebaseAuth

/// Per-view store for a linked web tournament. Kept separate from
/// FirestoreManager on purpose: publishing from the shared manager rebuilds
/// the home screen and pops pushed views off the navigation stack.
@MainActor
final class WebTournamentStore: ObservableObject {
    @Published var webTournament: WebTournament?
    @Published var suggestions: [WebTournament] = []
    @Published var isWorking = false

    private var listener: ListenerRegistration?
    private var db: Firestore { Firestore.firestore() }

    deinit {
        listener?.remove()
    }

    // MARK: - Live doc

    func listen(webId: String) {
        listener?.remove()
        listener = db.collection("webTournaments").document(webId).addSnapshotListener { [weak self] snap, err in
            if let err = err {
                print("WebTournamentStore.listen error: \(err)")
                return
            }
            let parsed = snap?.data().map { WebTournament.parse(id: webId, data: $0) }
            DispatchQueue.main.async { self?.webTournament = parsed }
        }
    }

    func stop() {
        listener?.remove()
        listener = nil
    }

    // MARK: - Auto-suggest linking

    /// Suggest webTournaments whose name overlaps the app tournament's and
    /// whose date (if parseable) is within a week of the app dates.
    func fetchSuggestions(for tournament: Tournament) {
        db.collection("webTournaments").getDocuments { [weak self] snap, err in
            if let err = err {
                print("WebTournamentStore.fetchSuggestions error: \(err)")
                return
            }
            let candidates = (snap?.documents ?? []).map { WebTournament.parse(id: $0.documentID, data: $0.data()) }
            let appTokens = Self.tokens(tournament.name)
            let scored: [(WebTournament, Int)] = candidates.compactMap { wt in
                let overlap = Self.tokens(wt.name).intersection(appTokens).count
                var score = overlap * 2
                if let wtDate = wt.parsedDate {
                    let interval = abs(wtDate.timeIntervalSince(tournament.startDate))
                    if interval <= 7 * 86400 { score += 3 }
                    else if interval > 60 * 86400 && overlap == 0 { return nil }
                }
                guard score >= 2 else { return nil }
                return (wt, score)
            }
            let top = scored.sorted { $0.1 > $1.1 }.prefix(3).map { $0.0 }
            DispatchQueue.main.async { self?.suggestions = top }
        }
    }

    private static func tokens(_ name: String) -> Set<String> {
        Set(name.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            .filter { $0.count > 2 })
    }

    // MARK: - Linking

    func link(appTournamentId: String, webId: String, completion: ((Error?) -> Void)? = nil) {
        db.collection("tournaments").document(appTournamentId).updateData(["webTournamentId": webId]) { err in
            if let err = err { print("WebTournamentStore.link error: \(err)") }
            DispatchQueue.main.async { completion?(err) }
        }
    }

    func unlink(appTournamentId: String, completion: ((Error?) -> Void)? = nil) {
        stop()
        webTournament = nil
        db.collection("tournaments").document(appTournamentId).updateData(["webTournamentId": FieldValue.delete()]) { err in
            if let err = err { print("WebTournamentStore.unlink error: \(err)") }
            DispatchQueue.main.async { completion?(err) }
        }
    }

    // MARK: - Create from app

    /// Create a webTournaments doc pre-filled from the app tournament,
    /// mirroring the web manager's createT() defaults, then link it.
    func createWebTournament(from tournament: Tournament, completion: @escaping (String?) -> Void) {
        let ref = db.collection("webTournaments").document()
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"

        // Events: union of what participants signed up for, else all three open doubles
        var eventKeys = Set(tournament.participants.values.flatMap { $0.events }
            .compactMap { WebTournamentEvents.appEventKeys[$0] })
        if eventKeys.isEmpty { eventKeys = ["mens_doubles", "womens_doubles", "mixed_doubles"] }
        let events = Array(eventKeys).sorted()
        var eventData: [String: Any] = [:]
        for ev in events {
            eventData[ev] = ["players": [], "bracket": NSNull(), "status": "setup", "champion": NSNull()]
        }

        var doc: [String: Any] = [
            "id": ref.documentID,
            "name": tournament.name,
            "date": df.string(from: tournament.startDate),
            "location": tournament.location,
            "format": "SE",
            "sport": "Badminton",
            "startTime": "09:00",
            "numCourts": 2,
            "maxPlayers": 0,
            "notes": "",
            "prizes": ["first": "", "second": "", "third": ""],
            "events": events,
            "eventData": eventData,
            "status": "setup",
            "created": Int(Date().timeIntervalSince1970 * 1000),
        ]
        if let uid = Auth.auth().currentUser?.uid {
            doc["createdBy"] = uid
        }

        isWorking = true
        ref.setData(doc) { [weak self] err in
            DispatchQueue.main.async {
                self?.isWorking = false
                if let err = err {
                    print("WebTournamentStore.createWebTournament error: \(err)")
                    completion(nil)
                    return
                }
                self?.link(appTournamentId: tournament.id, webId: ref.documentID)
                self?.listen(webId: ref.documentID)
                completion(ref.documentID)
            }
        }
    }

    // MARK: - Score entry

    /// Save a match result exactly the way the web manager does: propagate the
    /// winner/loser through the bracket, reassign the freed court, complete the
    /// event when all matches are done, and update webPlayers stats + H2H.
    func submitScore(webId: String, event: String?, matchId: String, sets: [WebSetScore], completion: @escaping (String?) -> Void) {
        isWorking = true
        db.collection("webTournaments").document(webId).getDocument { [weak self] snap, err in
            guard let self = self else { return }
            guard err == nil, let data = snap?.data() else {
                DispatchQueue.main.async { self.isWorking = false; completion("Couldn't load tournament") }
                return
            }
            var wt = WebTournament.parse(id: webId, data: data)
            var ed = wt.eventData(for: event)
            guard let outcome = WebBracketLogic.applyScore(eventData: &ed, matchId: matchId, sets: sets) else {
                DispatchQueue.main.async { self.isWorking = false; completion("Scores must determine a winner (2 sets)") }
                return
            }

            var updates: [AnyHashable: Any] = [:]
            if let event = event, !wt.events.isEmpty {
                wt.eventData[event] = ed
                updates[FieldPath(["eventData", event])] = ed.firestoreValue
                updates["status"] = WebBracketLogic.overallStatus(events: wt.events, eventData: wt.eventData)
            } else {
                updates["bracket"] = ed.bracket?.firestoreValue as Any? ?? NSNull()
                updates["status"] = ed.status
                updates["champion"] = ed.champion as Any? ?? NSNull()
            }

            self.db.collection("webTournaments").document(webId).updateData(updates) { uerr in
                DispatchQueue.main.async {
                    self.isWorking = false
                    if let uerr = uerr {
                        print("WebTournamentStore.submitScore write error: \(uerr)")
                        completion("Couldn't save the score")
                        return
                    }
                    completion(nil)
                }
                // Ratings + H2H, fire-and-forget like the web
                self.applyStatsUpdates(eventData: ed, outcome: outcome, newSets: sets)
            }
        }
    }

    func clearScore(webId: String, event: String?, matchId: String, completion: @escaping (String?) -> Void) {
        isWorking = true
        db.collection("webTournaments").document(webId).getDocument { [weak self] snap, err in
            guard let self = self else { return }
            guard err == nil, let data = snap?.data() else {
                DispatchQueue.main.async { self.isWorking = false; completion("Couldn't load tournament") }
                return
            }
            var wt = WebTournament.parse(id: webId, data: data)
            var ed = wt.eventData(for: event)
            let outcome = WebBracketLogic.clearScore(eventData: &ed, matchId: matchId)

            var updates: [AnyHashable: Any] = [:]
            if let event = event, !wt.events.isEmpty {
                wt.eventData[event] = ed
                updates[FieldPath(["eventData", event])] = ed.firestoreValue
                updates["status"] = WebBracketLogic.overallStatus(events: wt.events, eventData: wt.eventData)
            } else {
                updates["bracket"] = ed.bracket?.firestoreValue as Any? ?? NSNull()
                updates["status"] = "active"
                updates["champion"] = NSNull()
            }

            self.db.collection("webTournaments").document(webId).updateData(updates) { uerr in
                DispatchQueue.main.async {
                    self.isWorking = false
                    completion(uerr == nil ? nil : "Couldn't clear the score")
                }
                if let outcome = outcome {
                    let (w1, w2) = WebBracketLogic.setsWon(outcome.oldSets)
                    let is3 = (w1 + w2) == 3
                    let p1 = ed.players.first(where: { $0.id == outcome.p1 })
                    let p2 = ed.players.first(where: { $0.id == outcome.p2 })
                    let p1Won = outcome.oldWin == outcome.p1
                    if let uid = p1?.playerUID {
                        self.adjustPlayerStats(uid: uid, won: p1Won, setsWon: w1, setsLost: w2, isSet3: is3, set3Won: is3 && p1Won, sign: -1)
                    }
                    if let uid = p2?.playerUID {
                        self.adjustPlayerStats(uid: uid, won: !p1Won, setsWon: w2, setsLost: w1, isSet3: is3, set3Won: is3 && !p1Won, sign: -1)
                    }
                    let wUID = p1Won ? p1?.playerUID : p2?.playerUID
                    let lUID = p1Won ? p2?.playerUID : p1?.playerUID
                    if let w = wUID, let l = lUID { self.adjustH2H(winnerUID: w, loserUID: l, sign: -1) }
                }
            }
        }
    }

    // MARK: - webPlayers stats & H2H (ports of updatePlayerAfterMatch / updateH2H)

    private func applyStatsUpdates(eventData: WebEventData, outcome: WebBracketLogic.ScoreOutcome, newSets: [WebSetScore]) {
        let p1 = eventData.players.first(where: { $0.id == outcome.p1 })
        let p2 = eventData.players.first(where: { $0.id == outcome.p2 })
        let (w1, w2) = WebBracketLogic.setsWon(newSets)
        let isSet3 = (w1 + w2) == 3
        let p1Won = outcome.winnerEntryId == outcome.p1

        if let oldWin = outcome.oldWin {
            let (ow1, ow2) = WebBracketLogic.setsWon(outcome.oldSets)
            let os3 = (ow1 + ow2) == 3
            let oldP1Won = oldWin == outcome.p1
            if let uid = p1?.playerUID {
                adjustPlayerStats(uid: uid, won: oldP1Won, setsWon: ow1, setsLost: ow2, isSet3: os3, set3Won: os3 && oldP1Won, sign: -1)
            }
            if let uid = p2?.playerUID {
                adjustPlayerStats(uid: uid, won: !oldP1Won, setsWon: ow2, setsLost: ow1, isSet3: os3, set3Won: os3 && !oldP1Won, sign: -1)
            }
            let owUID = oldP1Won ? p1?.playerUID : p2?.playerUID
            let olUID = oldP1Won ? p2?.playerUID : p1?.playerUID
            if let w = owUID, let l = olUID { adjustH2H(winnerUID: w, loserUID: l, sign: -1) }
        }

        if let uid = p1?.playerUID {
            adjustPlayerStats(uid: uid, won: p1Won, setsWon: w1, setsLost: w2, isSet3: isSet3, set3Won: isSet3 && p1Won, sign: 1)
        }
        if let uid = p2?.playerUID {
            adjustPlayerStats(uid: uid, won: !p1Won, setsWon: w2, setsLost: w1, isSet3: isSet3, set3Won: isSet3 && !p1Won, sign: 1)
        }
        let wUID = p1Won ? p1?.playerUID : p2?.playerUID
        let lUID = p1Won ? p2?.playerUID : p1?.playerUID
        if let w = wUID, let l = lUID { adjustH2H(winnerUID: w, loserUID: l, sign: 1) }
    }

    /// sign +1 applies a result, -1 undoes it (web's update/undoPlayerAfterMatch).
    private func adjustPlayerStats(uid: String, won: Bool, setsWon: Int, setsLost: Int, isSet3: Bool, set3Won: Bool, sign: Int) {
        let ref = db.collection("webPlayers").document(uid)
        ref.getDocument { snap, _ in
            guard let data = snap?.data() else { return }
            var s = data["stats"] as? [String: Any] ?? [:]
            func bump(_ key: String, _ delta: Int) {
                let cur = (s[key] as? NSNumber)?.intValue ?? 0
                s[key] = max(0, cur + delta * sign)
            }
            bump("matches", 1)
            if won { bump("wins", 1) }
            bump("setsWon", setsWon)
            bump("setsLost", setsLost)
            if isSet3 { bump("set3Apps", 1); if set3Won { bump("set3Wins", 1) } }
            let ratings = WebBracketLogic.computeRatings(stats: s)
            ref.updateData(["stats": s, "ratings": ratings, "updatedAt": Int(Date().timeIntervalSince1970 * 1000)]) { err in
                if let err = err { print("adjustPlayerStats(\(uid)) failed: \(err)") }
            }
        }
    }

    private func adjustH2H(winnerUID: String, loserUID: String, sign: Int) {
        let pCol = db.collection("webPlayers")
        pCol.document(winnerUID).getDocument { snap, _ in
            guard let data = snap?.data() else { return }
            var h2h = data["h2h"] as? [String: Any] ?? [:]
            var rec = h2h[loserUID] as? [String: Any] ?? ["wins": 0, "losses": 0]
            rec["wins"] = max(0, ((rec["wins"] as? NSNumber)?.intValue ?? 0) + sign)
            h2h[loserUID] = rec
            pCol.document(winnerUID).updateData(["h2h": h2h])
        }
        pCol.document(loserUID).getDocument { snap, _ in
            guard let data = snap?.data() else { return }
            var h2h = data["h2h"] as? [String: Any] ?? [:]
            var rec = h2h[winnerUID] as? [String: Any] ?? ["wins": 0, "losses": 0]
            rec["losses"] = max(0, ((rec["losses"] as? NSNumber)?.intValue ?? 0) + sign)
            h2h[winnerUID] = rec
            pCol.document(loserUID).updateData(["h2h": h2h])
        }
    }
}
