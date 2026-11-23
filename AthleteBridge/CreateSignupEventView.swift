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
    @State private var opensHoursBefore = 0
    @State private var customOpensAt = Date()
    @State private var notes = ""
    @State private var requireWaiver = false
    @State private var waiverText = SignupEvent.defaultWaiver(placeName: "")
    @State private var isSaving = false
    @State private var errorMessage: String?

    private static let customOpenTag = -1

    /// Default for a custom opening time: 8:30 PM the evening before the event
    private static func dayBeforeAt830(_ event: Date) -> Date {
        let cal = Calendar.current
        let dayBefore = cal.date(byAdding: .day, value: -1, to: event) ?? event
        return cal.date(bySettingHour: 20, minute: 30, second: 0, of: dayBefore) ?? dayBefore
    }

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
                Section(header: Text("Schedule"), footer: Text(repeatsWeekly
                    ? "Next week's event is created automatically once this one starts, with an empty signup list."
                    : "")) {
                    Toggle("Repeats Weekly", isOn: $repeatsWeekly)
                    Picker("Sign-ups Open", selection: $opensHoursBefore) {
                        Text("Right away").tag(0)
                        Text("1 day before").tag(24)
                        Text("2 days before").tag(48)
                        Text("3 days before").tag(72)
                        Text("1 week before").tag(168)
                        Text("Custom…").tag(Self.customOpenTag)
                    }
                    if opensHoursBefore == Self.customOpenTag {
                        DatePicker("Opens At", selection: $customOpensAt, in: ...eventDate)
                    }
                }
                .onChange(of: opensHoursBefore) { _, newValue in
                    if newValue == Self.customOpenTag { customOpensAt = Self.dayBeforeAt830(eventDate) }
                }
                Section(header: Text("Important Notes (optional)"), footer: Text("Rules players should read before signing up, e.g. check-in, court queue, what to bring.")) {
                    TextField("Each player must sign up individually…", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section(header: Text("Waiver")) {
                    Toggle("Require waiver to sign up", isOn: $requireWaiver)
                    if requireWaiver {
                        TextField("Waiver text", text: $waiverText, axis: .vertical)
                            .lineLimit(3...8)
                    }
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
            .onAppear {
                waiverText = SignupEvent.defaultWaiver(placeName: place.name)
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
                                allowSelfReportPaid: allowSelfReport,
                                opensHoursBefore: opensHoursBefore == Self.customOpenTag ? nil : opensHoursBefore,
                                opensAt: opensHoursBefore == Self.customOpenTag ? customOpensAt : nil,
                                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                                waiverText: requireWaiver ? waiverText.trimmingCharacters(in: .whitespacesAndNewlines) : nil
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
