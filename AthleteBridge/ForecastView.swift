import SwiftUI

/// Which projection the forecaster shows: a coach's earnings or a client's spending.
enum ForecastMode {
    case coachEarnings
    case clientSpending

    var navigationTitle: String { self == .coachEarnings ? "Earnings Forecaster" : "Spending Forecaster" }
    var totalsHeader: String { self == .coachEarnings ? "Projected Earnings" : "Projected Spending" }
    var addSectionHeader: String { self == .coachEarnings ? "Add Manual Earning" : "Add Manual Spending" }
    var headerIcon: String { self == .coachEarnings ? "chart.line.uptrend.xyaxis" : "creditcard" }
}

/// Forecast of projected coaching earnings (coach) or spending (client),
/// grouped by month or week. Combines upcoming confirmed sessions at the
/// agreed rate with manual amounts entered for specific dates, optionally recurring.
struct ForecastView: View {
    let mode: ForecastMode

    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var manualEntries: [FirestoreManager.ManualEarningItem] = []
    @State private var isLoadingManual: Bool = true
    @State private var errorMessage: String? = nil

    // View granularity toggle
    private enum ForecastGranularity: String, CaseIterable, Identifiable {
        case monthly = "Monthly"
        case weekly = "Weekly"
        var id: String { rawValue }
    }
    @State private var granularity: ForecastGranularity = .monthly

    // Manual entry form state
    private enum Recurrence: String, CaseIterable, Identifiable {
        case none = "None"
        case weekly = "Weekly"
        case biweekly = "Every 2 Weeks"
        case monthly = "Monthly"
        var id: String { rawValue }
    }
    @State private var newAmountText: String = ""
    @State private var newDate: Date = Date()
    @State private var newNote: String = ""
    @State private var newRecurrence: Recurrence = .none
    @State private var recurrenceEndDate: Date = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
    @State private var isSavingEntry: Bool = false

    /// Periods (starting with the current one) always shown, even when empty.
    private let minimumMonthsShown = 6
    private let minimumWeeksShown = 8
    /// Safety cap on how many occurrences one recurring entry can create.
    private let maxRecurrenceOccurrences = 52

    // MARK: - Projection models

    private struct SessionProjection: Identifiable {
        let id: String
        let counterpartyName: String
        let date: Date
        let amount: Double
        let isGroup: Bool
    }

    private struct PeriodForecast: Identifiable {
        let periodStart: Date
        let sessions: [SessionProjection]
        let manual: [FirestoreManager.ManualEarningItem]
        var id: Date { periodStart }
        var sessionTotal: Double { sessions.reduce(0.0) { $0 + $1.amount } }
        var manualTotal: Double { manual.reduce(0.0) { $0 + $1.amount } }
        var total: Double { sessionTotal + manualTotal }
    }

    // MARK: - Projection logic

    /// Coach mode: bookings mirrored under the coach; client mode: the client's own bookings.
    private var relevantBookings: [FirestoreManager.BookingItem] {
        mode == .coachEarnings ? firestore.coachBookings : firestore.bookings
    }

    /// The amount this session is worth to the viewer. Coaches earn their own
    /// agreed rate (coachRates for group sessions, RateUSD otherwise); clients
    /// pay RateUSD, falling back to the sum of per-coach rates for group sessions.
    private func projectedAmount(for booking: FirestoreManager.BookingItem) -> Double {
        switch mode {
        case .coachEarnings:
            if let uid = auth.user?.uid, let rates = booking.coachRates, let rate = rates[uid] {
                return rate
            }
            return booking.RateUSD ?? 0.0
        case .clientSpending:
            if let rate = booking.RateUSD { return rate }
            if let rates = booking.coachRates, !rates.isEmpty { return rates.values.reduce(0, +) }
            return 0.0
        }
    }

