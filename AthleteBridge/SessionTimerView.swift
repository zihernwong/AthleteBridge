import SwiftUI
import FirebaseAuth

// MARK: - Session Timer Model

/// Shared stopwatch state so the timer keeps running while the coach
/// navigates elsewhere in the app or backgrounds it. Elapsed time is
/// derived from wall-clock dates, never from UI ticks, so it stays
/// accurate no matter how long the view is off screen.
final class SessionTimerModel: ObservableObject {
    static let shared = SessionTimerModel()

    @Published var isRunning: Bool = false
    @Published var startedAt: Date? = nil
    @Published var accumulated: TimeInterval = 0
    /// Booking the timed result will be saved to.
    @Published var selectedBookingId: String? = nil
    /// Metric name the elapsed time is saved under (e.g. "1 mile sprint").
    @Published var metricName: String = "Session Time"

    func elapsed(now: Date = Date()) -> TimeInterval {
        accumulated + (isRunning ? now.timeIntervalSince(startedAt ?? now) : 0)
    }

    func start() {
        guard !isRunning else { return }
        startedAt = Date()
        isRunning = true
    }

    func pause() {
        guard isRunning else { return }
        accumulated = elapsed()
        startedAt = nil
        isRunning = false
    }

    func reset() {
        isRunning = false
        startedAt = nil
        accumulated = 0
    }
}

// MARK: - Session Timer View

/// Coach-only stopwatch. The coach picks one of their confirmed sessions,
/// names the metric being timed, and on save the elapsed time is written to
/// that booking's session log as a metric — so it shows up in the log and in
/// the per-exercise progress charts automatically.
struct SessionTimerView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel
    @ObservedObject private var timer = SessionTimerModel.shared

    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil
    @State private var savedMessage: String? = nil

    /// Confirmed sessions the timer can attach to: recent past week through
    /// the next two days, nearest to now first.
    private var eligibleBookings: [FirestoreManager.BookingItem] {
        let now = Date()
        let cal = Calendar.current
        guard let past = cal.date(byAdding: .day, value: -7, to: now),
              let future = cal.date(byAdding: .day, value: 2, to: now) else { return [] }
        return firestore.coachBookings
            .filter { b in
                guard (b.status ?? "").lowercased() == "confirmed", let s = b.startAt else { return false }
                return s >= past && s <= future
            }
            .sorted {
                abs(($0.startAt ?? now).timeIntervalSince(now)) < abs(($1.startAt ?? now).timeIntervalSince(now))
            }
    }

    private var selectedBooking: FirestoreManager.BookingItem? {
        eligibleBookings.first { $0.id == timer.selectedBookingId }
    }

    private func bookingLabel(_ b: FirestoreManager.BookingItem) -> String {
        let name = (b.clientName?.isEmpty == false ? b.clientName! : nil) ?? "Client"
        guard let start = b.startAt else { return name }
        return "\(name) — \(DateFormatter.localizedString(from: start, dateStyle: .medium, timeStyle: .short))"
    }

    /// "M:SS" under an hour, "H:MM:SS" above — the format the metric trend
    /// charts already know how to parse.
    private func formatElapsed(_ t: TimeInterval) -> String {
        let total = Int(t)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    var body: some View {
        Form {
            Section {
                if eligibleBookings.isEmpty {
                    Text("No confirmed sessions in the past week or next two days. The timer saves its result to a session's log, so confirm a booking first.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else {
                    Picker("Session", selection: $timer.selectedBookingId) {
                        ForEach(eligibleBookings, id: \.id) { b in
                            Text(bookingLabel(b)).tag(Optional(b.id))
                        }
                    }
                }
            } header: {
                Text("Save to")
            }

            Section {
                TextField("Metric name", text: $timer.metricName)
                    .textInputAutocapitalization(.sentences)
            } header: {
                Text("Timing what?")
            } footer: {
                Text("Use the same name each session (e.g. 1 mile sprint) to track progress over time. \"Session Time\" tracks the whole session.")
            }

            Section {
                VStack(spacing: 16) {
                    TimelineView(.periodic(from: .now, by: 0.5)) { context in
                        Text(formatElapsed(timer.elapsed(now: context.date)))
                            .font(.system(size: 56, weight: .semibold, design: .monospaced))
                            .frame(maxWidth: .infinity)
                    }

                    HStack(spacing: 12) {
                        Button {
                            if timer.isRunning { timer.pause() } else { timer.start() }
                        } label: {
                            Label(timer.isRunning ? "Pause" : (timer.elapsed() > 0 ? "Resume" : "Start"),
                                  systemImage: timer.isRunning ? "pause.fill" : "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(timer.isRunning ? .orange : .green)

                        Button {
                            timer.reset()
                            savedMessage = nil
                            errorMessage = nil
                        } label: {
                            Label("Reset", systemImage: "arrow.counterclockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(timer.elapsed() < 1 && !timer.isRunning)
                    }
                }
                .padding(.vertical, 8)
            }

            Section {
                Button(action: saveToSessionLog) {
                    if isSaving {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Label("Stop & Save to Session Log", systemImage: "square.and.arrow.down")
                            .bold()
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(isSaving || selectedBooking == nil || (timer.elapsed() < 1 && !timer.isRunning))
            } footer: {
                Text("Saves the elapsed time as a metric on the selected session's log.")
            }

            if let msg = savedMessage {
                Section {
                    Label(msg, systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundColor(.green)
                }
            }
            if let err = errorMessage {
                Section {
                    Text(err).foregroundColor(.red).font(.footnote)
                }
            }
        }
        .navigationTitle("Session Timer")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            firestore.fetchBookingsForCurrentCoachSubcollection()
            if let uid = auth.user?.uid { firestore.listenSessionLogsForCoach(coachId: uid) }
        }
        .onChange(of: firestore.coachBookings) { _, _ in
            ensureSelection()
        }
    }

    /// Keep a sensible default selection: the session happening right now if
    /// there is one, otherwise the nearest eligible session.
    private func ensureSelection() {
        let bookings = eligibleBookings
        if let current = timer.selectedBookingId, bookings.contains(where: { $0.id == current }) { return }
        let now = Date()
        let inProgress = bookings.first { b in
            guard let s = b.startAt else { return false }
            let e = b.endAt ?? s.addingTimeInterval(3600)
            return s <= now && now <= e
        }
        timer.selectedBookingId = (inProgress ?? bookings.first)?.id
    }

    private func saveToSessionLog() {
        guard let booking = selectedBooking else {
            errorMessage = "Select a session to save to."
            return
        }
        timer.pause()
        let elapsed = timer.elapsed()
        guard elapsed >= 1 else {
            errorMessage = "The timer hasn't run yet."
            return
        }
        let trimmedName = timer.metricName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmedName.isEmpty ? "Session Time" : trimmedName
        let value = formatElapsed(elapsed)

        isSaving = true
        errorMessage = nil
        savedMessage = nil
        firestore.appendMetricToSessionLog(
            booking: booking,
            coachName: firestore.currentCoach?.name ?? (booking.coachName ?? ""),
            metricName: name,
            value: value
        ) { err in
            isSaving = false
            if let err = err {
                errorMessage = "Failed to save: \(err.localizedDescription)"
            } else {
                let client = (booking.clientName?.isEmpty == false ? booking.clientName! : nil) ?? "the client"
                savedMessage = "Saved \(name) — \(value) to \(client)'s session log."
                firestore.showToast("Time saved to session log")
                timer.reset()
            }
        }
    }
}

struct SessionTimerView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            SessionTimerView()
                .environmentObject(FirestoreManager())
                .environmentObject(AuthViewModel())
        }
    }
}
