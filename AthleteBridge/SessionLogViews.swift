import SwiftUI
import FirebaseAuth

// MARK: - Session Log Editor
// Coach fills this in after every completed session: what was worked on, what
// needs improvement, what improved, plus optional named metrics (e.g.
// "1 mile sprint" -> "8:00"). When a metric name matches one logged before for
// this client, the previous value is shown so progress is visible while typing.

struct SessionLogEditorView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @Environment(\.dismiss) private var dismiss

    let booking: FirestoreManager.BookingItem

    @State private var workedOn: String = ""
    @State private var toImprove: String = ""
    @State private var improved: String = ""
    @State private var metrics: [FirestoreManager.SessionMetric] = [FirestoreManager.SessionMetric(name: "", value: "")]
    @State private var isSaving = false
    @State private var errorMessage: String? = nil
    @State private var didPrefill = false

    /// Called after a successful save (used by the pending-logs flow).
    var onSaved: (() -> Void)? = nil

    private var isValid: Bool {
        !workedOn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !toImprove.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !improved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Most recent previous value per metric name for this coach-client pair.
    private var previousMetricValues: [String: (value: String, date: Date?)] {
        var result: [String: (value: String, date: Date?)] = [:]
        let pastLogs = firestore.coachSessionLogs
            .filter { $0.clientID == booking.clientID && $0.id != booking.id }
            .sorted { ($0.sessionDate ?? .distantPast) > ($1.sessionDate ?? .distantPast) }
        for log in pastLogs {
            for metric in log.metrics {
                let key = metric.name.lowercased()
                if result[key] == nil {
                    result[key] = (metric.value, log.sessionDate)
                }
            }
        }
        return result
    }

    var body: some View {
        Form {
            Section {
                if let start = booking.startAt {
                    HStack {
                        Text("Session").foregroundColor(.secondary)
                        Spacer()
                        Text(DateFormatter.localizedString(from: start, dateStyle: .medium, timeStyle: .short))
                    }
                }
                HStack {
                    Text("Client").foregroundColor(.secondary)
                    Spacer()
                    Text(booking.clientName ?? "Client")
                }
            }

            Section(header: Text("What was worked on today?")) {
                TextEditor(text: $workedOn).frame(minHeight: 70)
            }
            Section(header: Text("What needs to be improved?")) {
                TextEditor(text: $toImprove).frame(minHeight: 70)
            }
            Section(header: Text("What improved?")) {
                TextEditor(text: $improved).frame(minHeight: 70)
            }

            Section {
                ForEach($metrics) { $metric in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            TextField("Exercise (e.g. 1 mile sprint)", text: $metric.name)
                            Divider()
                            TextField("Result (e.g. 8:00)", text: $metric.value)
                                .frame(maxWidth: 120)
                        }
                        // Show the previous result for this exercise so the
                        // coach can see the improvement while logging
                        let key = metric.name.trimmingCharacters(in: .whitespaces).lowercased()
                        if !key.isEmpty, let prev = previousMetricValues[key] {
                            HStack(spacing: 4) {
                                Image(systemName: "clock.arrow.circlepath")
                                Text("Last time: \(prev.value)\(prev.date.map { " (\(DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .none)))" } ?? "")")
                            }
                            .font(.caption)
                            .foregroundColor(Color("LogoBlue"))
                        }
                    }
                }
                .onDelete { metrics.remove(atOffsets: $0) }

                Button {
                    metrics.append(FirestoreManager.SessionMetric(name: "", value: ""))
                } label: {
                    Label("Add Metric", systemImage: "plus.circle")
                        .font(.subheadline)
                }
            } header: {
                Text("Metrics (optional)")
            } footer: {
                Text("Use the same exercise name each session to track progress over time.")
            }

            if let err = errorMessage {
                Section { Text(err).foregroundColor(.red).font(.caption) }
            }
        }
        .navigationTitle("Session Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(action: save) {
                    if isSaving { ProgressView() } else { Text("Save") }
                }
                .disabled(!isValid || isSaving)
            }
        }
        .onAppear {
            guard !didPrefill else { return }
            didPrefill = true
            // Editing an existing log: prefill from it
            if let existing = firestore.coachSessionLogs.first(where: { $0.id == booking.id }) {
                workedOn = existing.workedOn
                toImprove = existing.toImprove
                improved = existing.improved
                if !existing.metrics.isEmpty { metrics = existing.metrics }
            }
        }
    }

    private func save() {
        guard let coachId = Auth.auth().currentUser?.uid else {
            errorMessage = "Not authenticated"
            return
        }
        isSaving = true
        errorMessage = nil
        firestore.saveSessionLog(
            bookingId: booking.id,
            coachId: coachId,
            clientId: booking.clientID,
            coachName: firestore.currentCoach?.name ?? (booking.coachName ?? ""),
            clientName: booking.clientName ?? "",
            sessionDate: booking.startAt,
            workedOn: workedOn,
            toImprove: toImprove,
            improved: improved,
            metrics: metrics
        ) { err in
            DispatchQueue.main.async {
                isSaving = false
                if let err = err {
                    errorMessage = err.localizedDescription
                } else {
                    firestore.showToast("Session log saved")
                    onSaved?()
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Pending Session Logs (shown to the coach after sessions end)

struct PendingSessionLogsView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @Environment(\.dismiss) private var dismiss

    private var pending: [FirestoreManager.BookingItem] {
        guard let uid = Auth.auth().currentUser?.uid else { return [] }
        return firestore.pendingSessionLogs(coachId: uid)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Log each completed session so you and your client can track progress.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                ForEach(pending) { booking in
                    NavigationLink {
                        SessionLogEditorView(booking: booking)
                            .environmentObject(firestore)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(booking.clientName ?? "Client")
                                .font(.headline)
                            if let start = booking.startAt {
                                Text(DateFormatter.localizedString(from: start, dateStyle: .medium, timeStyle: .short))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Sessions to Log (\(pending.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Later") { dismiss() }
                }
            }
            .onChange(of: pending.count) { _, newCount in
                // All caught up — close automatically
                if newCount == 0 { dismiss() }
            }
        }
        .interactiveDismissDisabled()
    }
}

// MARK: - Session Log Card (shared display)

struct SessionLogCard: View {
    let log: FirestoreManager.SessionLog

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let date = log.sessionDate {
                Text(DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(Color("LogoGreen"))
            }
            logField(title: "Worked on", text: log.workedOn)
            logField(title: "Needs improvement", text: log.toImprove)
            logField(title: "Improved", text: log.improved)
            if !log.metrics.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Metrics")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    ForEach(log.metrics) { metric in
                        HStack {
                            Text(metric.name).font(.caption)
                            Spacer()
                            Text(metric.value).font(.caption).fontWeight(.semibold)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func logField(title: String, text: String) -> some View {
        if !text.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(text)
                    .font(.subheadline)
            }
        }
    }
}

// MARK: - Metric Progress (grouped across sessions)

struct MetricProgressSection: View {
    let logs: [FirestoreManager.SessionLog]

    /// Metric history grouped by exercise name, oldest -> newest.
    private var groupedMetrics: [(name: String, entries: [(date: Date?, value: String)])] {
        var groups: [String: (display: String, entries: [(Date?, String)])] = [:]
        for log in logs.sorted(by: { ($0.sessionDate ?? .distantPast) < ($1.sessionDate ?? .distantPast) }) {
            for metric in log.metrics {
                let key = metric.name.lowercased()
                var group = groups[key] ?? (display: metric.name, entries: [])
                group.entries.append((log.sessionDate, metric.value))
                groups[key] = group
            }
        }
        return groups.values
            .map { (name: $0.display, entries: $0.entries) }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    var body: some View {
        if !groupedMetrics.isEmpty {
            Section(header: Text("Metric Progress")) {
                ForEach(groupedMetrics, id: \.name) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.name)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        // e.g. 8:00 → 7:45 → 7:30
                        Text(group.entries.map { $0.value }.joined(separator: " → "))
                            .font(.subheadline)
                            .foregroundColor(Color("LogoGreen"))
                        if let firstDate = group.entries.first?.date, let lastDate = group.entries.last?.date, group.entries.count > 1 {
                            Text("\(DateFormatter.localizedString(from: firstDate, dateStyle: .short, timeStyle: .none)) – \(DateFormatter.localizedString(from: lastDate, dateStyle: .short, timeStyle: .none))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}
