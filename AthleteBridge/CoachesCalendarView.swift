import SwiftUI

/// Shows a list of matched coaches and navigates to each coach's availability (their bookings).
struct CoachesCalendarView: View {
    let coaches: [Coach]
    @EnvironmentObject var firestore: FirestoreManager

    var body: some View {
        List(coaches) { coach in
            NavigationLink(destination: CoachAvailabilityView(coach: coach).environmentObject(firestore)) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(coach.name).font(.headline)
                        if !coach.specialties.isEmpty {
                            Text(coach.specialties.joined(separator: ", "))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Text("View calendar")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .padding(.vertical, 6)
            }
        }
        .navigationTitle("Coaches Calendar")
        .onAppear {
            // ensure coaches list is populated
            if firestore.coaches.isEmpty { firestore.fetchCoaches() }
        }
    }
}

struct CoachesCalendarView_Previews: PreviewProvider {
    static var previews: some View {
        CoachesCalendarView(coaches: [Coach(id: "demo", name: "Demo Coach", specialties: ["Tennis"], experienceYears: 3, availability: ["Morning"])])
            .environmentObject(FirestoreManager())
    }
}
