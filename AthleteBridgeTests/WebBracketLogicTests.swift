import XCTest
@testable import AthleteBridge

/// Score entry and bracket advancement for the web tournament manager (WebBracketLogic is a port of
/// public/tournament/index.html, so a failure here likely exists on the web too).
final class WebBracketLogicTests: XCTestCase {

    private func match(_ id: String, round: Int, _ p1: String?, _ p2: String?, next: String? = nil, slot: String? = nil,
                       loseNext: String? = nil, loseSlot: String? = nil, bracket: String = "W") -> WebMatch {
        WebMatch(id: id, round: round, pos: 0, p1: p1, p2: p2, sets: [.empty, .empty, .empty], win: nil, bye: false,
                 next: next, slot: slot, loseNext: loseNext, loseSlot: loseSlot, bracket: bracket, court: nil, scheduledTime: nil)
    }

    private func sets(_ games: (Int, Int)...) -> [WebSetScore] {
        games.map { WebSetScore(s1: $0.0, s2: $0.1) } + Array(repeating: .empty, count: max(0, 3 - games.count))
    }

    private func players(_ ids: String...) -> [WebPlayerEntry] {
        ids.enumerated().map { WebPlayerEntry(id: $0.element, name: "Player \($0.element)", seed: $0.offset + 1, playerUID: nil) }
    }

    /// Four-player single elimination: A–B and C–D semifinals feed the final.
    private func fourPlayerKnockout() -> WebEventData {
        WebEventData(players: players("A", "B", "C", "D"),
                     bracket: WebBracket(matches: [
                        match("sf1", round: 1, "A", "B", next: "f", slot: "p1"),
                        match("sf2", round: 1, "C", "D", next: "f", slot: "p2"),
                        match("f", round: 2, nil, nil)
                     ], rounds: 2, fmt: "SE"),
                     status: "active", champion: nil, rawWaitlist: [])
    }

    private func m(_ ed: WebEventData, _ id: String) -> WebMatch { ed.bracket!.matches.first { $0.id == id }! }

    private func playOutKnockout() -> WebEventData {
        var ed = fourPlayerKnockout()
        XCTAssertNotNil(WebBracketLogic.applyScore(eventData: &ed, matchId: "sf1", sets: sets((21, 10), (21, 12))))
        XCTAssertNotNil(WebBracketLogic.applyScore(eventData: &ed, matchId: "sf2", sets: sets((21, 15), (21, 18))))
        XCTAssertNotNil(WebBracketLogic.applyScore(eventData: &ed, matchId: "f", sets: sets((21, 19), (19, 21), (21, 17))))
        return ed
    }

    func testBestOfThreeNeedsTwoSets() {
        XCTAssertEqual(WebBracketLogic.matchWinner(sets: sets((21, 10), (21, 12)), p1: "A", p2: "B"), "A")
        XCTAssertEqual(WebBracketLogic.matchWinner(sets: sets((21, 10), (10, 21), (15, 21)), p1: "A", p2: "B"), "B")
        XCTAssertNil(WebBracketLogic.matchWinner(sets: sets((21, 10), (10, 21)), p1: "A", p2: "B"))
        XCTAssertNil(WebBracketLogic.matchWinner(sets: sets((21, 21), (21, 10)), p1: "A", p2: "B"), "tied sets don't count")
        var ed = fourPlayerKnockout()
        XCTAssertNil(WebBracketLogic.applyScore(eventData: &ed, matchId: "sf1", sets: sets((21, 10))), "an undecided score is rejected")
        XCTAssertNil(WebBracketLogic.applyScore(eventData: &ed, matchId: "f", sets: sets((21, 10), (21, 10))), "the final has no players yet")
    }