    /// Who the session is with, from the viewer's perspective.
    private func counterpartyName(for booking: FirestoreManager.BookingItem, isGroup: Bool) -> String {
        if isGroup { return "Group Session" }
        switch mode {
        case .coachEarnings:
            return (booking.clientName?.isEmpty == false ? booking.clientName! : nil) ?? "Client"
        case .clientSpending:
            if let coach = firestore.coaches.first(where: { $0.id == booking.coachID }) {
                return coach.name
            }
            return (booking.coachName?.isEmpty == false ? booking.coachName! : nil) ?? "Coach"
        }
    }

    /// Upcoming confirmed sessions (today onward) mapped to projected amounts.
    private var upcomingSessions: [SessionProjection] {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        return relevantBookings.compactMap { b in
            guard (b.status ?? "").lowercased() == "confirmed",
                  let start = b.startAt, start >= startOfToday else { return nil }
            let isGroup = b.isGroupBooking == true || b.allCoachIDs.count > 1
            return SessionProjection(id: b.id,
                                     counterpartyName: counterpartyName(for: b, isGroup: isGroup),
                                     date: start,
                                     amount: projectedAmount(for: b),
                                     isGroup: isGroup)
        }
    }

    /// Manual entries from today onward (past entries are not part of the forecast).
    private var upcomingManual: [FirestoreManager.ManualEarningItem] {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        return manualEntries.filter { $0.date >= startOfToday }
    }

    /// Start of the month or week containing the date, depending on the toggle.
    private func periodStart(of date: Date) -> Date {
        let cal = Calendar.current
        switch granularity {
        case .monthly:
            return cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? date
        case .weekly:
            return cal.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        }
    }

    private func nextPeriod(after date: Date) -> Date? {
        let cal = Calendar.current
        switch granularity {
        case .monthly: return cal.date(byAdding: .month, value: 1, to: date)
        case .weekly: return cal.date(byAdding: .weekOfYear, value: 1, to: date)
        }
    }

    /// Sessions and manual entries grouped by period, current period first.
    /// Always includes a minimum number of periods plus any later period with data.
    private var periodForecasts: [PeriodForecast] {
        let currentPeriod = periodStart(of: Date())
        let minimumShown = granularity == .monthly ? minimumMonthsShown : minimumWeeksShown

        var periods: Set<Date> = []
        var cursor: Date? = currentPeriod
        for _ in 0..<minimumShown {
            guard let p = cursor else { break }
            periods.insert(p)
            cursor = nextPeriod(after: p)
        }
        for s in upcomingSessions { periods.insert(periodStart(of: s.date)) }
        for m in upcomingManual { periods.insert(periodStart(of: m.date)) }

        let sessionsByPeriod = Dictionary(grouping: upcomingSessions) { periodStart(of: $0.date) }
        let manualByPeriod = Dictionary(grouping: upcomingManual) { periodStart(of: $0.date) }

        return periods.sorted().map { p in
            PeriodForecast(periodStart: p,
                           sessions: (sessionsByPeriod[p] ?? []).sorted { $0.date < $1.date },
                           manual: (manualByPeriod[p] ?? []).sorted { $0.date < $1.date })
        }
    }

    private var projectedTotal: Double {
        periodForecasts.reduce(0.0) { $0 + $1.total }
    }

    /// Occurrence dates for the entry being added, honoring the recurrence choice.
    private func recurrenceDates() -> [Date] {
        var dates: [Date] = [newDate]
        guard newRecurrence != .none else { return dates }
        let cal = Calendar.current
        var current = newDate
        while dates.count < maxRecurrenceOccurrences {
            let next: Date?
            switch newRecurrence {
            case .weekly: next = cal.date(byAdding: .weekOfYear, value: 1, to: current)
            case .biweekly: next = cal.date(byAdding: .weekOfYear, value: 2, to: current)
            case .monthly: next = cal.date(byAdding: .month, value: 1, to: current)
            case .none: next = nil
            }
            guard let n = next, n <= recurrenceEndDate else { break }
            dates.append(n)
            current = n
        }
        return dates
    }

    // MARK: - Formatting

    private func formatUSD(_ amount: Double) -> String {
        if amount >= 1000 {
            return String(format: "$%.0f", amount)
        }
        return String(format: "$%.2f", amount)
    }

