import SwiftUI

/// Native bracket / results view for a linked web tournament. Read-only for
/// everyone; tournament organizers can tap a match to enter scores.
struct WebBracketView: View {
    @ObservedObject var store: WebTournamentStore
    let isOrganizer: Bool

    @State private var selectedEvent: String? = nil
    @State private var scoreContext: ScoreContext? = nil
    @State private var errorMessage: String? = nil
    @State private var showError = false

    struct ScoreContext: Identifiable {
        let id: String
        let match: WebMatch
        let event: String?
        let p1Name: String
        let p2Name: String
        let roundLabel: String
    }

    private var currentEvent: String? {
        guard let wt = store.webTournament, !wt.events.isEmpty else { return nil }
        return selectedEvent ?? wt.events.first
    }

    var body: some View {
        Group {
            if let wt = store.webTournament {
                content(wt)
            } else {
                ProgressView("Loading tournament…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Bracket & Results")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $scoreContext) { ctx in
            ScoreEntrySheet(store: store, context: ctx, webId: store.webTournament?.id ?? "")
        }
        .alert(errorMessage ?? "Something went wrong", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func content(_ wt: WebTournament) -> some View {
        let ed = wt.eventData(for: currentEvent)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !wt.events.isEmpty {
                    eventPills(wt)
                }
                statusHeader(ed)
                if let bracket = ed.bracket {
                    if bracket.fmt == "RR" {
                        rrStandings(ed: ed, bracket: bracket)
                        rrMatchList(ed: ed, bracket: bracket)
                    } else {
                        bracketColumns(ed: ed, bracket: bracket)
                    }
                } else {
                    noBracketYet(wt)
                }
            }
            .padding()
        }
    }

    private func eventPills(_ wt: WebTournament) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(wt.events, id: \.self) { ev in
                    let isSel = ev == currentEvent
                    Button(action: { selectedEvent = ev }) {
                        Text(WebTournamentEvents.displayName(ev))
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(isSel ? Color("LogoBlue") : Color(UIColor.secondarySystemBackground))
                            .foregroundColor(isSel ? .white : .primary)
                            .cornerRadius(16)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }

    private func statusHeader(_ ed: WebEventData) -> some View {
        HStack(spacing: 8) {
            Text(ed.status == "complete" ? "Complete" : ed.status == "active" ? "Live" : "Setup")
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(statusColor(ed.status).opacity(0.15))
                .foregroundColor(statusColor(ed.status))
                .cornerRadius(10)
            if ed.status == "complete", let champ = ed.playerName(ed.champion) {
                Label(champ, systemImage: "crown.fill")
                    .font(.subheadline)
                    .foregroundColor(.orange)
            }
            Spacer()
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "complete": return Color("LogoGreen")
        case "active": return .red
        default: return .secondary
        }
    }

    private func noBracketYet(_ wt: WebTournament) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "square.grid.3x1.below.line.grid.1x2")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text("No bracket yet")
                .font(.headline)
            Text("Players and draws are set up in the web tournament manager.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            if let url = wt.webURL {
                Link("Open Tournament Manager", destination: url)
                    .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Elimination brackets

    private func bracketColumns(ed: WebEventData, bracket: WebBracket) -> some View {
        let columns = Self.columns(for: bracket)
        return ScrollView(.horizontal, showsIndicators: true) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(columns, id: \.title) { column in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(column.title)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                        ForEach(column.matches) { m in
                            matchCard(m, ed: ed, bracket: bracket)
                        }
                    }
                    .frame(width: 210)
                }
            }
            .padding(.vertical, 4)
        }
    }

    struct BracketColumn {
        let title: String
        let matches: [WebMatch]
    }

    static func columns(for bracket: WebBracket) -> [BracketColumn] {
        var cols: [BracketColumn] = []
        let w = bracket.matches.filter { $0.bracket == "W" }
        let wRounds = Set(w.map { $0.round }).sorted()
        for r in wRounds {
            let title: String
            if bracket.fmt == "SE" {
                title = r == bracket.rounds ? "Final" : r == bracket.rounds - 1 ? "Semifinals" : "Round \(r)"
            } else {
                title = "Winners R\(r)"
            }
            cols.append(BracketColumn(title: title, matches: w.filter { $0.round == r }.sorted { $0.pos < $1.pos }))
        }
        let l = bracket.matches.filter { $0.bracket == "L" }
        let lRounds = Set(l.map { $0.round }).sorted()
        for r in lRounds {
            cols.append(BracketColumn(title: "Losers R\(r)", matches: l.filter { $0.round == r }.sorted { $0.pos < $1.pos }))
        }
        let gf = bracket.matches.filter { $0.bracket == "GF" }
        if !gf.isEmpty {
            cols.append(BracketColumn(title: "Grand Final", matches: gf))
        }
        return cols
    }

    private func matchCard(_ m: WebMatch, ed: WebEventData, bracket: WebBracket) -> some View {
        let p1Name = ed.playerName(m.p1)
        let p2Name = ed.playerName(m.p2)
        let (w1, w2) = WebBracketLogic.setsWon(m.sets)
        return Button(action: {
            guard isOrganizer, let p1 = p1Name, let p2 = p2Name else { return }
            scoreContext = ScoreContext(
                id: m.id,
                match: m,
                event: currentEvent,
                p1Name: p1,
                p2Name: p2,
                roundLabel: WebBracketLogic.roundLabel(match: m, bracket: bracket)
            )
        }) {
            VStack(spacing: 0) {
                matchRow(name: p1Name, isBye: m.bye && m.p1 == nil, isWinner: m.win != nil && m.win == m.p1, setsWon: m.win != nil ? w1 : nil)
                Divider()
                matchRow(name: p2Name, isBye: m.bye && m.p2 == nil, isWinner: m.win != nil && m.win == m.p2, setsWon: m.win != nil ? w2 : nil)
                if m.win != nil {
                    Text(WebBracketLogic.setsDisplay(m))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 6)
                } else if let court = m.court {
                    Text("Court \(court)\(m.scheduledTime.map { " · \($0)" } ?? "")")
                        .font(.caption2)
                        .foregroundColor(Color("LogoBlue"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 6)
                }
            }
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(10)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func matchRow(name: String?, isBye: Bool, isWinner: Bool, setsWon: Int?) -> some View {
        HStack {
            Text(name ?? (isBye ? "BYE" : "TBD"))
                .font(.subheadline)
                .fontWeight(isWinner ? .semibold : .regular)
                .foregroundColor(name == nil ? .secondary : (isWinner ? Color("LogoGreen") : .primary))
                .lineLimit(1)
            Spacer()
            if let s = setsWon {
                Text("\(s)")
                    .font(.subheadline)
                    .fontWeight(isWinner ? .bold : .regular)
                    .foregroundColor(isWinner ? Color("LogoGreen") : .secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    // MARK: - Round robin

    private func rrStandings(ed: WebEventData, bracket: WebBracket) -> some View {
        let stats = WebBracketLogic.rrStats(players: ed.players, matches: bracket.matches)
        let ranked = ed.players.sorted { a, b in
            let sa = stats[a.id] ?? .init(), sb = stats[b.id] ?? .init()
            if sa.pts != sb.pts { return sa.pts > sb.pts }
            return (sa.sw - sa.sl) > (sb.sw - sb.sl)
        }
        return VStack(alignment: .leading, spacing: 6) {
            Text("Standings")
                .font(.headline)
            ForEach(Array(ranked.enumerated()), id: \.element.id) { index, p in
                let s = stats[p.id] ?? .init()
                HStack {
                    Text("\(index + 1)")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .frame(width: 24, alignment: .leading)
                    if index == 0 && ed.status == "complete" {
                        Image(systemName: "crown.fill").font(.caption).foregroundColor(.orange)
                    }
                    Text(p.name)
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer()
                    Text("\(s.w)–\(s.l)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(s.pts) pts")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .frame(width: 44, alignment: .trailing)
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 10)
                .background(index == 0 && ed.status == "complete" ? Color("LogoGreen").opacity(0.1) : Color(UIColor.secondarySystemBackground))
                .cornerRadius(8)
            }
        }
    }

    private func rrMatchList(ed: WebEventData, bracket: WebBracket) -> some View {
        let rounds = Set(bracket.matches.map { $0.round }).sorted()
        return VStack(alignment: .leading, spacing: 10) {
            Text("Matches")
                .font(.headline)
            ForEach(rounds, id: \.self) { r in
                Text("Round \(r)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                ForEach(bracket.matches.filter { $0.round == r }) { m in
                    matchCard(m, ed: ed, bracket: bracket)
                }
            }
        }
    }
}

// MARK: - Score entry sheet

private struct ScoreEntrySheet: View {
    @ObservedObject var store: WebTournamentStore
    let context: WebBracketView.ScoreContext
    let webId: String
    @Environment(\.dismiss) private var dismiss

    @State private var scores: [[String]] = [["", ""], ["", ""], ["", ""]]
    @State private var errorText: String? = nil

    private var enteredSets: [WebSetScore] {
        scores.map { WebSetScore(s1: Int($0[0]), s2: Int($0[1])) }
    }

    private var verdict: String {
        let sets = enteredSets
        let (w1, w2) = WebBracketLogic.setsWon(sets)
        if let winner = WebBracketLogic.matchWinner(sets: sets, p1: context.match.p1, p2: context.match.p2) {
            let name = winner == context.match.p1 ? context.p1Name : context.p2Name
            return "🏆 \(name) wins \(max(w1, w2))–\(min(w1, w2)) in sets"
        }
        if w1 > 0 || w2 > 0 {
            return "\(w1)–\(w2) in sets — \(w1 == 1 && w2 == 1 ? "play set 3" : "enter more scores")"
        }
        return "Best of 3 sets to 21"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(context.roundLabel)) {
                    HStack {
                        Text(context.p1Name).font(.headline)
                        Spacer()
                        Text("vs").foregroundColor(.secondary)
                        Spacer()
                        Text(context.p2Name).font(.headline)
                    }
                }
                Section {
                    ForEach(0..<3, id: \.self) { i in
                        HStack(spacing: 12) {
                            Text("Set \(i + 1)")
                                .frame(width: 50, alignment: .leading)
                                .foregroundColor(.secondary)
                            TextField("0", text: $scores[i][0])
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.center)
                                .textFieldStyle(.roundedBorder)
                            Text("–").foregroundColor(.secondary)
                            TextField("0", text: $scores[i][1])
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.center)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    Text(verdict)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                if let errorText = errorText {
                    Section {
                        Text(errorText).foregroundColor(.red)
                    }
                }
                if context.match.win != nil {
                    Section {
                        Button("Clear Result", role: .destructive) {
                            store.clearScore(webId: webId, event: context.event, matchId: context.match.id) { err in
                                if let err = err { errorText = err } else { dismiss() }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Enter Score")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.submitScore(webId: webId, event: context.event, matchId: context.match.id, sets: enteredSets) { err in
                            if let err = err { errorText = err } else { dismiss() }
                        }
                    }
                    .disabled(store.isWorking || WebBracketLogic.matchWinner(sets: enteredSets, p1: context.match.p1, p2: context.match.p2) == nil)
                }
            }
            .onAppear {
                for (i, s) in context.match.sets.prefix(3).enumerated() {
                    scores[i][0] = s.s1.map(String.init) ?? ""
                    scores[i][1] = s.s2.map(String.init) ?? ""
                }
            }
        }
    }
}
