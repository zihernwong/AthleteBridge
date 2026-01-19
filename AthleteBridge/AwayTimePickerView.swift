import SwiftUI
import FirebaseFirestore

struct AwayTimePickerView: View {
    let coach: Coach
    @EnvironmentObject var auth: AuthViewModel

    @State private var startAt: Date = Date()
    @State private var endAt: Date = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil
    @Environment(\.dismiss) private var dismiss

    private var isValidRange: Bool {
        return endAt > startAt
    }

    var body: some View {
        Form {
            Section(header: Text("Select Time Away")) {
                DatePicker("Start", selection: $startAt, displayedComponents: [.date, .hourAndMinute])
                DatePicker("End", selection: $endAt, in: startAt...Date.distantFuture, displayedComponents: [.date, .hourAndMinute])
            }

            if let err = errorMessage {
                Text(err).foregroundColor(.red)
            }

            Section {
                Button(action: saveAwayTime) {
                    if isSaving { ProgressView() }
                    Text(isSaving ? "Saving…" : "Block Time")
                        .bold()
                        .frame(maxWidth: .infinity)
                }
                .disabled(!isValidRange || isSaving)
            }
        }
        .navigationTitle("Input Time Away")
    }

    private func saveAwayTime() {
        errorMessage = nil
        guard auth.user?.uid == coach.id else {
            errorMessage = "You must be the coach to enter away time."
            return
        }
        guard isValidRange else {
            errorMessage = "End must be after start."
            return
        }
        isSaving = true
        let db = Firestore.firestore()
        let coll = db.collection("coaches").document(coach.id).collection("awayTimes")
        let payload: [String: Any] = [
            "startAt": Timestamp(date: startAt),
            "endAt": Timestamp(date: endAt),
            "createdAt": Timestamp(date: Date()),
            "createdBy": auth.user?.uid ?? coach.id
        ]
        coll.addDocument(data: payload) { err in
            DispatchQueue.main.async {
                isSaving = false
                if let err = err {
                    errorMessage = "Failed to save: \(err.localizedDescription)"
                } else {
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
    }
}
