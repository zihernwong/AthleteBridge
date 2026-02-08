import Foundation
import UIKit
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import SafariServices

/// StripeCheckoutManager
/// - Writes a document to customers/{uid}/checkout_sessions to trigger firestore-stripe-payments
///   and listens for the extension to write back a "url" field. Presents a SFSafariViewController
///   when the URL becomes available.
/// - Also supports opening the billing portal by writing to customers/{uid}/portal_sessions.
final class StripeCheckoutManager {
    static let shared = StripeCheckoutManager()
    private init() {}

    private let db = Firestore.firestore()

    enum StripeError: LocalizedError {
        case notAuthenticated
        case invalidURL
        case presenterNotFound
        case responseError(String)

        var errorDescription: String? {
            switch self {
            case .notAuthenticated: return "User not signed in."
            case .invalidURL: return "Received invalid URL from server."
            case .presenterNotFound: return "Unable to find a view controller to present checkout."
            case .responseError(let msg): return msg
            }
        }
    }

    /// Start a Stripe Checkout session by creating a request doc under customers/{uid}/checkout_sessions.
    func startCheckout(priceId: String,
                       mode: String = "subscription",
                       successURL: String,
                       cancelURL: String,
                       metadata: [String: Any]? = nil,
                       completion: @escaping (Result<Void, Error>) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            DispatchQueue.main.async { completion(.failure(StripeError.notAuthenticated)) }
            return
        }

        let sessionsRef = db.collection("customers").document(uid).collection("checkout_sessions")
        let docRef = sessionsRef.document()

        var data: [String: Any] = [
            "price": priceId,
            "mode": mode,
            "success_url": successURL,
            "cancel_url": cancelURL,
            "created": FieldValue.serverTimestamp()
        ]
        if let metadata = metadata { data["metadata"] = metadata }

        var listener: ListenerRegistration?
        listener = docRef.addSnapshotListener { snapshot, error in
            if let error = error {
                listener?.remove()
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            guard let snapshot = snapshot, snapshot.exists else { return }
            let dict = snapshot.data() ?? [:]

            if let urlString = dict["url"] as? String {
                listener?.remove()
                DispatchQueue.main.async {
                    guard let url = URL(string: urlString) else { completion(.failure(StripeError.invalidURL)); return }
                    guard let presenter = Self.topMostViewController() else { completion(.failure(StripeError.presenterNotFound)); return }
                    let sf = SFSafariViewController(url: url)
                    presenter.present(sf, animated: true) {
                        completion(.success(()))
                    }
                }
                return
            }

            if let errMsg = dict["error"] as? String {
                listener?.remove()
                DispatchQueue.main.async { completion(.failure(StripeError.responseError(errMsg))) }
                return
            }
        }

        // create the request doc to trigger the extension
        docRef.setData(data) { err in
            if let err = err {
                listener?.remove()
                DispatchQueue.main.async { completion(.failure(err)) }
            }
            // otherwise wait for extension to write url
        }
    }

    /// Open Stripe Billing Portal using the Firebase extension's HTTPS callable function
    func openBillingPortal(returnURL: String? = nil, completion: @escaping (Result<Void, Error>) -> Void) {
        print("[StripeCheckoutManager] openBillingPortal called")
        guard Auth.auth().currentUser != nil else {
            print("[StripeCheckoutManager] openBillingPortal: not authenticated")
            DispatchQueue.main.async { completion(.failure(StripeError.notAuthenticated)) }
            return
        }

        let functions = Functions.functions()
        let callable = functions.httpsCallable("ext-firestore-stripe-payments-createPortalLink")

        var data: [String: Any] = [:]
        if let r = returnURL { data["returnUrl"] = r }

        print("[StripeCheckoutManager] openBillingPortal: calling createPortalLink function")
        callable.call(data) { result, error in
            if let error = error {
                print("[StripeCheckoutManager] openBillingPortal: function error: \(error)")
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            guard let resultData = result?.data as? [String: Any],
                  let urlString = resultData["url"] as? String else {
                print("[StripeCheckoutManager] openBillingPortal: no URL in response: \(String(describing: result?.data))")
                DispatchQueue.main.async { completion(.failure(StripeError.invalidURL)) }
                return
            }

            print("[StripeCheckoutManager] openBillingPortal: got URL: \(urlString)")
            DispatchQueue.main.async {
                guard let url = URL(string: urlString) else {
                    completion(.failure(StripeError.invalidURL))
                    return
                }
                guard let presenter = Self.topMostViewController() else {
                    completion(.failure(StripeError.presenterNotFound))
                    return
                }
                let sf = SFSafariViewController(url: url)
                presenter.present(sf, animated: true) {
                    completion(.success(()))
                }
            }
        }
    }

    // MARK: - Helpers
    private static func topMostViewController() -> UIViewController? {
        if #available(iOS 13.0, *) {
            let scenes = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
            for scene in scenes.reversed() {
                if let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
                    return topViewController(root)
                }
            }
        }
        if let root = UIApplication.shared.keyWindow?.rootViewController {
            return topViewController(root)
        }
        return nil
    }

    private static func topViewController(_ root: UIViewController) -> UIViewController? {
        if let presented = root.presentedViewController {
            return topViewController(presented)
        }
        if let nav = root as? UINavigationController, let top = nav.topViewController {
            return topViewController(top)
        }
        if let tab = root as? UITabBarController, let sel = tab.selectedViewController {
            return topViewController(sel)
        }
        return root
    }
}
