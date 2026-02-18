import SwiftUI
import FirebaseAuth

struct MyClubsView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel
    @EnvironmentObject var deepLink: DeepLinkManager

    @State private var deepLinkPlace: PlaceToPlay? = nil
    @State private var deepLinkAnnouncementId: String? = nil
    @State private var navigateToDeepLink = false

    private var currentUid: String { auth.user?.uid ?? "" }

    /// Clubs the user is a member of or is the contact/leader for.
    private var myClubs: [PlaceToPlay] {
        firestore.placesToPlay.filter { place in
            place.members.contains { $0.id == currentUid } || place.contactUid == currentUid
        }
    }

    var body: some View {
        List {
            if myClubs.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.3")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("You haven't joined any clubs yet.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    NavigationLink {
                        PlacesToPlayView()
                            .environmentObject(firestore)
                            .environmentObject(auth)
                    } label: {
                        Text("Browse Places to Play")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(Color("LogoGreen"))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .listRowBackground(Color.clear)
            } else {
                ForEach(myClubs) { place in
                    NavigationLink {
                        PlaceDetailView(place: place)
                            .environmentObject(firestore)
                            .environmentObject(auth)
                    } label: {
                        clubRow(place: place)
                    }
                }
            }
        }
        .navigationTitle("My Clubs")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            firestore.fetchPlacesToPlay()
            handleDeepLink(deepLink.pendingDestination)
        }
        .onChange(of: deepLink.pendingDestination) { _old, destination in
            handleDeepLink(destination)
        }
        .onChange(of: firestore.placesToPlay) { _, _ in
            if deepLink.pendingDestination != nil {
                handleDeepLink(deepLink.pendingDestination)
            }
        }
        .navigationDestination(isPresented: $navigateToDeepLink) {
            if let place = deepLinkPlace {
                ClubAnnouncementsView(
                    place: place,
                    highlightAnnouncementId: deepLinkAnnouncementId
                )
                .environmentObject(firestore)
            }
        }
    }

    // MARK: - Club Row

    private func clubRow(place: PlaceToPlay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(place.name)
                .font(.headline)

            if !place.address.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundColor(.secondary)
                    Text(place.address)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .foregroundColor(Color("LogoGreen"))
                    Text("\(place.members.count) member\(place.members.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(Color("LogoGreen"))
                }

                if place.contactUid == currentUid {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .foregroundColor(Color("LogoBlue"))
                        Text("Leader")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(Color("LogoBlue"))
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Deep Link

    private func handleDeepLink(_ destination: DeepLinkDestination?) {
        guard case .clubAnnouncement(let placeId, let announcementId) = destination else { return }
        if let place = firestore.placesToPlay.first(where: { $0.id == placeId }) {
            deepLinkPlace = place
            deepLinkAnnouncementId = announcementId
            deepLink.pendingDestination = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                navigateToDeepLink = true
            }
        } else {
            firestore.fetchPlacesToPlay()
        }
    }
}
