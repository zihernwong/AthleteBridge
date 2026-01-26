import SwiftUI

struct MainAppView: View {
    @EnvironmentObject var auth: AuthViewModel
    @EnvironmentObject var firestore: FirestoreManager
        // Small UIImage used for the TabBar icon (loaded from firestore URLs)
    @State private var tabAvatarImage: UIImage? = nil
    @State private var selectedTab: Int = 1 // default to Home so Profile view doesn't open fullscreen by default
    // Prevent repeated automatic switching to the coach Home tab once the user has actively
    // chosen a tab (for example, Profile). We auto-switch at most once to avoid stomping
    // the user's explicit tab selection.
    @State private var didAutoSelectCoachHome: Bool = false
    // Flag set when the user manually selects a tab so we don't override their choice
    @State private var userDidSelectTab: Bool = false

    // Computed flag: true when the signed-in user should be treated as a coach
    private var isCoachUserComputed: Bool {
        if let t = firestore.currentUserType?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), t == "COACH" { return true }
        if let coach = firestore.currentCoach, coach.id == auth.user?.uid { return true }
        if let uid = auth.user?.uid, firestore.coaches.contains(where: { $0.id == uid }) { return true }
        return false
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            // Messages tab (placeholder) — moved Locations into Bookings
            RequiresProfile(content: { messagesTab }, selectedTab: $selectedTab)
                .tabItem { Label("Messages", systemImage: "message") }
                .badge(firestore.unreadChatIds.count)
                .tag(4)

            // Home (or Payments for coaches)
            RequiresProfile(content: { homeOrPaymentsTab() }, selectedTab: $selectedTab)
                .tabItem {
                    let homeTitle = isCoachUserComputed ? "Payments" : "Home"
                    let homeIcon = isCoachUserComputed ? "creditcard" : "house"
                    Label(homeTitle, systemImage: homeIcon)
                }
                .tag(1)

            // For coaches, keep Reviews as a primary tab; for clients, move it to More
            if isCoachUserComputed {
                RequiresProfile(content: { ReviewsView() }, selectedTab: $selectedTab)
                    .tabItem { Label("Reviews", systemImage: "star.bubble") }
                    .tag(2)
            }

            // Bookings tab wrapper: shows BookingsView and exposes Locations as a navigable page.
            RequiresProfile(content: { bookingsTab }, selectedTab: $selectedTab)
                .tabItem { Label("Bookings", systemImage: "calendar") }
                .tag(3)

            // Profile tab (use system icon to avoid layout issues)
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(0)

