import SwiftUI

struct MainAppView: View {
    @EnvironmentObject var auth: AuthViewModel
    @State private var navigateToClientForm = false
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // Profile tab
            ProfileView()
                .tabItem {
                    Image(systemName: "person.crop.circle")
                    Text("Profile")
                }
                .tag(0)

            // Home tab
            NavigationStack {
                ZStack {
                    // background logo (load via helper for bundle filename support)
                    if let bg = appLogoImageSwiftUI() {
                        bg
                            .resizable()
                            .scaledToFit()
                            .opacity(0.08)
                            .frame(maxWidth: 400)
                            .allowsHitTesting(false)
                    }

                    // Pin welcome content to top so it doesn't overlap the centered logo
                    VStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Welcome, \(auth.user?.email ?? "User")!")
                                .font(.title3)
                                .padding(.horizontal)

                            Button("Logout") {
                                auth.logout()
                            }
                            .foregroundColor(.red)
                            .padding(.horizontal)
                        }
                        .padding(.top, 12)

                        Spacer()
                    }
                }
                .navigationTitle("AthleteBridge")
                .navigationDestination(isPresented: $navigateToClientForm) {
                    ClientFormView()
                }
            }
            .tabItem {
                Image(systemName: "house")
                Text("Home")
            }
            .tag(1)

            // Reviews tab
            ReviewsView()
                .tabItem {
                    Image(systemName: "star.bubble")
                    Text("Reviews")
                }
                .tag(2)

            // Bookings tab (new)
            BookingsView()
                .tabItem {
                    Image(systemName: "calendar")
                    Text("Bookings")
                }
                .tag(3)

            // Locations tab (new)
            LocationsView()
                .tabItem {
                    Image(systemName: "mappin.and.ellipse")
                    Text("Locations")
                }
                .tag(4)
        }
        .onAppear {
            navigateToClientForm = auth.user != nil
        }
        .onChange(of: auth.user?.uid) { _old, newValue in
            navigateToClientForm = newValue != nil
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
