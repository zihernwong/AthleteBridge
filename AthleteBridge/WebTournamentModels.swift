import Foundation

// Models for the web tournament manager's Firestore collections
// (webTournaments / webPlayers), mirroring public/tournament/index.html.
// The score/advancement logic here is a direct port of the web JS — keep the
// two in sync if the web manager's rules change.

enum WebTournamentEvents {
    static let displayNames: [String: String] = [
        "mens_singles": "Men's Singles",
        "womens_singles": "Women's Singles",
        "mens_doubles": "Men's Doubles",
        "womens_doubles": "Women's Doubles",
        "mixed_doubles": "Mixed Doubles",
        "senior_mens_singles": "Senior Men's Singles",
        "senior_womens_singles": "Senior Women's Singles",
        "senior_mens_doubles": "Senior Men's Doubles",
        "senior_womens_doubles": "Senior Women's Doubles",
        "senior_mixed_doubles": "Senior Mixed Doubles",
        "junior_boys_singles": "Junior Boys' Singles",
        "junior_girls_singles": "Junior Girls' Singles",
        "junior_boys_doubles": "Junior Boys' Doubles",
        "junior_girls_doubles": "Junior Girls' Doubles",
        "junior_mixed_doubles": "Junior Mixed Doubles",
    ]

    static func displayName(_ key: String) -> String {
        displayNames[key] ?? key.replacingOccurrences(of: "_", with: " ").capitalized
    }

    /// App-side participant event names → web event keys (for create-from-app).
    static let appEventKeys: [String: String] = [
        "Men's Doubles": "mens_doubles",
        "Women's Doubles": "womens_doubles",
        "Mixed Doubles": "mixed_doubles",
    ]
}

struct WebSetScore: Hashable {
    var s1: Int?
    var s2: Int?

    static let empty = WebSetScore(s1: nil, s2: nil)

    static func parse(_ raw: Any?) -> WebSetScore {
        guard let dict = raw as? [String: Any] else { return .empty }
        return WebSetScore(s1: intOrNil(dict["s1"]), s2: intOrNil(dict["s2"]))
    }

    var firestoreValue: [String: Any] {
        ["s1": s1 as Any? ?? NSNull(), "s2": s2 as Any? ?? NSNull()]
    }
}

struct WebMatch: Identifiable, Hashable {
    let id: String
    var round: Int
    var pos: Int
    var p1: String?
    var p2: String?
    var sets: [WebSetScore]
    var win: String?
    var bye: Bool
    var next: String?
    var slot: String?
    var loseNext: String?
    var loseSlot: String?
    var bracket: String   // "W" | "L" | "GF" | "RR"
    var court: Int?
    var scheduledTime: String?

    static func parse(_ raw: Any?) -> WebMatch? {
        guard let d = raw as? [String: Any], let id = d["id"] as? String else { return nil }
        var sets = (d["sets"] as? [Any] ?? []).map { WebSetScore.parse($0) }
        while sets.count < 3 { sets.append(.empty) }
        return WebMatch(
            id: id,
            round: intOrNil(d["round"]) ?? 1,
            pos: intOrNil(d["pos"]) ?? 0,
            p1: d["p1"] as? String,
            p2: d["p2"] as? String,
            sets: sets,
            win: d["win"] as? String,
            bye: d["bye"] as? Bool ?? false,
            next: d["next"] as? String,
            slot: d["slot"] as? String,
            loseNext: d["loseNext"] as? String,
            loseSlot: d["loseSlot"] as? String,
            bracket: d["bracket"] as? String ?? "W",
            court: intOrNil(d["court"]),
            scheduledTime: d["scheduledTime"] as? String
        )
    }

    var firestoreValue: [String: Any] {
        [
            "id": id,
            "round": round,
            "pos": pos,
            "p1": p1 as Any? ?? NSNull(),
            "p2": p2 as Any? ?? NSNull(),
            "sets": sets.map { $0.firestoreValue },
            "win": win as Any? ?? NSNull(),
            "bye": bye,
            "next": next as Any? ?? NSNull(),
            "slot": slot as Any? ?? NSNull(),
            "loseNext": loseNext as Any? ?? NSNull(),
            "loseSlot": loseSlot as Any? ?? NSNull(),
            "bracket": bracket,
            "court": court as Any? ?? NSNull(),
            "scheduledTime": scheduledTime as Any? ?? NSNull(),
        ]
    }
}

