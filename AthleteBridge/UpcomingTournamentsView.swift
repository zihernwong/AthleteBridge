import SwiftUI

struct UpcomingTournamentsView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel
    @State private var showTournamentInput: Bool = false

    private var upcomingTournaments: [Tournament] {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        return firestore.tournaments
            .filter { $0.endDate >= startOfToday }
            .sorted { $0.startDate < $1.startDate }
    }

    private func partnerSeekerText(for tournament: Tournament) -> String {
        let uid = auth.user?.uid ?? ""
        let others = tournament.participants.keys.filter { $0 != uid }.count
        switch others {
        case 0: return "Find a partner"
        case 1: return "1 player looking for a partner"
        default: return "\(others) players looking for partners"
        }
    }

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }()

    var body: some View {
        List {
            if upcomingTournaments.isEmpty {
                Text("No upcoming tournaments").foregroundColor(.secondary)
            } else {
                ForEach(upcomingTournaments) { tournament in
                    NavigationLink {
                        TournamentDetailView(tournament: tournament)
                            .environmentObject(firestore)
                            .environmentObject(auth)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(tournament.name)
                                .font(.headline)
                            Text("\(Self.dateFormatter.string(from: tournament.startDate)) – \(Self.dateFormatter.string(from: tournament.endDate))")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            HStack(spacing: 4) {
                                Image(systemName: "mappin.and.ellipse")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(tournament.location)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            if let link = tournament.signupLink, !link.isEmpty, let url = URL(string: link) {
                                Link(destination: url) {
                                    Label("Tournament Signup", systemImage: "link")
                                        .font(.subheadline)
                                }
                            }
                            HStack(spacing: 4) {
                                Image(systemName: "person.2")
                                    .font(.caption)
                                Text(partnerSeekerText(for: tournament))
                                    .font(.subheadline)
                            }
                            .foregroundColor(Color("LogoBlue"))
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Upcoming Tournaments")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showTournamentInput = true }) {
                    Label("Suggest", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showTournamentInput) {
            TournamentInputView()
                .environmentObject(firestore)
        }
        .onAppear {
            firestore.fetchTournaments()
        }
    }
}
