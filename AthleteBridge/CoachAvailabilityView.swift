import SwiftUI

struct CoachAvailabilityView: View {
    let coach: Coach
    @EnvironmentObject var firestore: FirestoreManager
    @State private var bookings: [FirestoreManager.BookingItem] = []
    @State private var loading: Bool = true

    var body: some View {
        List {
            if loading {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if bookings.isEmpty {
                Text("No bookings found for this coach").foregroundColor(.secondary)
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
        .navigationTitle("Availability")
        .onAppear {
            loading = true
            firestore.fetchBookingsForCoach(coachId: coach.id) { items in
                DispatchQueue.main.async {
                    self.bookings = items
                    self.loading = false
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