struct WebPlayerEntry: Identifiable, Hashable {
    let id: String
    var name: String
    var seed: Int
    var playerUID: String?

    static func parse(_ raw: Any?) -> WebPlayerEntry? {
        guard let d = raw as? [String: Any], let id = d["id"] as? String else { return nil }
        return WebPlayerEntry(id: id, name: d["name"] as? String ?? "?", seed: intOrNil(d["seed"]) ?? 0, playerUID: d["playerUID"] as? String)
    }
}

struct WebBracket: Hashable {
    var matches: [WebMatch]
    var rounds: Int
    var fmt: String   // "SE" | "DE" | "RR"

    static func parse(_ raw: Any?) -> WebBracket? {
        guard let d = raw as? [String: Any] else { return nil }
        let matches = (d["matches"] as? [Any] ?? []).compactMap { WebMatch.parse($0) }
        return WebBracket(matches: matches, rounds: intOrNil(d["rounds"]) ?? 1, fmt: d["fmt"] as? String ?? "SE")
    }

    var firestoreValue: [String: Any] {
        ["matches": matches.map { $0.firestoreValue }, "rounds": rounds, "fmt": fmt]
    }
}

struct WebEventData: Hashable {
    var players: [WebPlayerEntry]
    var bracket: WebBracket?
    var status: String        // "setup" | "active" | "complete"
    var champion: String?     // player entry id

    // Raw fields we don't model (waitlist etc.) preserved for write-back
    var rawWaitlist: [[String: String]]

    static let empty = WebEventData(players: [], bracket: nil, status: "setup", champion: nil, rawWaitlist: [])

    static func parse(_ raw: Any?) -> WebEventData {
        guard let d = raw as? [String: Any] else { return .empty }
        let players = (d["players"] as? [Any] ?? []).compactMap { WebPlayerEntry.parse($0) }
        var waitlist: [[String: String]] = []
        for w in (d["waitlist"] as? [Any] ?? []) {
            if let wd = w as? [String: Any] {
                var entry: [String: String] = [:]
                for (k, v) in wd { entry[k] = "\(v)" }
                waitlist.append(entry)
            }
        }
        return WebEventData(
            players: players,
            bracket: WebBracket.parse(d["bracket"]),
            status: d["status"] as? String ?? "setup",
            champion: d["champion"] as? String,
            rawWaitlist: waitlist
        )
    }

    var firestoreValue: [String: Any] {
        [
            "players": players.map { p -> [String: Any] in
                var v: [String: Any] = ["id": p.id, "name": p.name, "seed": p.seed]
                if let uid = p.playerUID { v["playerUID"] = uid }
                return v
            },
            "bracket": bracket?.firestoreValue as Any? ?? NSNull(),
            "status": status,
            "champion": champion as Any? ?? NSNull(),
            "waitlist": rawWaitlist,
        ]
    }

    func playerName(_ entryId: String?) -> String? {
        guard let entryId = entryId else { return nil }
        return players.first(where: { $0.id == entryId })?.name
    }
}

struct WebTournament: Identifiable, Hashable {
    let id: String
    var name: String
    var date: String          // "yyyy-MM-dd"
    var startTime: String
    var location: String
    var sport: String
    var format: String        // "SE" | "DE" | "RR"
    var status: String        // "setup" | "active" | "complete" (legacy: "completed")
    var numCourts: Int
    var events: [String]      // event keys; empty = legacy single-event at root
    var eventData: [String: WebEventData]
    var createdBy: String?

    /// Legacy docs keep players/bracket at the root instead of eventData.
    var legacyRoot: WebEventData?

