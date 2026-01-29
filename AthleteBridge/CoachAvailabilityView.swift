import SwiftUI
import FirebaseAuth

struct CoachAvailabilityView: View {
    let coach: Coach
    @EnvironmentObject var firestore: FirestoreManager
    @State private var bookings: [FirestoreManager.BookingItem] = []
    @State private var loading: Bool = true
    @State private var selectedAvailability: Set<String> = []

    private let availabilityOptions = ["Morning", "Afternoon", "Evening"]

    private var isOwnProfile: Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        return coach.id == uid
    }

    var body: some View {
        List {
            if isOwnProfile {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Update your availability")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        AvailabilityChipSelect(items: availabilityOptions, selection: $selectedAvailability)
                    }
                    .padding(.vertical, 8)
                }
            }

            Section(header: Text("Bookings")) {
                if loading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if bookings.isEmpty {
                    Text("No bookings found").foregroundColor(.secondary)
                } else {
                    ForEach(bookings) { b in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(b.clientName ?? b.clientID)
                                    .font(.headline)
                                Spacer()
                                if let status = b.status { Text(status.capitalized).font(.caption).foregroundColor(.secondary) }
                            }
                            if let start = b.startAt, let end = b.endAt {
                                Text("\(DateFormatter.localizedString(from: start, dateStyle: .medium, timeStyle: .short)) — \(DateFormatter.localizedString(from: end, dateStyle: .medium, timeStyle: .short))")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            } else if let start = b.startAt {
                                Text(DateFormatter.localizedString(from: start, dateStyle: .medium, timeStyle: .short)).font(.subheadline).foregroundColor(.secondary)
                            }
                            if let loc = b.location, !loc.isEmpty { Text(loc).font(.caption).foregroundColor(.secondary) }
                            if let notes = b.notes, !notes.isEmpty { Text(notes).font(.caption2).foregroundColor(.secondary) }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
        .navigationTitle("Availability")
        .onAppear {
            selectedAvailability = Set(coach.availability)
            loading = true
            firestore.fetchBookingsForCoach(coachId: coach.id) { items in
                DispatchQueue.main.async {
                    self.bookings = items
                    self.loading = false
                }
            }
        }
        .onChange(of: selectedAvailability) { _, newValue in
            if isOwnProfile {
                firestore.updateCurrentCoachAvailability(Array(newValue)) { err in
                    if let err = err {
                        print("Failed to update availability: \(err)")
                    }
                }
            }
        }
    }
}

struct CoachAvailabilityView_Previews: PreviewProvider {
    static var previews: some View {
        CoachAvailabilityView(coach: Coach(id: "demo", name: "Demo Coach", specialties: ["Tennis"], experienceYears: 5, availability: ["Morning"]))
            .environmentObject(FirestoreManager())
    }
}
