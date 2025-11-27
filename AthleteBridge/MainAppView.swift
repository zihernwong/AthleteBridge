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

            // Wrap other tabs so they become inaccessible until a profile is created
            RequiresProfile(content: { homeTab }, selectedTab: $selectedTab)
                .tabItem { Image(systemName: "house"); Text("Home") }
                .tag(1)

            RequiresProfile(content: { ReviewsView() }, selectedTab: $selectedTab)
                .tabItem { Image(systemName: "star.bubble"); Text("Reviews") }
                .tag(2)

            RequiresProfile(content: { BookingsView() }, selectedTab: $selectedTab)
                .tabItem { Image(systemName: "calendar"); Text("Bookings") }
                .tag(3)

            RequiresProfile(content: { LocationsView() }, selectedTab: $selectedTab)
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
            // Match ProfileView: prefer client photo, then coach photo, and use the same AsyncImage phase handling
            if let clientURL = firestore.currentClientPhotoURL {
                AsyncImage(url: clientURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView().frame(width: 44, height: 44)
                    case .success(let image):
                        image.resizable().scaledToFill().frame(width: 44, height: 44).clipShape(Circle()).shadow(radius: 4)
                    case .failure(_):
                        Image(systemName: "person.circle.fill").resizable().frame(width: 44, height: 44).foregroundColor(.secondary)
                    @unknown default:
                        Image(systemName: "person.circle.fill").resizable().frame(width: 44, height: 44).foregroundColor(.secondary)
                    }
                }
            } else if let coachURL = firestore.currentCoachPhotoURL {
                AsyncImage(url: coachURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView().frame(width: 44, height: 44)
                    case .success(let image):
                        image.resizable().scaledToFill().frame(width: 44, height: 44).clipShape(Circle()).shadow(radius: 4)
                    case .failure(_):
                        Image(systemName: "person.circle.fill").resizable().frame(width: 44, height: 44).foregroundColor(.secondary)
                    @unknown default:
                        Image(systemName: "person.circle.fill").resizable().frame(width: 44, height: 44).foregroundColor(.secondary)
                    }
                }
            } else {
                Image(systemName: "person.circle.fill").resizable().frame(width: 44, height: 44).foregroundColor(.secondary)
            }
        }
    }

    // A lightweight wrapper view that disables/obscures its content when the
    // signed-in user has no client or coach profile. The visual overlay includes
    // a call-to-action which switches to the Profile tab to create a profile.
    @ViewBuilder
    private func RequiresProfile<Content: View>(content: @escaping () -> Content, selectedTab: Binding<Int>) -> some View {
        let needsProfile = (auth.user != nil) && (firestore.currentClient == nil && firestore.currentCoach == nil)
        ZStack {
            content()
                .disabled(needsProfile)
                .blur(radius: needsProfile ? 4 : 0)

            if needsProfile {
                // Semi-opaque overlay with button
                Color(.systemBackground).opacity(0.4).ignoresSafeArea()
                VStack(spacing: 16) {
                    Text("Create your profile to continue")
                        .font(.headline)
                    Text("Please create a client or coach profile (including a photo) before using the app")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    Button(action: {
                        // Switch to Profile tab where the user can create their profile
                        selectedTab.wrappedValue = 0
                    }) {
                        Text("Create Profile")
                            .frame(minWidth: 180)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
                .padding()
                .background(.thinMaterial)
                .cornerRadius(12)
                .shadow(radius: 8)
                .padding(40)
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
