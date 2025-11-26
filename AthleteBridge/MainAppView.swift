import SwiftUI

struct MainAppView: View {
    @EnvironmentObject var auth: AuthViewModel
    @EnvironmentObject var firestore: FirestoreManager
    @State private var navigateToClientForm = false
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ProfileView()
                .tabItem { Image(systemName: "person.crop.circle"); Text("Profile") }
                .tag(0)

            homeTab
                .tabItem { Image(systemName: "house"); Text("Home") }
                .tag(1)

            ReviewsView()
                .tabItem { Image(systemName: "star.bubble"); Text("Reviews") }
                .tag(2)

            BookingsView()
                .tabItem { Image(systemName: "calendar"); Text("Bookings") }
                .tag(3)

            LocationsView()
                .tabItem { Image(systemName: "mappin.and.ellipse"); Text("Locations") }
                .tag(4)
        }
        .onAppear {
            if let uid = auth.user?.uid { firestore.fetchCurrentProfiles(for: uid) }
            navigateToClientForm = auth.user != nil
        }
        .onChange(of: auth.user?.uid) { oldValue, newValue in
            if let uid = newValue { firestore.fetchCurrentProfiles(for: uid) }
            navigateToClientForm = newValue != nil
        }
    }

    private var homeTab: some View {
        NavigationStack {
            ZStack {
                if let bg = appLogoImageSwiftUI() {
                    bg.resizable().scaledToFit().opacity(0.08).frame(maxWidth: 400).allowsHitTesting(false)
                }

                VStack {
                    HStack(spacing: 12) {
                        avatarView

                        VStack(alignment: .leading) {
                            Text("Welcome, \(auth.user?.email ?? "User")!")
                                .font(.title3)
                            // Debug: show resolved photo URL if available
                            if let clientURL = firestore.currentClientPhotoURL {
                                Text("Client photo: \(clientURL.absoluteString)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else if let coachURL = firestore.currentCoachPhotoURL {
                                Text("Coach photo: \(coachURL.absoluteString)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("No photo URL resolved")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Button("Logout") { auth.logout() }
                                .foregroundColor(.red)
                        }
                        .padding(.horizontal)

                        Spacer()
                    }
                    .padding(.top, 12)

                    Spacer()
                }
            }
            .navigationTitle("AthleteBridge")
            .navigationDestination(isPresented: $navigateToClientForm) { ClientFormView() }
        }
    }

    private var avatarView: some View {
        Group {
            if let url = firestore.currentClientPhotoURL ?? firestore.currentCoachPhotoURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty: ProgressView().frame(width: 44, height: 44)
                    case .success(let image): image.resizable().scaledToFill().frame(width: 44, height: 44).clipShape(Circle())
                    case .failure(_): Image(systemName: "person.circle.fill").resizable().frame(width: 44, height: 44).foregroundColor(.secondary)
                    @unknown default: Image(systemName: "person.circle.fill").resizable().frame(width: 44, height: 44).foregroundColor(.secondary)
                    }
                }
            } else {
                Image(systemName: "person.circle.fill").resizable().frame(width: 44, height: 44).foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Preview
struct MainAppView_Previews: PreviewProvider {
    static var previews: some View {
        MainAppView()
            .environmentObject(AuthViewModel())
            .environmentObject(FirestoreManager())
    }
}