    func testWinnersAdvanceAndTheFinalCrownsTheChampion() {
        var ed = fourPlayerKnockout()
        _ = WebBracketLogic.applyScore(eventData: &ed, matchId: "sf1", sets: sets((21, 10), (21, 12)))
        XCTAssertEqual(m(ed, "f").p1, "A")
        XCTAssertEqual(ed.status, "active")
        ed = playOutKnockout()
        XCTAssertEqual(m(ed, "f").p2, "C")
        XCTAssertEqual(m(ed, "f").win, "A")
        XCTAssertEqual(ed.status, "complete")
        XCTAssertEqual(ed.champion, "A")
        XCTAssertEqual(WebBracketLogic.roundLabel(match: m(ed, "f"), bracket: ed.bracket!), "Final")
        XCTAssertEqual(WebBracketLogic.roundLabel(match: m(ed, "sf1"), bracket: ed.bracket!), "Semifinal")
        XCTAssertEqual(WebBracketLogic.setsDisplay(m(ed, "f")), "21–19, 19–21, 21–17")
    }

    func testCorrectingAScoreWithTheSameWinnerKeepsLaterResults() {
        var ed = playOutKnockout()
        // The organizer fixes a typo in A's semifinal — A still won.
        XCTAssertNotNil(WebBracketLogic.applyScore(eventData: &ed, matchId: "sf1", sets: sets((21, 19), (21, 17))))
        XCTAssertEqual(m(ed, "f").win, "A", "fixing a semifinal score erased the final's result")
        XCTAssertEqual(m(ed, "f").sets, sets((21, 19), (19, 21), (21, 17)))
    }

    func testChangingAnEarlierWinnerReopensACompletedEvent() {
        var ed = playOutKnockout()
        // B actually won the semifinal, so the final has to be replayed.
        XCTAssertNotNil(WebBracketLogic.applyScore(eventData: &ed, matchId: "sf1", sets: sets((19, 21), (18, 21))))
        XCTAssertEqual(m(ed, "f").p1, "B")
        XCTAssertNil(m(ed, "f").win)
        XCTAssertEqual(ed.status, "active", "the event still says complete with no final result")
        XCTAssertNil(ed.champion, "A is still listed as champion")
    }

    func testClearingAScoreUndoesItsAdvancement() {
        var ed = playOutKnockout()
        let cleared = WebBracketLogic.clearScore(eventData: &ed, matchId: "sf2")
        XCTAssertEqual(cleared?.oldWin, "C")
        XCTAssertNil(m(ed, "sf2").win)
        XCTAssertNil(m(ed, "f").p2)
        XCTAssertNil(m(ed, "f").win)
        XCTAssertEqual(ed.status, "active")
        XCTAssertNil(ed.champion)
    }

    func testDoubleEliminationSendsLosersToTheLosersBracket() {
        var ed = WebEventData(players: players("A", "B", "C"),
                              bracket: WebBracket(matches: [
                                match("w1", round: 1, "A", "B", next: "gf", slot: "p1", loseNext: "l1", loseSlot: "p1"),
                                match("l1", round: 1, nil, "C", next: "gf", slot: "p2", bracket: "L"),
                                match("gf", round: 2, nil, nil, bracket: "GF")
                              ], rounds: 2, fmt: "DE"),
                              status: "active", champion: nil, rawWaitlist: [])
        _ = WebBracketLogic.applyScore(eventData: &ed, matchId: "w1", sets: sets((21, 10), (21, 10)))
        XCTAssertEqual(m(ed, "gf").p1, "A")
        XCTAssertEqual(m(ed, "l1").p1, "B")
        // Rescored: B won — both slots swap
        _ = WebBracketLogic.applyScore(eventData: &ed, matchId: "w1", sets: sets((10, 21), (10, 21)))
        XCTAssertEqual(m(ed, "gf").p1, "B")
        XCTAssertEqual(m(ed, "l1").p1, "A")
        _ = WebBracketLogic.applyScore(eventData: &ed, matchId: "l1", sets: sets((21, 15), (21, 15)))
        _ = WebBracketLogic.applyScore(eventData: &ed, matchId: "gf", sets: sets((15, 21), (15, 21)))
        XCTAssertEqual(ed.champion, "A")
        XCTAssertEqual(WebBracketLogic.roundLabel(match: m(ed, "gf"), bracket: ed.bracket!), "Grand Final")
    }

