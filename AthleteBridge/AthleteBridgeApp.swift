import SwiftUI
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseInAppMessaging
import FirebaseMessaging
import UserNotifications

// AppDelegate to receive APNs device token and forward to FCM & Firebase Auth
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Configure Firebase FIRST — before any Firebase service is used.
        // This must happen here (not in App.init) because didFinishLaunchingWithOptions
        // runs before App.init when using @UIApplicationDelegateAdaptor.
        FirebaseApp.configure()
        print("[AppDelegate] FirebaseApp.configure() called")
        #if DEBUG
        Self.useFirebaseEmulatorsWhenUnitTesting()
        #endif

        // Initialize NotificationManager early to set up MessagingDelegate
        _ = NotificationManager.shared

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
            let maskedApiKey: String
            if apiKey.count > 4 {
                let tail = apiKey.suffix(4)
                maskedApiKey = "****\(tail)"
            } else {
                maskedApiKey = apiKey
            }
            print("[AppDelegate] FirebaseApp options: projectID=\(project), clientID=\(client), apiKey=\(maskedApiKey), bundle=\(bundleID)")
        } else {
            print("[AppDelegate] WARNING: FirebaseApp.app() is nil after configure()")
        }

        // Set up UNUserNotificationCenter delegate
        UNUserNotificationCenter.current().delegate = NotificationManager.shared
        print("[AppDelegate] didFinishLaunchingWithOptions complete")
        return true
    }

    #if DEBUG
    /// Unit tests run inside this app (it is their TEST_HOST). Point Auth and Firestore at the local
    /// Firebase emulators before anything touches them, so tests can never read or write production data.
    /// Start the emulators with: firebase emulators:start --only auth,firestore --project athletebridge-63176
    static let isRunningUnitTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    static let emulatorFirestoreHost = "127.0.0.1:8080"

    private static func useFirebaseEmulatorsWhenUnitTesting() {
        guard isRunningUnitTests else { return }
        Auth.auth().useEmulator(withHost: "127.0.0.1", port: 9099)
        // A production session left on the simulator can't refresh against the Auth emulator,
        // which keeps Firestore offline; tests always start signed out.
        try? Auth.auth().signOut()
        let settings = Firestore.firestore().settings
        settings.host = emulatorFirestoreHost
        settings.isSSLEnabled = false
        settings.cacheSettings = MemoryCacheSettings()
        Firestore.firestore().settings = settings
        print("[AppDelegate] Unit tests: using the Firebase Auth/Firestore emulators")
    }
    #endif

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("[AppDelegate] Received APNs device token: \(tokenString.prefix(20))...")
        // Forward to Firebase Auth (required for phone verification when swizzling is disabled)
        Auth.auth().setAPNSToken(deviceToken, type: .unknown)
        // Forward to FCM for push notifications
        NotificationManager.shared.updateAPNSToken(deviceToken)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[AppDelegate] Failed to register for remote notifications: \(error)")
    }

    // Forward silent push notifications to Firebase Auth for Phone Auth verification
    // Also handles booking cancellation calendar removal via content-available push
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        if Auth.auth().canHandleNotification(userInfo) {
            print("[AppDelegate] Firebase Auth handled silent push notification")
            completionHandler(.noData)
            return
        }

        // Handle booking cancellation/decline/rejection — remove calendar event on this device
        let calendarRemovalTypes: Set<String> = ["booking_cancelled", "booking_rejected", "booking_declined"]
        if let type = userInfo["type"] as? String, calendarRemovalTypes.contains(type),
           let bookingId = userInfo["bookingId"] as? String, !bookingId.isEmpty {
            print("[AppDelegate] Booking \(type) notification — removing calendar event for \(bookingId)")
            NotificationManager.removeCalendarEventForCancelledBooking(bookingId: bookingId)
            completionHandler(.newData)
            return
        }

        print("[AppDelegate] didReceiveRemoteNotification - not handled by Auth")
        completionHandler(.noData)
    }
}

@main
struct AthleteBridgeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var auth = AuthViewModel()
    @StateObject private var firestore = FirestoreManager()
    @StateObject private var subscriptionStore = SubscriptionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(firestore)
                .environmentObject(subscriptionStore)
                .environmentObject(DeepLinkManager.shared)
        }
    }
}
