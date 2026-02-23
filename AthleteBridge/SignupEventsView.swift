import SwiftUI

struct SignupEventsView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel
    @Environment(\.scenePhase) private var scenePhase
    let place: PlaceToPlay
    @State private var showCreateSheet = false

    private var eventsForPlace: [SignupEvent] {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        return firestore.signupEvents
            .filter { $0.placeId == place.id && $0.eventDate >= startOfToday }
            .sorted { $0.eventDate < $1.eventDate }
    }

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()

    var body: some View {
        List {
            if eventsForPlace.isEmpty {
                Text("No upcoming events at this venue")
                    .foregroundColor(.secondary)
            } else {
                ForEach(eventsForPlace) { event in
                    NavigationLink {
                        SignupEventDetailView(event: event)
                            .environmentObject(firestore)
                            .environmentObject(auth)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(event.title)
                                .font(.headline)
                            Text(Self.dateFormatter.string(from: event.eventDate))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            HStack(spacing: 4) {
                                Image(systemName: "person.2")
                                    .font(.caption)
                                    .foregroundColor(event.isFull ? .red : Color("LogoGreen"))
                                Text(event.isFull ? "Full" : "\(event.spotsRemaining) spots left")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(event.isFull ? .red : Color("LogoGreen"))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Events")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showCreateSheet = true }) {
                    Label("Create", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateSignupEventView(place: place)
                .environmentObject(firestore)
        }
        .onAppear {
            firestore.fetchSignupEvents()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                firestore.fetchSignupEvents()
            }
        }
    }
}
