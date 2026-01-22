import SwiftUI

struct RootView: View {
    @EnvironmentObject var auth: AuthViewModel

    var body: some View {
        Group {
            if auth.user == nil {
                AuthScreen()
            } else {
                MainAppView()
            }
        }
        .onAppear {
            // Handle case where user is already authenticated on app launch
            if auth.user != nil {
                print("[RootView] User already authenticated on appear, registering for notifications")
                NotificationManager.shared.registerForPushNotifications()
                NotificationManager.shared.saveTokenIfNeeded()
            }
        }
        .onChange(of: auth.user) { newUser in
            if newUser != nil {
                // User just authenticated - register for push notifications
                print("[RootView] User state changed to authenticated, registering for notifications")
                NotificationManager.shared.registerForPushNotifications()
                // Also try to save any cached FCM token
                NotificationManager.shared.saveTokenIfNeeded()
            }
        }
    }
}

// MARK: - Preview
struct RootView_Previews: PreviewProvider {
    static var previews: some View {
        RootView()
            .environmentObject(AuthViewModel()) // Inject dummy AuthViewModel
    }
}

