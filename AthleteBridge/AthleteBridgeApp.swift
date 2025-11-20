import SwiftUI
import FirebaseCore
import FirebaseAuth

@main
struct AthleteBridgeApp: App {
    @StateObject private var auth = AuthViewModel()
    @StateObject private var firestore = FirestoreService()

    init() {
        FirebaseApp.configure()
        print("[AthleteBridgeApp] FirebaseApp.configure() called")

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
