import SwiftUI

struct MainAppView: View {
    @EnvironmentObject var auth: AuthViewModel
    @EnvironmentObject var firestore: FirestoreManager
    @State private var navigateToClientForm = false
    @State private var selectedTab: Int = 0
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
            // Locations tab moved to the first position
            RequiresProfile(content: { LocationsView() }, selectedTab: $selectedTab)
                .tabItem { Image(systemName: "mappin.and.ellipse"); Text("Locations") }
                .tag(4)

            // Home
            RequiresProfile(content: { homeTab }, selectedTab: $selectedTab)
                .tabItem { Image(systemName: "house"); Text("Home") }
                .tag(1)

            RequiresProfile(content: { ReviewsView() }, selectedTab: $selectedTab)
                .tabItem { Image(systemName: "star.bubble"); Text("Reviews") }
                .tag(2)

            RequiresProfile(content: { BookingsView() }, selectedTab: $selectedTab)
                .tabItem { Image(systemName: "calendar"); Text("Bookings") }
                .tag(3)

            // Profile tab moved to the last position but keeps tag 0 so existing code referencing tag 0 still selects Profile
            ProfileView()
                .tabItem { Image(systemName: "person.crop.circle"); Text("Profile") }
                .tag(0)
        }
        // Track manual tab selection so we don't override the user's explicit choice.
        .onChange(of: selectedTab) { old, new in
            // If the change wasn't caused by our auto-switch logic, mark it as a user selection
            if !didAutoSelectCoachHome {
                userDidSelectTab = true
            }
        }
        .onAppear {
            if let uid = auth.user?.uid {
                firestore.fetchCurrentProfiles(for: uid)
                firestore.fetchUserType(for: uid)
            }
            // Only navigate to ClientForm for non-coach users
            navigateToClientForm = (auth.user != nil) && !isCoachUserComputed
        }
        .onChange(of: auth.user?.uid) { oldValue, newValue in
            if let uid = newValue {
                firestore.fetchCurrentProfiles(for: uid)
                firestore.fetchUserType(for: uid)
            }
            // Only navigate to ClientForm for non-coach users
            navigateToClientForm = (newValue != nil) && !isCoachUserComputed
        }
        // React to role changes so the UI switches to the coach logout view as soon as we know the user is a coach
        .onChange(of: firestore.currentUserType) { oldType, newType in
            print("[MainAppView] currentUserType changed -> \(newType ?? "nil") (old=\(oldType ?? "nil"))")
            if let t = newType?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), t == "COACH" {
                // Only auto-switch to Home for coaches if the user hasn't explicitly
                // selected the Profile tab and we haven't already auto-switched.
                if selectedTab != 0 && !didAutoSelectCoachHome && !userDidSelectTab {
                    selectedTab = 1
                    didAutoSelectCoachHome = true
                }
            }
            // Recompute whether we should navigate to ClientForm (only for non-coach users)
            navigateToClientForm = (auth.user != nil) && !isCoachUserComputed
        }
        // If the userType document finished loading and indicates COACH, make sure Home is set to the coach view.
        .onChange(of: firestore.userTypeLoaded) { oldLoaded, newLoaded in
            guard newLoaded else { return }
            if (firestore.currentUserType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "COACH" {
                if selectedTab != 0 && !didAutoSelectCoachHome && !userDidSelectTab {
                    selectedTab = 1
                    didAutoSelectCoachHome = true
                }
            }
        }
        // If a coach profile is detected for the signed-in user, switch to the Home coach view immediately.
        .onChange(of: firestore.currentCoach?.id) { oldId, newId in
            if let uid = auth.user?.uid, newId == uid {
                if selectedTab != 0 && !didAutoSelectCoachHome && !userDidSelectTab {
                    selectedTab = 1
                    didAutoSelectCoachHome = true
                }
            }
            // Recompute navigateToClientForm when currentCoach changes
            navigateToClientForm = (auth.user != nil) && !isCoachUserComputed
        }
        // When the coaches list finishes loading, check whether the signed-in user is among them and, if so, switch to the coach Home view.
        .onChange(of: firestore.coaches.count) { oldCount, newCount in
            if let uid = auth.user?.uid, firestore.coaches.contains(where: { $0.id == uid }) {
                if selectedTab != 0 && !didAutoSelectCoachHome && !userDidSelectTab {
                    selectedTab = 1
                    didAutoSelectCoachHome = true
                }
            }
            // Recompute navigateToClientForm when coaches list updates
            navigateToClientForm = (auth.user != nil) && !isCoachUserComputed
        }
        // Also re-evaluate when userTypeLoaded flips (role info became available)
        .onChange(of: firestore.userTypeLoaded) { oldLoaded, newLoaded in
            if newLoaded {
                navigateToClientForm = (auth.user != nil) && !isCoachUserComputed
            }
        }
    }

    private var homeTab: some View {
        NavigationStack {
            ZStack {
                if let bg = appLogoImageSwiftUI() {
                    bg.resizable().scaledToFit().opacity(0.08).frame(maxWidth: 400).allowsHitTesting(false)
                }

                // Decide whether current user should be treated as a coach. We consider the user a coach if any of:
                // - the userType doc indicates COACH
                // - the cached currentCoach matches the auth uid
                // - the coaches list contains a coach with the auth uid (helps when currentCoach wasn't loaded yet)
                let isCoachUser: Bool = {
                    var res = false
                    if let t = firestore.currentUserType?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), t == "COACH" {
                        res = true
                    } else if let coach = firestore.currentCoach, coach.id == auth.user?.uid {
                        res = true
                    } else if let uid = auth.user?.uid, firestore.coaches.contains(where: { $0.id == uid }) {
                        res = true
                    }
                    print("[MainAppView.homeTab] isCoachUser=\(res) currentUserType=\(firestore.currentUserType ?? "nil") userTypeLoaded=\(firestore.userTypeLoaded) currentCoachExists=\(firestore.currentCoach != nil) coachesCount=\(firestore.coaches.count)")
                    return res
                }()

                // If user is a coach, show only the AthleteBridge logo (no other functionality)
                if isCoachUserComputed {
                    VStack {
                        Spacer()
                        if let img = appLogoImageSwiftUI() {
                            img.resizable().scaledToFit().frame(maxWidth: 300).padding()
                        } else {
                            Image("AthleteBridgeLogo").resizable().scaledToFit().frame(maxWidth: 300).padding()
                        }
                        Spacer()
                    }
                } else {
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
        // Determine coach user similarly to `homeTab` so both places use the same rule.
        let isCoachUser = {
            if let t = firestore.currentUserType?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), t == "COACH" { return true }
            if let coach = firestore.currentCoach, coach.id == auth.user?.uid { return true }
            if let uid = auth.user?.uid, firestore.coaches.contains(where: { $0.id == uid }) { return true }
            return false
        }()

        // Require profile only when we know the user's type and they are not a coach and they have no profile docs.
        // If userType is not yet loaded, be conservative and wait for it to avoid briefly showing the wrong UI.
        let needsProfile: Bool = {
            guard auth.user != nil else { return false }
            // If userType hasn't finished loading, we avoid forcing the 'create profile' flow here so
            // the home tab decision (above) can rely on coach profile detection if available.
            if !firestore.userTypeLoaded {
                // If a coach profile already exists, don't require a profile; otherwise, keep tabs enabled
                return !(firestore.currentCoach != nil)
            }
            return !isCoachUser && (firestore.currentClient == nil && firestore.currentCoach == nil)
        }()
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