    func testRoundRobinStandings() {
        var ed = WebEventData(players: players("A", "B", "C"),
                              bracket: WebBracket(matches: [
                                match("r1", round: 1, "A", "B", bracket: "RR"),
                                match("r2", round: 2, "A", "C", bracket: "RR"),
                                match("r3", round: 3, "B", "C", bracket: "RR")
                              ], rounds: 3, fmt: "RR"),
                              status: "active", champion: nil, rawWaitlist: [])
        _ = WebBracketLogic.applyScore(eventData: &ed, matchId: "r1", sets: sets((21, 10), (21, 10)))
        _ = WebBracketLogic.applyScore(eventData: &ed, matchId: "r2", sets: sets((21, 10), (10, 21), (21, 10)))
        XCTAssertEqual(ed.status, "active")
        _ = WebBracketLogic.applyScore(eventData: &ed, matchId: "r3", sets: sets((21, 10), (21, 10)))
        let stats = WebBracketLogic.rrStats(players: ed.players, matches: ed.bracket!.matches)
        XCTAssertEqual(stats["A"]?.pts, 4)
        XCTAssertEqual(stats["A"]?.sw, 4)
        XCTAssertEqual(stats["A"]?.sl, 1)
        XCTAssertEqual(stats["C"]?.l, 2)
        XCTAssertEqual(ed.status, "complete")
        XCTAssertEqual(ed.champion, "A")
        XCTAssertEqual(WebBracketLogic.overallStatus(events: ["mens_doubles", "mixed_doubles"],
                                                     eventData: ["mens_doubles": ed, "mixed_doubles": .empty]), "active")
    }

    func testPlayerRatings() {
        XCTAssertEqual(WebBracketLogic.computeRatings(stats: ["matches": 2, "wins": 2])["overall"], 5.0, "neutral until 3 matches")
        let r = WebBracketLogic.computeRatings(stats: [
            "matches": 10, "wins": 7, "set3Apps": 4, "set3Wins": 3, "setsWon": 15, "setsLost": 6,
            "tournaments": 2, "titles": 1, "finals": 1, "semis": 0
        ])
        XCTAssertEqual(r["winRate"], 7.0)
        XCTAssertEqual(r["clutch"], 7.5)
        XCTAssertEqual(r["dominance"], 7.1)
        XCTAssertEqual(r["tournament"], 8.8)
        XCTAssertEqual(r["overall"], 7.4)
    }

    func testParsingTheWebDocument() {
        let doc: [String: Any] = [
            "name": "Fall Open", "date": "2026-11-28", "format": "SE", "status": "completed", "numCourts": "3",
            "events": ["mens_doubles"],
            "eventData": ["mens_doubles": [
                "players": [["id": "A", "name": "Alex", "seed": 1], ["id": "B", "name": "Blake", "seed": "2"]],
                "bracket": ["rounds": 1, "fmt": "SE", "matches": [["id": "f", "round": 1, "p1": "A", "p2": "B",
                                                                 "sets": [["s1": 21, "s2": 15]]]]],
                "status": "active"
            ]]
        ]
        let t = WebTournament.parse(id: "w1", data: doc)
        XCTAssertTrue(t.isComplete, "legacy 'completed' status")
        XCTAssertEqual(t.numCourts, 3)
        let ed = t.eventData(for: "mens_doubles")
        XCTAssertEqual(ed.players.map(\.seed), [1, 2])
        XCTAssertEqual(ed.playerName("B"), "Blake")
        XCTAssertEqual(ed.bracket?.matches.first?.sets.count, 3, "sets are padded to best-of-three")
        XCTAssertEqual(WebTournamentEvents.displayName("mens_doubles"), "Men's Doubles")
        XCTAssertEqual(WebTournamentEvents.displayName("open_singles"), "Open Singles")
        XCTAssertEqual(t.webURL?.absoluteString, "https://athletesbridge.com/tournament/?id=w1")
    }
}