    static func parse(id: String, data: [String: Any]) -> WebTournament {
        let events = data["events"] as? [String] ?? []
        var eventData: [String: WebEventData] = [:]
        if let edRaw = data["eventData"] as? [String: Any] {
            for (key, value) in edRaw { eventData[key] = WebEventData.parse(value) }
        }
        var legacy: WebEventData? = nil
        if events.isEmpty {
            legacy = WebEventData.parse(data)
        }
        return WebTournament(
            id: id,
            name: data["name"] as? String ?? "",
            date: data["date"] as? String ?? "",
            startTime: data["startTime"] as? String ?? "",
            location: data["location"] as? String ?? "",
            sport: data["sport"] as? String ?? "",
            format: data["format"] as? String ?? "SE",
            status: data["status"] as? String ?? "setup",
            numCourts: intOrNil(data["numCourts"]) ?? 1,
            events: events,
            eventData: eventData,
            createdBy: data["createdBy"] as? String,
            legacyRoot: legacy
        )
    }

    func eventData(for event: String?) -> WebEventData {
        if let event = event, !events.isEmpty {
            return eventData[event] ?? .empty
        }
        return legacyRoot ?? .empty
    }

    var isComplete: Bool { status == "complete" || status == "completed" }

    var parsedDate: Date? {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone.current
        return df.date(from: date)
    }

    static let managerBaseURL = "https://athletebridge-63176.web.app/tournament/"

    var webURL: URL? { URL(string: "\(Self.managerBaseURL)?id=\(id)") }
    var registerURL: URL? { URL(string: "\(Self.managerBaseURL)?id=\(id)&register=1") }
}

// MARK: - Score / bracket logic (port of the web manager's JS)

enum WebBracketLogic {

    static func setsWon(_ sets: [WebSetScore]) -> (w1: Int, w2: Int) {
        var w1 = 0, w2 = 0
        for s in sets {
            guard let a = s.s1, let b = s.s2, a != b else { continue }
            if a > b { w1 += 1 } else { w2 += 1 }
        }
        return (w1, w2)
    }

    static func matchWinner(sets: [WebSetScore], p1: String?, p2: String?) -> String? {
        let (w1, w2) = setsWon(sets)
        if w1 >= 2 { return p1 }
        if w2 >= 2 { return p2 }
        return nil
    }

    static func setsDisplay(_ m: WebMatch) -> String {
        m.sets.compactMap { s -> String? in
            guard let a = s.s1, let b = s.s2 else { return nil }
            return "\(a)–\(b)"
        }.joined(separator: ", ")
    }

    static func roundLabel(match: WebMatch, bracket: WebBracket) -> String {
        switch bracket.fmt {
        case "SE":
            if match.round == bracket.rounds { return "Final" }
            if match.round == bracket.rounds - 1 { return "Semifinal" }
            return "Round \(match.round)"
        case "DE":
            if match.bracket == "GF" { return "Grand Final" }
            return match.bracket == "W" ? "Winners R\(match.round)" : "Losers R\(match.round)"
        default:
            return "Round \(match.round)"
        }
    }

    /// Propagate a result: winner into next match's slot, loser into loseNext.
    private static func doProp(_ ms: inout [WebMatch], _ i: Int, winner: String, loser: String?) {
        let m = ms[i]
        if let next = m.next, let slot = m.slot, let ni = ms.firstIndex(where: { $0.id == next }) {
            if slot == "p1" { ms[ni].p1 = winner } else { ms[ni].p2 = winner }
        }
        if let loseNext = m.loseNext, let loseSlot = m.loseSlot, let loser = loser,
           let li = ms.firstIndex(where: { $0.id == loseNext }) {
            if loseSlot == "p1" { ms[li].p1 = loser } else { ms[li].p2 = loser }
        }
    }

