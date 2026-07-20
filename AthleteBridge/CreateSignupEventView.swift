import SwiftUI

struct CreateSignupEventView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @Environment(\.dismiss) private var dismiss
    let place: PlaceToPlay
    @State private var title = ""
    @State private var description = ""
    @State private var eventDate = Date()
    @State private var maxSignups = 10
    @State private var repeatsWeekly = false
    @State private var feeText = ""
    @State private var paymentLink = ""
    @State private var allowSelfReport = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var feeUSD: Double? {
        Double(feeText.replacingOccurrences(of: "$", with: "").trimmingCharacters(in: .whitespaces))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Event Details")) {
                    TextField("Event Title", text: $title)
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                    DatePicker("Date & Time", selection: $eventDate, in: Date()...)
                }
                Section(header: Text("Venue")) {
                    HStack {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundColor(Color("LogoGreen"))
                        Text(place.name)
                    }
                    if !place.address.isEmpty {
                        Text(place.address)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Section(header: Text("Capacity")) {
                    Stepper("Max Signups: \(maxSignups)", value: $maxSignups, in: 2...500)
                }
                Section(header: Text("Schedule")) {
                    Toggle("Repeats Weekly", isOn: $repeatsWeekly)
                }
                Section(header: Text("Payment (optional)"), footer: Text("Players see the fee and a payment button on the signup page. You can mark who has paid on the event screen.")) {
                    HStack {
                        Text("$")
                            .foregroundColor(.secondary)
                        TextField("Fee per player, e.g. 8", text: $feeText)
                            .keyboardType(.decimalPad)
                    }
                    TextField("Payment link or @venmo-handle", text: $paymentLink)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    Toggle("Players can mark themselves paid", isOn: $allowSelfReport)
                }
            }
            .navigationTitle("New Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Create") {
                            isSaving = true
                            firestore.createSignupEvent(
                                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                                eventDate: eventDate,
                                location: place.address,
                                placeId: place.id,
                                placeName: place.name,
                                maxSignups: maxSignups,
                                recurrence: repeatsWeekly ? "weekly" : nil,
                                feeUSD: feeUSD,
                                paymentLink: paymentLink.trimmingCharacters(in: .whitespacesAndNewlines),
                                allowSelfReportPaid: allowSelfReport
                            ) { err in
                                DispatchQueue.main.async {
                                    isSaving = false
                                    if let err = err {
                                        errorMessage = err.localizedDescription
                                    } else {
                                        dismiss()
                                    }
                                }
                            }
                        }
                        .disabled(!isValid)
                    }
                }
            }
            .alert("Failed to Create Event", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }
}