            // Additional Payments tab for clients (keep Home intact and all existing tabs)
            if !isCoachUserComputed {
                RequiresProfile(content: { paymentsTab }, selectedTab: $selectedTab)
                    .tabItem { Label("Payments", systemImage: "creditcard") }
                    .tag(5)

                // Move Reviews to overflow (More) for clients
                RequiresProfile(content: { ReviewsView() }, selectedTab: $selectedTab)
                    .tabItem { Label("Reviews", systemImage: "star.bubble") }
                    .tag(6)
            }
        }
        // Track manual tab selection so we don't override the user's explicit choice.
        .onChange(of: selectedTab) { _old, _new in
            if !didAutoSelectCoachHome {
                userDidSelectTab = true
            }
        }
        .onAppear {
            if let uid = auth.user?.uid {
                firestore.fetchCurrentProfiles(for: uid)
                firestore.fetchUserType(for: uid)
            }
            if let clientURL = firestore.currentClientPhotoURL { loadTabAvatar(from: clientURL) }
            else if let coachURL = firestore.currentCoachPhotoURL { loadTabAvatar(from: coachURL) }
        }
        .onChange(of: auth.user?.uid) { _old, _new in
            if let uid = _new {
                firestore.fetchCurrentProfiles(for: uid)
                firestore.fetchUserType(for: uid)
            }
        }
        .onChange(of: isCoachUserComputed) { _old, isCoach in
            if isCoach && selectedTab != 0 && !didAutoSelectCoachHome && !userDidSelectTab {
                selectedTab = 1
                didAutoSelectCoachHome = true
            }
        }
        .onChange(of: firestore.currentClientPhotoURL) { _old, new in
            if let u = new { loadTabAvatar(from: u) } else { tabAvatarImage = nil }
        }
        .onChange(of: firestore.currentCoachPhotoURL) { _old, new in
            if let u = new { loadTabAvatar(from: u) } else { if firestore.currentClientPhotoURL == nil { tabAvatarImage = nil } }
        }
    }

    private var homeTab: some View {
        NavigationStack {
            ClientFormView()
                .environmentObject(firestore)
                .environmentObject(auth)
        }
    }

    // New Payments tab content for coaches
    private var paymentsTab: some View {
        NavigationStack {
            PaymentsView()
                .navigationTitle("Payments")
        }
    }

    // MARK: - Tab avatar loading
    private func loadTabAvatar(from url: URL?) {
        guard let url = url else { self.tabAvatarImage = nil; return }
        // simple fetch — small images ok; replace with caching as needed
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let d = data, let ui = UIImage(data: d) else { return }
            // Resize to a reasonable size for tab bar to avoid large memory usage
            let targetSize = CGSize(width: 64, height: 64)
            let resized = ui.resizeMaintainingAspectRatio(targetSize: targetSize)
            DispatchQueue.main.async { self.tabAvatarImage = resized }
        }.resume()
    }


    @ViewBuilder
    private func RequiresProfile<Content: View>(content: @escaping () -> Content, selectedTab: Binding<Int>) -> some View {
        let needsProfile: Bool = {
            guard auth.user != nil else { return false }
            // If we haven't finished loading the user's type/profile yet, avoid blocking the UI.
            // We only want to show the "Create Profile" blur once we've confirmed there is no profile.
            if !firestore.userTypeLoaded && firestore.currentClient == nil && firestore.currentCoach == nil {
                // Still checking; do not require profile yet to prevent a brief flash
                return false
            }

            // Otherwise evaluate normally: non-coach users without either profile need to create one.
            return !isCoachUserComputed && (firestore.currentClient == nil && firestore.currentCoach == nil)
        }()

        ZStack {
            content()
                .disabled(needsProfile)
                .blur(radius: needsProfile ? 4 : 0)

            if needsProfile {
                Color(.systemBackground).opacity(0.4).ignoresSafeArea()
                VStack(spacing: 16) {
                    Text("Create your profile to continue").font(.headline)
                    Text("Please create a client or coach profile (including a photo) before using the app")
                        .font(.subheadline).multilineTextAlignment(.center).foregroundColor(.secondary).padding(.horizontal)
                    Button(action: { selectedTab.wrappedValue = 0 }) {
                        Text("Create Profile").frame(minWidth:180).padding().background(Color.accentColor).foregroundColor(.white).cornerRadius(10)
                    }
                }
                .padding().background(.thinMaterial).cornerRadius(12).shadow(radius:8).padding(40)
            }
        }
    }

    // Placeholder messages tab content
    private var messagesTab: some View {
        MessagesView()
            .environmentObject(firestore)
            .environmentObject(auth)
    }

    // Bookings tab wrapper: shows BookingsView (Input Time Away and Locations are inside BookingsView for coaches)
    private var bookingsTab: some View {
        NavigationStack {
            BookingsView()
                .navigationTitle("Bookings")
        }
    }

    @ViewBuilder
    private func homeOrPaymentsTab() -> some View {
        if isCoachUserComputed {
            paymentsTab
        } else {
            homeTab
        }
    }
}

struct MainAppView_Previews: PreviewProvider {
    static var previews: some View {
        MainAppView().environmentObject(AuthViewModel()).environmentObject(FirestoreManager())
    }
}
