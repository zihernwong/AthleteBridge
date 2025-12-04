import SwiftUI

/// Shows a list of matched coaches and navigates to each coach's availability (their bookings).
struct CoachesCalendarView: View {
    let coaches: [Coach]
    @EnvironmentObject var firestore: FirestoreManager

    var body: some View {
        List(coaches) { coach in
            NavigationLink(destination: CoachAvailabilityView(coach: coach).environmentObject(firestore)) {
                HStack(alignment: .top, spacing: 12) {
                    // Pass coach-specific photo URL when resolved; fall back to default AvatarView behavior
                    let coachURL = firestore.coachPhotoURLs[coach.id] ?? nil
                    AvatarView(url: coachURL ?? nil, size: 56, useCurrentUser: false)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(coach.name).font(.headline)
                            Spacer()
                            if let rate = coach.hourlyRate {
                                Text(String(format: "$%.0f", rate))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if !coach.specialties.isEmpty {
                            Text(coach.specialties.joined(separator: ", "))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        if let bio = coach.bio, !bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(bio)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }

                        if !coach.availability.isEmpty {
                            Text(coach.availability.joined(separator: ", "))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    Text("View calendar")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .padding(.vertical, 8)
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