    /// Recursively unwind a previous result before overwriting it.
    private static func undoProp(_ ms: inout [WebMatch], _ i: Int) {
        let m = ms[i]
        guard let win = m.win else { return }
        if let next = m.next, let slot = m.slot, let ni = ms.firstIndex(where: { $0.id == next }) {
            let occupant = slot == "p1" ? ms[ni].p1 : ms[ni].p2
            if occupant == win {
                if ms[ni].win != nil { undoProp(&ms, ni) }
                if slot == "p1" { ms[ni].p1 = nil } else { ms[ni].p2 = nil }
                ms[ni].sets = [.empty, .empty, .empty]
                ms[ni].win = nil
            }
        }
        if let loseNext = m.loseNext, let loseSlot = m.loseSlot,
           let li = ms.firstIndex(where: { $0.id == loseNext }) {
            let loser = win == m.p1 ? m.p2 : m.p1
            let occupant = loseSlot == "p1" ? ms[li].p1 : ms[li].p2
            if occupant == loser, loser != nil {
                if ms[li].win != nil { undoProp(&ms, li) }
                if loseSlot == "p1" { ms[li].p1 = nil } else { ms[li].p2 = nil }
                ms[li].sets = [.empty, .empty, .empty]
                ms[li].win = nil
            }
        }
    }

    /// Give the freed court to the next ready, unscheduled match.
    private static func scheduleNextMatch(_ ms: inout [WebMatch], freedCourt: Int) {
        guard let i = ms.firstIndex(where: { $0.p1 != nil && $0.p2 != nil && !$0.bye && $0.win == nil && $0.court == nil }) else { return }
        ms[i].court = freedCourt
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        ms[i].scheduledTime = df.string(from: Date())
    }

    struct ScoreOutcome {
        let winnerEntryId: String
        let loserEntryId: String?
        let oldWin: String?
        let oldSets: [WebSetScore]
        let p1: String?
        let p2: String?
    }

    /// Mirror of the web's saveScore mutation. Returns nil if the sets don't
    /// determine a 2-set winner.
    static func applyScore(eventData: inout WebEventData, matchId: String, sets: [WebSetScore]) -> ScoreOutcome? {
        guard var bracket = eventData.bracket,
              let mi = bracket.matches.firstIndex(where: { $0.id == matchId }) else { return nil }
        let m = bracket.matches[mi]
        guard let winner = matchWinner(sets: sets, p1: m.p1, p2: m.p2) else { return nil }

        let oldWin = m.win
        let oldSets = m.sets
        var ms = bracket.matches
        if ms[mi].win != nil { undoProp(&ms, mi) }
        ms[mi].sets = sets
        ms[mi].win = winner
        let loser = winner == m.p1 ? m.p2 : m.p1
        doProp(&ms, mi, winner: winner, loser: loser)
        if let freedCourt = ms[mi].court {
            scheduleNextMatch(&ms, freedCourt: freedCourt)
        }
        bracket.matches = ms
        eventData.bracket = bracket
        checkDone(&eventData)
        return ScoreOutcome(winnerEntryId: winner, loserEntryId: loser, oldWin: oldWin, oldSets: oldSets, p1: m.p1, p2: m.p2)
    }

    struct ClearOutcome {
        let oldWin: String
        let oldSets: [WebSetScore]
        let p1: String?
        let p2: String?
    }

    /// Mirror of the web's clearScore mutation.
    static func clearScore(eventData: inout WebEventData, matchId: String) -> ClearOutcome? {
        guard var bracket = eventData.bracket,
              let mi = bracket.matches.firstIndex(where: { $0.id == matchId }) else { return nil }
        let m = bracket.matches[mi]
        let outcome = m.win.map { ClearOutcome(oldWin: $0, oldSets: m.sets, p1: m.p1, p2: m.p2) }
        var ms = bracket.matches
        undoProp(&ms, mi)
        ms[mi].sets = [.empty, .empty, .empty]
        ms[mi].win = nil
        for i in ms.indices where ms[i].id != matchId {
            if ms[i].court != nil && (ms[i].p1 == nil || ms[i].p2 == nil) {
                ms[i].court = nil
                ms[i].scheduledTime = nil
            }
        }
        bracket.matches = ms
        eventData.bracket = bracket
        eventData.status = "active"
        eventData.champion = nil
        return outcome
    }

