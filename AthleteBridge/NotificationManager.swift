import Foundation
import UserNotifications
import UIKit
import Firebase
import FirebaseMessaging
import FirebaseAuth
@preconcurrency import EventKit

/// Centralized notification helper to register for APNs, obtain FCM token and persist it to Firestore.
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate, MessagingDelegate {
    static let shared = NotificationManager()

    /// Posted when a push notification arrives while the app is in the foreground.
    /// Views can observe this to refresh their data.
    static let didReceiveForegroundNotification = Notification.Name("didReceiveForegroundNotification")

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

        let userInfo = notification.request.content.userInfo

        // If a booking was cancelled/declined/rejected, remove the calendar event on this device
        let calendarRemovalTypes: Set<String> = ["booking_cancelled", "booking_rejected", "booking_declined"]
        if let type = userInfo["type"] as? String, calendarRemovalTypes.contains(type),
           let bookingId = userInfo["bookingId"] as? String, !bookingId.isEmpty {
            NotificationManager.removeCalendarEventForCancelledBooking(bookingId: bookingId)
        }

        // Broadcast so any visible view can refresh its data
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: NotificationManager.didReceiveForegroundNotification,
                                            object: nil,
                                            userInfo: userInfo)
        }
    }

    // Handle user tapping on notification — route to the appropriate screen
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        print("[DeepLink] didReceive notification tap. userInfo keys: \(userInfo.keys)")
        print("[DeepLink] userInfo: \(userInfo)")

        // If a booking was cancelled/declined/rejected, remove the calendar event on this device
        let calendarRemovalTypes: Set<String> = ["booking_cancelled", "booking_rejected", "booking_declined"]
        if let type = userInfo["type"] as? String, calendarRemovalTypes.contains(type),
           let bookingId = userInfo["bookingId"] as? String, !bookingId.isEmpty {
            NotificationManager.removeCalendarEventForCancelledBooking(bookingId: bookingId)
        }

        if let chatId = userInfo["chatId"] as? String, !chatId.isEmpty {
            print("[DeepLink] Found chatId: \(chatId)")
            DispatchQueue.main.async {
                DeepLinkManager.shared.pendingDestination = .chat(chatId: chatId)
            }
        } else if let bookingId = userInfo["bookingId"] as? String, !bookingId.isEmpty {
            let notifType = userInfo["type"] as? String
            print("[DeepLink] Found bookingId: \(bookingId), type: \(notifType ?? "nil")")
            DispatchQueue.main.async {
                if notifType == "payment_confirmed" || notifType == "payment_reminder" {
                    DeepLinkManager.shared.pendingDestination = .payments
                } else {
                    DeepLinkManager.shared.pendingBookingType = notifType
                    DeepLinkManager.shared.pendingDestination = .booking(bookingId: bookingId)
                }
            }
        } else if let orderId = userInfo["stringerOrderId"] as? String, !orderId.isEmpty {
            print("[DeepLink] Found stringerOrderId: \(orderId)")
            DispatchQueue.main.async {
                DeepLinkManager.shared.pendingDestination = .stringing(orderId: orderId)
            }
        } else if let type = userInfo["type"] as? String, let placeId = userInfo["placeId"] as? String, !placeId.isEmpty {
            if type == "club_join_request" {
                print("[DeepLink] Club join request for place: \(placeId)")
                DispatchQueue.main.async {
                    DeepLinkManager.shared.pendingDestination = .clubJoinRequest(placeId: placeId)
                }
            } else if type == "club_approved" {
                print("[DeepLink] Club approved for place: \(placeId)")
                DispatchQueue.main.async {
                    DeepLinkManager.shared.pendingDestination = .clubMembers(placeId: placeId)
                }
            } else if type == "club_announcement" {
                let announcementId = userInfo["announcementId"] as? String ?? ""
                print("[DeepLink] Club announcement for place: \(placeId), announcement: \(announcementId)")
                DispatchQueue.main.async {
                    DeepLinkManager.shared.pendingDestination = .clubAnnouncement(placeId: placeId, announcementId: announcementId)
                }
            }
        } else {
            print("[DeepLink] No chatId, bookingId, or stringerOrderId found in notification payload")
        }

        completionHandler()
    }

    // MARK: - Calendar removal for cancelled bookings

    /// Removes the Apple Calendar event for a cancelled booking on this device.
    /// Reads the per-user calendarEventId from Firestore and deletes the local EKEvent.
    /// Safe to call multiple times (idempotent).
    static func removeCalendarEventForCancelledBooking(bookingId: String) {
        guard let uid = Auth.auth().currentUser?.uid else {
            print("[CalendarRemoval] No authenticated user, skipping")
            return
        }

        let db = Firestore.firestore()
        let bookingRef = db.collection("bookings").document(bookingId)

        bookingRef.getDocument { snap, err in
            if let err = err {
                print("[CalendarRemoval] Failed to read booking \(bookingId): \(err)")
                return
            }

            guard let data = snap?.data() else {
                print("[CalendarRemoval] No booking data for \(bookingId)")
                return
            }

            // Look up per-user event ID first, fall back to legacy global field
            let eventId: String? = {
                if let perUser = data["calendarEventIds"] as? [String: String],
                   let id = perUser[uid], !id.isEmpty {
                    return id
                }
                if let global = data["calendarEventId"] as? String, !global.isEmpty {
                    return global
                }
                return nil
            }()

            guard let eventId = eventId, !eventId.isEmpty else {
                print("[CalendarRemoval] No calendarEventId for booking \(bookingId), user \(uid)")
                return
            }

            let handleAccess: (Bool, Error?) -> Void = { granted, error in
                guard granted, error == nil else {
                    print("[CalendarRemoval] Calendar access not granted")
                    return
                }

                let store = EKEventStore()
                if let event = store.event(withIdentifier: eventId) {
                    do {
                        try store.remove(event, span: .thisEvent)
                        print("[CalendarRemoval] Removed calendar event \(eventId) for cancelled booking \(bookingId)")

                        // Clean up per-user entry in Firestore
                        bookingRef.updateData([
                            "calendarEventIds.\(uid)": FieldValue.delete(),
                            "calendarRemovedAt": FieldValue.serverTimestamp(),
                            "calendarRemovedBy": uid
                        ]) { _ in }
                    } catch {
                        print("[CalendarRemoval] Failed to remove event: \(error)")
                    }
                } else {
                    print("[CalendarRemoval] Event \(eventId) not found on this device (already removed or added on another device)")
                }
            }

            if #available(iOS 17.0, *) {
                EKEventStore().requestFullAccessToEvents { granted, error in
                    handleAccess(granted, error)
                }
            } else {
                EKEventStore().requestAccess(to: .event) { granted, error in
                    handleAccess(granted, error)
                }
            }
        }
    }
}
