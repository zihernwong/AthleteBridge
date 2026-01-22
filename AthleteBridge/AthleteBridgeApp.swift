import SwiftUI
import FirebaseCore
import FirebaseAuth
import FirebaseInAppMessaging
import FirebaseMessaging
import UserNotifications

// AppDelegate to receive APNs device token and forward to FCM
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Set up UNUserNotificationCenter delegate
        UNUserNotificationCenter.current().delegate = NotificationManager.shared
        print("[AppDelegate] didFinishLaunchingWithOptions - UNUserNotificationCenter delegate set")
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("[AppDelegate] Received APNs device token: \(tokenString.prefix(20))...")
        NotificationManager.shared.updateAPNSToken(deviceToken)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[AppDelegate] Failed to register for remote notifications: \(error)")
    }
}

@main
struct AthleteBridgeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var auth = AuthViewModel()
    @StateObject private var firestore = FirestoreManager()

    init() {
        FirebaseApp.configure()

        // Initialize NotificationManager early to set up MessagingDelegate
        _ = NotificationManager.shared
        print("[AthleteBridgeApp] FirebaseApp.configure() called")

        // Suppress Firebase In-App Messaging automatic display/fetch until the
        // Firebase project is verified and In-App Messaging is configured in
        // the Firebase Console. This avoids repeated 403 fetch errors at app
        // startup while you finish setup.
        // Remove this line when IAM is correctly configured for your app.
        InAppMessaging.inAppMessaging().messageDisplaySuppressed = true

        // Print the configured Firebase options to verify the project/bundle match
        if let app = FirebaseApp.app() {
            let options = app.options
            let project = options.projectID ?? "<no projectID>"
            let client = options.clientID ?? "<no clientID>"
            let bundleID = Bundle.main.bundleIdentifier ?? "<no bundle id>"
            let apiKey = options.apiKey ?? "<no apiKey>"
            // mask apiKey for casual logs showing only last 4 characters
            let maskedApiKey: String
            if apiKey.count > 4 {
                let tail = apiKey.suffix(4)
                maskedApiKey = "****\(tail)"
            } else {
                maskedApiKey = apiKey
            }
            print("[AthleteBridgeApp] FirebaseApp options: projectID=\(project), clientID=\(client), apiKey=\(maskedApiKey), bundle=\(bundleID)")
        } else {
            print("[AthleteBridgeApp] WARNING: FirebaseApp.app() is nil after configure()")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth) // ✅ Provide environment object here
                .environmentObject(firestore)
        }
    }
}
