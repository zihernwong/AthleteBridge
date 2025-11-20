import SwiftUI

struct MainAppView: View {
    @EnvironmentObject var auth: AuthViewModel
    @State private var navigateToClientForm = false
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // Profile tab (first)
            ProfileView()
                .tabItem {
                    Image(systemName: "person.crop.circle")
                    Text("Profile")
                }
                .tag(0)

            // Home tab
            NavigationStack {
                VStack(spacing: 20) {
                    Text("Welcome, \(auth.user?.email ?? "User")!")
                        .font(.title3)

                    Button("Logout") {
                        auth.logout()
                    }
                    .foregroundColor(.red)
                }
                .navigationTitle("AthleteBridge")
                // Present ClientFormView when navigateToClientForm becomes true
                .navigationDestination(isPresented: $navigateToClientForm) {
                    ClientFormView()
                }
            }
            .tabItem {
                Image(systemName: "house")
                Text("Home")
            }
            .tag(1)
        }
        .onAppear {
            // If user already signed in, navigate immediately
            navigateToClientForm = auth.user != nil
        }
        .onChange(of: auth.user?.uid) { _old, newValue in
            // When auth.user becomes non-nil (login) navigate; when nil (logout), reset
            navigateToClientForm = newValue != nil
        }
    }
}

// MARK: - Preview
struct MainAppView_Previews: PreviewProvider {
    static var previews: some View {
        MainAppView()
            .environmentObject(AuthViewModel())
    }
}
