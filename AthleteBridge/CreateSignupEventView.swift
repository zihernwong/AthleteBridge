import SwiftUI

struct CreateSignupEventView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @Environment(\.dismiss) private var dismiss
    let place: PlaceToPlay
    @State private var title = ""
    @State private var description = ""
    @State private var eventDate = Date()
    @State private var maxSignups = 10
    @State private var isSaving = false

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
            }
            .navigationTitle("New Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        isSaving = true
                        firestore.createSignupEvent(
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                            eventDate: eventDate,
                            location: place.address,
                            placeId: place.id,
                            placeName: place.name,
                            maxSignups: maxSignups
                        ) { err in
                            DispatchQueue.main.async {
                                isSaving = false
                                if err == nil {
                                    dismiss()
                                }
                            }
                        }
                    }
                    .disabled(!isValid || isSaving)
                }
            }
        }
    }
}
