import Foundation
import UserNotifications
import UIKit
import Firebase
import FirebaseMessaging
import FirebaseAuth

/// Centralized notification helper to register for APNs, obtain FCM token and persist it to Firestore.
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate, MessagingDelegate {
    static let shared = NotificationManager()

    private override init() {
        super.init()
        Messaging.messaging().delegate = self
    }

    /// Request permission and register for remote notifications. Call this once after user signs in (or at app start).
    func registerForPushNotifications() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let err = error { print("NotificationManager: requestAuthorization error: \(err)") }
            DispatchQueue.main.async {
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                } else {
                    print("NotificationManager: user denied notifications")
                }
            }
        }
    }

    // Call from AppDelegate's didRegisterForRemoteNotificationsWithDeviceToken to pass APNs token to FCM
    func updateAPNSToken(_ deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    // MessagingDelegate - receives new FCM token
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        print("NotificationManager: didReceiveRegistrationToken: \(token)")
        // Persist the token in Firestore under the current user's document.
        // Resolve user role via userType/{uid} if present; fallback to checking coaches/{uid} existence.
        guard let uid = Auth.auth().currentUser?.uid else { print("NotificationManager: no authenticated user to save token"); return }
        let db = Firestore.firestore()
        // Try userType document first
        let userTypeRef = db.collection("userType").document(uid)
        userTypeRef.getDocument { snap, err in
            if let err = err {
                print("NotificationManager: userType lookup error: \(err). Falling back to coaches check.")
                // fallback to existence check
                let coachRef = db.collection("coaches").document(uid)
                coachRef.getDocument { csnap, _ in
                    let collection = (csnap?.exists == true) ? "coaches" : "clients"
                    db.collection(collection).document(uid).setData(["deviceTokens": FieldValue.arrayUnion([token])], merge: true) { err in
                        if let err = err { print("NotificationManager: failed to save device token to \(collection): \(err)") }
                    }
                }
                return
            }

            if let data = snap?.data(), let t = (data["type"] as? String)?.uppercased() {
                let coll = (t == "COACH") ? "coaches" : "clients"
                db.collection(coll).document(uid).setData(["deviceTokens": FieldValue.arrayUnion([token])], merge: true) { err in
                    if let err = err { print("NotificationManager: failed to save device token to \(coll): \(err)") }
                }
            } else {
                // userType doc missing - check coaches collection as fallback
                let coachRef = db.collection("coaches").document(uid)
                coachRef.getDocument { csnap, _ in
                    let collection = (csnap?.exists == true) ? "coaches" : "clients"
                    db.collection(collection).document(uid).setData(["deviceTokens": FieldValue.arrayUnion([token])], merge: true) { err in
                        if let err = err { print("NotificationManager: failed to save device token to \(collection): \(err)") }
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
