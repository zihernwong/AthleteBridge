import Foundation
import UserNotifications
import UIKit
import Firebase
import FirebaseMessaging
import FirebaseAuth

/// Centralized notification helper to register for APNs, obtain FCM token and persist it to Firestore.
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate, MessagingDelegate {
    static let shared = NotificationManager()

    /// Cached FCM token - stored here in case it arrives before user authenticates
    private var cachedFCMToken: String?

    private override init() {
        super.init()
        Messaging.messaging().delegate = self
    }

    /// Request permission and register for remote notifications. Call this once after user signs in (or at app start).
    func registerForPushNotifications() {
        print("NotificationManager: registerForPushNotifications called")
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            print("NotificationManager: requestAuthorization callback - granted: \(granted), error: \(String(describing: error))")
            if let err = error { print("NotificationManager: requestAuthorization error: \(err)") }
            DispatchQueue.main.async {
                if granted {
                    print("NotificationManager: calling registerForRemoteNotifications()")
                    UIApplication.shared.registerForRemoteNotifications()
                } else {
                    print("NotificationManager: user denied notifications")
                }
            }
        }
    }

    // Call from AppDelegate's didRegisterForRemoteNotificationsWithDeviceToken to pass APNs token to FCM
    func updateAPNSToken(_ deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("NotificationManager: updateAPNSToken called with token: \(tokenString.prefix(20))...")
        Messaging.messaging().apnsToken = deviceToken
        print("NotificationManager: APNs token passed to FCM Messaging")
    }

    // MessagingDelegate - receives new FCM token
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        print("NotificationManager: didReceiveRegistrationToken: \(token)")

        // Always cache the token in case user isn't authenticated yet
        cachedFCMToken = token

        // Attempt to save immediately if user is authenticated
        saveTokenToFirestore(token)
    }

    /// Call this after user authenticates to save any cached FCM token
    func saveTokenIfNeeded() {
        guard let token = cachedFCMToken else {
            print("NotificationManager: saveTokenIfNeeded - no cached token")
            return
        }
        saveTokenToFirestore(token)
    }

    /// Internal method to persist token to Firestore
    private func saveTokenToFirestore(_ token: String) {
        guard let uid = Auth.auth().currentUser?.uid else {
            print("NotificationManager: no authenticated user to save token (will retry when authenticated)")
            return
        }

        let db = Firestore.firestore()
        // Try userType document first
        let userTypeRef = db.collection("userType").document(uid)
        userTypeRef.getDocument { [weak self] snap, err in
            if let err = err {
                print("NotificationManager: userType lookup error: \(err). Falling back to coaches check.")
                // fallback to existence check
                let coachRef = db.collection("coaches").document(uid)
                coachRef.getDocument { csnap, _ in
                    let collection = (csnap?.exists == true) ? "coaches" : "clients"
                    db.collection(collection).document(uid).setData(["deviceTokens": FieldValue.arrayUnion([token])], merge: true) { err in
                        if let err = err {
                            print("NotificationManager: failed to save device token to \(collection): \(err)")
                        } else {
                            print("NotificationManager: saved device token to \(collection)/\(uid)")
                        }
                    }
                }
                return
            }

            if let data = snap?.data(), let t = (data["type"] as? String)?.uppercased() {
                let coll = (t == "COACH") ? "coaches" : "clients"
                db.collection(coll).document(uid).setData(["deviceTokens": FieldValue.arrayUnion([token])], merge: true) { err in
                    if let err = err {
                        print("NotificationManager: failed to save device token to \(coll): \(err)")
                    } else {
                        print("NotificationManager: saved device token to \(coll)/\(uid)")
                    }
                }
            } else {
                // userType doc missing - check coaches collection as fallback
                let coachRef = db.collection("coaches").document(uid)
                coachRef.getDocument { csnap, _ in
                    let collection = (csnap?.exists == true) ? "coaches" : "clients"
                    db.collection(collection).document(uid).setData(["deviceTokens": FieldValue.arrayUnion([token])], merge: true) { err in
                        if let err = err {
                            print("NotificationManager: failed to save device token to \(collection): \(err)")
                        } else {
                            print("NotificationManager: saved device token to \(collection)/\(uid)")
                        }
                    }
                }
            }
        }
    }

    // UNUserNotificationCenterDelegate - show notifications while app is foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show banner, sound, and badge while in foreground
        completionHandler([.banner, .sound, .badge])
    }

    // Optional: handle user tapping on notification
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // You can parse response.notification.request.content.userInfo to navigate in-app
        completionHandler()
    }
}
