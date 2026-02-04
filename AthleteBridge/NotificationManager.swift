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
    /// Previously saved token so we can remove it when a new one arrives
    private var previouslySavedToken: String?

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

        // Force FCM to fetch a fresh token now that APNs token is set.
        // This ensures the FCM token is properly mapped to this APNs token,
        // fixing cases where FCM generated a token before APNs was ready.
        Messaging.messaging().token { [weak self] token, error in
            if let error = error {
                print("NotificationManager: FCM token refresh after APNs failed: \(error)")
                return
            }
            if let token = token {
                print("NotificationManager: FCM token after APNs set: \(token.prefix(20))...")
                self?.cachedFCMToken = token
                self?.saveTokenToFirestore(token)
            }
        }
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

    /// Remove device token from Firestore when user logs out.
    /// This prevents the device from receiving notifications for this account after logout.
    func removeDeviceToken(completion: (() -> Void)? = nil) {
        guard let uid = Auth.auth().currentUser?.uid else {
            print("NotificationManager: no authenticated user to remove token")
            completion?()
            return
        }
        guard let token = cachedFCMToken ?? previouslySavedToken else {
            print("NotificationManager: no token to remove")
            completion?()
            return
        }

        let db = Firestore.firestore()

        // Determine collection (coaches or clients) and remove token
        let userTypeRef = db.collection("userType").document(uid)
        userTypeRef.getDocument { [weak self] snap, err in
            let removeFromCollection: (String) -> Void = { collection in
                let docRef = db.collection(collection).document(uid)
                docRef.updateData(["deviceTokens": FieldValue.arrayRemove([token])]) { err in
                    if let err = err {
                        print("NotificationManager: failed to remove token on logout: \(err)")
                    } else {
                        print("NotificationManager: removed device token from \(collection)/\(uid)")
                    }
                    self?.previouslySavedToken = nil
                    completion?()
                }
            }

            if let data = snap?.data(), let t = (data["type"] as? String)?.uppercased() {
                let coll = (t == "COACH") ? "coaches" : "clients"
                removeFromCollection(coll)
            } else {
                // Fallback: check if coach document exists
                let coachRef = db.collection("coaches").document(uid)
                coachRef.getDocument { csnap, _ in
                    let collection = (csnap?.exists == true) ? "coaches" : "clients"
                    removeFromCollection(collection)
                }
            }
        }
    }

    /// Internal method to persist token to Firestore, replacing any previously saved token from this device
    private func saveTokenToFirestore(_ token: String) {
        guard let uid = Auth.auth().currentUser?.uid else {
            print("NotificationManager: no authenticated user to save token (will retry when authenticated)")
            return
        }

        let db = Firestore.firestore()
        let oldToken = previouslySavedToken

        // Try userType document first
        let userTypeRef = db.collection("userType").document(uid)
        userTypeRef.getDocument { [weak self] snap, err in
            if let err = err {
                print("NotificationManager: userType lookup error: \(err). Falling back to coaches check.")
                let coachRef = db.collection("coaches").document(uid)
                coachRef.getDocument { csnap, _ in
                    let collection = (csnap?.exists == true) ? "coaches" : "clients"
                    self?.replaceToken(db: db, collection: collection, uid: uid, oldToken: oldToken, newToken: token)
                }
                return
            }

            if let data = snap?.data(), let t = (data["type"] as? String)?.uppercased() {
                let coll = (t == "COACH") ? "coaches" : "clients"
                self?.replaceToken(db: db, collection: coll, uid: uid, oldToken: oldToken, newToken: token)
            } else {
                let coachRef = db.collection("coaches").document(uid)
                coachRef.getDocument { csnap, _ in
                    let collection = (csnap?.exists == true) ? "coaches" : "clients"
                    self?.replaceToken(db: db, collection: collection, uid: uid, oldToken: oldToken, newToken: token)
                }
            }
        }
    }

    /// Replace old token with new token in the user's deviceTokens array
    private func replaceToken(db: Firestore, collection: String, uid: String, oldToken: String?, newToken: String) {
        let docRef = db.collection(collection).document(uid)

        // If there's an old token different from the new one, remove it first
        if let old = oldToken, old != newToken {
            docRef.updateData(["deviceTokens": FieldValue.arrayRemove([old])]) { err in
                if let err = err {
                    print("NotificationManager: failed to remove old token: \(err)")
                } else {
                    print("NotificationManager: removed old token from \(collection)/\(uid)")
                }
                // Add new token regardless of whether removal succeeded
                docRef.setData(["deviceTokens": FieldValue.arrayUnion([newToken])], merge: true) { err in
                    if let err = err {
                        print("NotificationManager: failed to save device token to \(collection): \(err)")
                    } else {
                        print("NotificationManager: saved device token to \(collection)/\(uid)")
                        self.previouslySavedToken = newToken
                    }
                }
            }
        } else {
            // No old token or same token - just add
            docRef.setData(["deviceTokens": FieldValue.arrayUnion([newToken])], merge: true) { err in
                if let err = err {
                    print("NotificationManager: failed to save device token to \(collection): \(err)")
                } else {
                    print("NotificationManager: saved device token to \(collection)/\(uid)")
                    self.previouslySavedToken = newToken
                }
            }
        }
    }

    // UNUserNotificationCenterDelegate - show notifications while app is foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show banner, sound, and badge while in foreground
        completionHandler([.banner, .sound, .badge])
    }

    // Handle user tapping on notification — route to the appropriate screen
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        print("[DeepLink] didReceive notification tap. userInfo keys: \(userInfo.keys)")
        print("[DeepLink] userInfo: \(userInfo)")

        if let chatId = userInfo["chatId"] as? String, !chatId.isEmpty {
            print("[DeepLink] Found chatId: \(chatId)")
            DispatchQueue.main.async {
                DeepLinkManager.shared.pendingDestination = .chat(chatId: chatId)
            }
        } else if let bookingId = userInfo["bookingId"] as? String, !bookingId.isEmpty {
            print("[DeepLink] Found bookingId: \(bookingId)")
            DispatchQueue.main.async {
                DeepLinkManager.shared.pendingDestination = .booking(bookingId: bookingId)
            }
        } else {
            print("[DeepLink] No chatId or bookingId found in notification payload")
        }

        completionHandler()
    }
}
