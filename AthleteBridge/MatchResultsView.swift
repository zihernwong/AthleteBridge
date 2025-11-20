import SwiftUI

struct MatchResultsView: View {
    let client: Client
    @EnvironmentObject var firestore: FirestoreService

    var body: some View {
        let allCoaches = firestore.coaches.isEmpty ? coaches : firestore.coaches
        let matches = matchCoaches(client: client, allCoaches: allCoaches)

        List(matches) { coach in
            VStack(alignment: .leading) {
                Text(coach.name)
                    .font(.headline)
                Text("Specialties: \(coach.specialties.joined(separator: ", "))")
                Text("Experience: \(coach.experienceYears) years")
                Text("Availability: \(coach.availability.joined(separator: ", "))")
            }
            .padding(4)
        }
        .navigationTitle("Your Matches")
        .onAppear {
            if firestore.coaches.isEmpty {
                firestore.fetchCoaches()
            }
        }
    }
}