    private func periodTitle(_ date: Date) -> String {
        let f = DateFormatter()
        switch granularity {
        case .monthly:
            f.dateFormat = "MMMM yyyy"
            return f.string(from: date)
        case .weekly:
            f.dateFormat = "MMM d, yyyy"
            return "Week of \(f.string(from: date))"
        }
    }

    private func dayString(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
    }

    private var parsedNewAmount: Double? {
        let cleaned = newAmountText
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(cleaned), value > 0 else { return nil }
        return value
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("View", selection: $granularity) {
                        ForEach(ForecastGranularity.allCases) { g in
                            Text(g.rawValue).tag(g)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section(mode.totalsHeader) {
                    HStack {
                        Image(systemName: mode.headerIcon)
                            .foregroundColor(.accentColor)
                        Text("Total Projected")
                        Spacer()
                        Text(formatUSD(projectedTotal)).bold()
                    }
                    HStack {
                        Text("Scheduled Sessions")
                        Spacer()
                        Text("\(upcomingSessions.count)").foregroundColor(.secondary)
                    }
                }

                Section(mode.addSectionHeader) {
                    HStack {
                        Text("Amount")
                        Spacer()
                        TextField("$0.00", text: $newAmountText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                    }
                    DatePicker("Date", selection: $newDate, displayedComponents: [.date])
                        .onChange(of: newDate) { _, newStart in
                            if recurrenceEndDate < newStart { recurrenceEndDate = newStart }
                        }
                    Picker("Repeat", selection: $newRecurrence) {
                        ForEach(Recurrence.allCases) { r in
                            Text(r.rawValue).tag(r)
                        }
                    }
                    if newRecurrence != .none {
                        DatePicker("Until", selection: $recurrenceEndDate, in: newDate..., displayedComponents: [.date])
                    }
                    TextField("Note (optional)", text: $newNote)
                        .textInputAutocapitalization(.sentences)
                    Button(action: addManualEntry) {
                        if isSavingEntry {
                            ProgressView().progressViewStyle(.circular)
                        } else {
                            Text(newRecurrence == .none ? "Add to Forecast" : "Add \(recurrenceDates().count) Entries")
                                .bold()
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(parsedNewAmount == nil || isSavingEntry)
                }

                if let err = errorMessage {
                    Section {
                        Text(err).foregroundColor(.red).font(.footnote)
                    }
                }

                ForEach(periodForecasts) { period in
                    Section {
                        if period.sessions.isEmpty && period.manual.isEmpty {
                            Text(mode == .coachEarnings ? "No projected earnings yet." : "No projected spending yet.")
                                .foregroundColor(.secondary)
                                .font(.footnote)
                        }
                        ForEach(period.sessions) { s in
                            HStack {
                                Image(systemName: s.isGroup ? "person.3.fill" : "figure.run")
                                    .foregroundColor(.blue)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.counterpartyName)
                                    Text(dayString(s.date))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(formatUSD(s.amount)).foregroundColor(.secondary)
                            }
                        }
                        ForEach(period.manual) { m in
                            HStack {
                                Image(systemName: "pencil.circle.fill")
                                    .foregroundColor(.orange)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Text(m.note ?? "Manual entry")
                                        if m.recurrenceGroupId != nil {
                                            Image(systemName: "repeat")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    Text(dayString(m.date))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(formatUSD(m.amount)).foregroundColor(.secondary)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    deleteManualEntry(m)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                if let groupId = m.recurrenceGroupId {
                                    Button {
                                        deleteManualSeries(groupId)
                                    } label: {
                                        Label("Delete Series", systemImage: "repeat")
                                    }
                                    .tint(.orange)
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text(periodTitle(period.periodStart))
                            Spacer()
                            Text(formatUSD(period.total)).bold()
                        }
                    }
                }
            }
            .navigationTitle(mode.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay {
                if isLoadingManual {
                    ProgressView("Loading forecast…")
                }
            }
            .onAppear {
                switch mode {
                case .coachEarnings:
                    firestore.fetchBookingsForCurrentCoachSubcollection()
                case .clientSpending:
                    firestore.fetchBookingsForCurrentClientSubcollection()
                    firestore.fetchCoaches()
                }
                loadManualEntries()
            }
        }
    }

    // MARK: - Actions

    private func loadManualEntries() {
        isLoadingManual = true
        let handle: ([FirestoreManager.ManualEarningItem]) -> Void = { items in
            manualEntries = items
            isLoadingManual = false
        }
        switch mode {
        case .coachEarnings:
            FirestoreManager.shared.fetchManualEarningsForCurrentCoach(completion: handle)
        case .clientSpending:
            FirestoreManager.shared.fetchManualSpendingForCurrentClient(completion: handle)
        }
    }

    private func addManualEntry() {
        guard let amount = parsedNewAmount else { return }
        errorMessage = nil
        isSavingEntry = true
        let note = newNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteOrNil = note.isEmpty ? nil : note
        let dates = recurrenceDates()

        let finish: (Result<[FirestoreManager.ManualEarningItem], Error>) -> Void = { result in
            isSavingEntry = false
            switch result {
            case .success(let items):
                manualEntries.append(contentsOf: items)
                manualEntries.sort { $0.date < $1.date }
                newAmountText = ""
                newNote = ""
                newRecurrence = .none
            case .failure(let err):
                errorMessage = "Failed to save entry: \(err.localizedDescription)"
            }
        }
        let finishSingle: (Result<FirestoreManager.ManualEarningItem, Error>) -> Void = { result in
            finish(result.map { [$0] })
        }

        switch (mode, dates.count) {
        case (.coachEarnings, 1):
            FirestoreManager.shared.addManualEarningForCurrentCoach(amount: amount, date: newDate, note: noteOrNil, completion: finishSingle)
        case (.coachEarnings, _):
            FirestoreManager.shared.addManualEarningSeriesForCurrentCoach(amount: amount, dates: dates, note: noteOrNil, completion: finish)
        case (.clientSpending, 1):
            FirestoreManager.shared.addManualSpendingForCurrentClient(amount: amount, date: newDate, note: noteOrNil, completion: finishSingle)
        case (.clientSpending, _):
            FirestoreManager.shared.addManualSpendingSeriesForCurrentClient(amount: amount, dates: dates, note: noteOrNil, completion: finish)
        }
    }

    private func deleteManualEntry(_ item: FirestoreManager.ManualEarningItem) {
        errorMessage = nil
        // Optimistically remove, restore on failure
        let previous = manualEntries
        manualEntries.removeAll { $0.id == item.id }
        let handle: (Error?) -> Void = { err in
            if let err = err {
                manualEntries = previous
                errorMessage = "Failed to delete entry: \(err.localizedDescription)"
            }
        }
        switch mode {
        case .coachEarnings:
            FirestoreManager.shared.deleteManualEarningForCurrentCoach(id: item.id, completion: handle)
        case .clientSpending:
            FirestoreManager.shared.deleteManualSpendingForCurrentClient(id: item.id, completion: handle)
        }
    }

    private func deleteManualSeries(_ groupId: String) {
        errorMessage = nil
        // Optimistically remove, restore on failure
        let previous = manualEntries
        manualEntries.removeAll { $0.recurrenceGroupId == groupId }
        let handle: (Error?) -> Void = { err in
            if let err = err {
                manualEntries = previous
                errorMessage = "Failed to delete series: \(err.localizedDescription)"
            }
        }
        switch mode {
        case .coachEarnings:
            FirestoreManager.shared.deleteManualEarningSeriesForCurrentCoach(groupId: groupId, completion: handle)
        case .clientSpending:
            FirestoreManager.shared.deleteManualSpendingSeriesForCurrentClient(groupId: groupId, completion: handle)
        }
    }
}

struct ForecastView_Previews: PreviewProvider {
    static var previews: some View {
        ForecastView(mode: .coachEarnings)
            .environmentObject(FirestoreManager())
            .environmentObject(AuthViewModel())
    }
}
