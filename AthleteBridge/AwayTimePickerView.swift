import SwiftUI
import FirebaseFirestore

struct AwayTimePickerView: View {
    let coach: Coach
    @EnvironmentObject var auth: AuthViewModel
    @EnvironmentObject var firestore: FirestoreManager

    // Round up to the next 30-minute boundary safely
    private static func nearest30Up(from date: Date) -> Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let minute = comps.minute ?? 0
        let remainder = minute % 30
        if remainder == 0 {
            comps.second = 0
            return cal.date(from: comps) ?? date
        }
        var newMinute = minute + (30 - remainder)
        var newHour = comps.hour ?? 0
        var year = comps.year ?? 0
        var month = comps.month ?? 0
        var day = comps.day ?? 0
        if newMinute >= 60 {
            newMinute -= 60
            newHour += 1
            if newHour >= 24 {
                newHour = 0
                // advance day safely
                if let advanced = cal.date(byAdding: .day, value: 1, to: cal.date(from: comps) ?? date) {
                    let advComps = cal.dateComponents([.year, .month, .day], from: advanced)
                    year = advComps.year ?? year
                    month = advComps.month ?? month
                    day = advComps.day ?? day
                }
            }
        }
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = newHour
        comps.minute = newMinute
        comps.second = 0
        return cal.date(from: comps) ?? date
    }

    @State private var startAt: Date = AwayTimePickerView.nearest30Up(from: Date())
    @State private var endAt: Date = Calendar.current.date(byAdding: .minute, value: 30, to: AwayTimePickerView.nearest30Up(from: Date())) ?? Date()
    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil
    @State private var reason: String = ""
    @Environment(\.dismiss) private var dismiss

    private var isValidRange: Bool { endAt > startAt }
    private var isReasonProvided: Bool { !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    // Snap to the nearest lower 30-min mark (picker changes), but keep consistency
    private func snappedTo30Floor(_ date: Date) -> Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let minute = comps.minute ?? 0
        let snappedMinute = (minute / 30) * 30
        comps.minute = snappedMinute
        comps.second = 0
        return cal.date(from: comps) ?? date
    }

    var body: some View {
        Form {
            Section(header: Text("Select Time Away")) {
                DatePicker("Start", selection: $startAt, displayedComponents: [.date, .hourAndMinute])
                DatePicker("End", selection: $endAt, in: startAt...Date.distantFuture, displayedComponents: [.date, .hourAndMinute])
                TextField("Reason", text: $reason)
                    .textInputAutocapitalization(.sentences)
                if reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Reason is required").font(.caption).foregroundColor(.red)
                }
            }

            if let err = errorMessage { Text(err).foregroundColor(.red) }

            Section {
                Button(action: saveAwayTime) {
                    if isSaving { ProgressView() }
                    Text(isSaving ? "Saving…" : "Block Time").bold().frame(maxWidth: .infinity)
                }
                .disabled(!isValidRange || !isReasonProvided || isSaving)
            }
        }
        .navigationTitle("Input Time Away")
        .onChange(of: startAt) { _old, newVal in
            let snapped = snappedTo30Floor(newVal)
            if snapped != newVal { startAt = snapped }
            if endAt <= startAt { endAt = Calendar.current.date(byAdding: .minute, value: 30, to: startAt) ?? startAt }
        }
        .onChange(of: endAt) { _old, newVal in
            let snapped = snappedTo30Floor(newVal)
            if snapped != newVal { endAt = snapped }
            if endAt <= startAt { endAt = Calendar.current.date(byAdding: .minute, value: 30, to: startAt) ?? startAt }
        }
    }

    private func saveAwayTime() {
        errorMessage = nil
        // Round start to next 30 up to satisfy request for default behavior alignment
        startAt = AwayTimePickerView.nearest30Up(from: startAt)
        endAt = AwayTimePickerView.nearest30Up(from: endAt)
        guard auth.user?.uid == coach.id else { errorMessage = "You must be the coach to enter away time."; return }
        guard isValidRange else { errorMessage = "End must be after start."; return }
        isSaving = true
        let db = Firestore.firestore()
        let coll = db.collection("coaches").document(coach.id).collection("awayTimes")
        var payload: [String: Any] = [
            "startAt": Timestamp(date: startAt),
            "endAt": Timestamp(date: endAt),
            "createdAt": Timestamp(date: Date()),
            "createdBy": auth.user?.uid ?? coach.id
        ]
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        payload["notes"] = trimmed
        coll.addDocument(data: payload) { [self] err in
            DispatchQueue.main.async {
                isSaving = false
                if let err = err {
                    errorMessage = "Failed to save: \(err.localizedDescription)"
                } else {
                    // Add to Apple Calendar if enabled
                    if firestore.autoAddToCalendar {
                        let title = "Time Away - \(trimmed)"
                        firestore.addBookingToAppleCalendar(
                            title: title,
                            start: startAt,
                            end: endAt,
                            location: nil,
                            notes: trimmed,
                            bookingId: "away-\(coach.id)-\(Int(startAt.timeIntervalSince1970))"
                        ) { res in
                            switch res {
                            case .success(let eventId):
                                print("Added time away to calendar: \(eventId)")
                            case .failure(let err):
                                print("Failed to add time away to calendar: \(err)")
                            }
                        }
                    }
                    dismiss()
                }
            }
        }
    }
}

struct AwayTimePickerView_Previews: PreviewProvider {
    static var previews: some View {
        AwayTimePickerView(coach: Coach(id: "demo", name: "Demo Coach", specialties: [], experienceYears: 1, availability: []))
            .environmentObject(AuthViewModel())
            .environmentObject(FirestoreManager())
    }
}