    /// If every real match has a result, mark the event complete and crown a champion.
    static func checkDone(_ eventData: inout WebEventData) {
        guard let bracket = eventData.bracket else { return }
        let real = bracket.matches.filter { !$0.bye && $0.p1 != nil && $0.p2 != nil }
        guard !real.isEmpty, real.allSatisfy({ $0.win != nil }) else { return }
        eventData.status = "complete"
        if bracket.fmt == "RR" {
            let stats = rrStats(players: eventData.players, matches: bracket.matches)
            eventData.champion = eventData.players.sorted {
                (stats[$0.id]?.pts ?? 0) > (stats[$1.id]?.pts ?? 0)
            }.first?.id
        } else {
            let last = (bracket.matches.filter { $0.bracket == "GF" }
                        + bracket.matches.filter { $0.bracket != "GF" && $0.bracket != "L" })
                .sorted { a, b in
                    let ra = a.bracket == "GF" ? 1_000_000 : a.round
                    let rb = b.bracket == "GF" ? 1_000_000 : b.round
                    return ra > rb
                }.first
            eventData.champion = last?.win
        }
    }

    /// Recompute the tournament-level status the way the web's saveED does.
    static func overallStatus(events: [String], eventData: [String: WebEventData]) -> String {
        let statuses = events.map { eventData[$0]?.status ?? "setup" }
        if !statuses.isEmpty && statuses.allSatisfy({ $0 == "complete" }) { return "complete" }
        if statuses.contains(where: { $0 == "active" || $0 == "complete" }) { return "active" }
        return "setup"
    }

    struct RRStat {
        var w = 0, l = 0, pts = 0, sw = 0, sl = 0
    }

    static func rrStats(players: [WebPlayerEntry], matches: [WebMatch]) -> [String: RRStat] {
        var stats: [String: RRStat] = [:]
        for p in players { stats[p.id] = RRStat() }
        for m in matches {
            guard let win = m.win else { continue }
            let lid = m.p1 == win ? m.p2 : m.p1
            if stats[win] != nil { stats[win]!.w += 1; stats[win]!.pts += 2 }
            if let lid = lid, stats[lid] != nil { stats[lid]!.l += 1 }
            let (w1, w2) = setsWon(m.sets)
            if let p1 = m.p1, stats[p1] != nil { stats[p1]!.sw += w1; stats[p1]!.sl += w2 }
            if let p2 = m.p2, stats[p2] != nil { stats[p2]!.sw += w2; stats[p2]!.sl += w1 }
        }
        return stats
    }

    /// Port of the web's computeRatings for webPlayers stat updates.
    static func computeRatings(stats: [String: Any]) -> [String: Double] {
        let m = doubleOr(stats["matches"], 0)
        let neutral: [String: Double] = ["overall": 5.0, "winRate": 5.0, "clutch": 5.0, "dominance": 5.0, "tournament": 5.0]
        guard m >= 3 else { return neutral }
        func r(_ v: Double) -> Double { (min(10, max(0, v)) * 10).rounded() / 10 }
        let winRate = doubleOr(stats["wins"], 0) / m * 10
        let set3Apps = doubleOr(stats["set3Apps"], 0)
        let clutch = set3Apps > 0 ? doubleOr(stats["set3Wins"], 0) / set3Apps * 10 : 5
        let totalSets = doubleOr(stats["setsWon"], 0) + doubleOr(stats["setsLost"], 0)
        let dominance = totalSets > 0 ? doubleOr(stats["setsWon"], 0) / totalSets * 10 : 5
        let t = max(1, doubleOr(stats["tournaments"], 0))
        let perfPts = doubleOr(stats["titles"], 0) * 3 + doubleOr(stats["finals"], 0) * 2 + doubleOr(stats["semis"], 0)
        let tournament = min(10, perfPts / t * 3.5)
        let overall = winRate * 0.35 + clutch * 0.20 + dominance * 0.30 + tournament * 0.15
        return ["overall": r(overall), "winRate": r(winRate), "clutch": r(clutch), "dominance": r(dominance), "tournament": r(tournament)]
    }

    private static func doubleOr(_ v: Any?, _ fallback: Double) -> Double {
        (v as? NSNumber)?.doubleValue ?? fallback
    }
}

private func intOrNil(_ v: Any?) -> Int? {
    if let n = v as? NSNumber { return n.intValue }
    if let s = v as? String { return Int(s) }
    return nil
}
