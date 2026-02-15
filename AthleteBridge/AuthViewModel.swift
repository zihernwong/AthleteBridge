import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
class AuthViewModel: ObservableObject {
    @Published var user: User?
    @Published var isLoading = false
    @Published var errorMessage: String?

    init() {
        self.user = Auth.auth().currentUser
        
        // Listen for auth state changes
        Auth.auth().addStateDidChangeListener { _, newUser in
            self.user = newUser
        }
    }

    // MARK: - Sign Up
    func signUp(email: String, password: String, userType: String? = nil, additionalTypes: [String] = []) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false } // ensure we always clear loading

        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            self.user = result.user

            // After creating the auth user, write the chosen user type to Firestore
            if let uid = result.user.uid as String?, let type = userType {
                let db = Firestore.firestore()
                var data: [String: Any] = ["type": type]
                if !additionalTypes.isEmpty {
                    data["additionalTypes"] = additionalTypes
                }
                db.collection("userType").document(uid).setData(data) { err in
                    if let err = err {
                        print("AuthViewModel: failed to write userType for uid=\(uid): \(err)")
                        // Don't treat Firestore write failure as fatal for signup; surface warning
                        DispatchQueue.main.async {
                            self.errorMessage = "Account created but failed to save user type. Please try again later."
                        }
                    } else {
                        print("AuthViewModel: userType \(type) with additionalTypes \(additionalTypes) written for uid=\(uid)")
                    }
                }
            }
        } catch {
            // Use centralized handler so we print all useful debug info
            errorMessage = handleAuthError(error)
        }
    }

    // MARK: - Login
    func login(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            self.user = result.user
        } catch {
            errorMessage = handleAuthError(error)
        }
    }

    // MARK: - Logout
    func logout() {
        // Remove device token first to prevent receiving notifications for this account
        NotificationManager.shared.removeDeviceToken {
            do {
                try Auth.auth().signOut()
                DispatchQueue.main.async {
                    self.user = nil
                }
            } catch {
                print("Error signing out: \(error)")
            }
        }
    }

    // MARK: - Phone Verification
    @Published var verificationID: String?
    @Published var phoneVerificationInProgress = false

    /// Send an SMS verification code to the given phone number (E.164 format, e.g. "+15551234567").
    func sendPhoneVerification(phoneNumber: String, completion: ((Bool) -> Void)? = nil) {
        phoneVerificationInProgress = true
        errorMessage = nil
        PhoneAuthProvider.provider().verifyPhoneNumber(phoneNumber, uiDelegate: nil) { [weak self] verificationID, error in
            DispatchQueue.main.async {
                self?.phoneVerificationInProgress = false
                if let error = error {
                    self?.errorMessage = self?.handleAuthError(error)
                    completion?(false)
                    return
                }
                self?.verificationID = verificationID
                completion?(true)
            }
        }
    }

    /// Confirm the 6-digit SMS code and link the phone credential to the current user.
    func confirmPhoneCode(_ code: String, firestore: FirestoreManager, completion: @escaping (Bool) -> Void) {
        guard let verificationID = verificationID else {
            errorMessage = "No verification in progress."
            completion(false)
            return
        }
        phoneVerificationInProgress = true
        errorMessage = nil

        let credential = PhoneAuthProvider.provider().credential(withVerificationID: verificationID, verificationCode: code)

        guard let currentUser = Auth.auth().currentUser else {
            phoneVerificationInProgress = false
            errorMessage = "Not signed in."
            completion(false)
            return
        }

        currentUser.link(with: credential) { [weak self] _, error in
            DispatchQueue.main.async {
                self?.phoneVerificationInProgress = false
                if let error = error {
                    let nsError = error as NSError
                    // If phone is already linked, treat as success
                    if AuthErrorCode(rawValue: nsError.code) == .providerAlreadyLinked {
                        firestore.setPhoneVerified { _ in completion(true) }
                        return
                    }
                    self?.errorMessage = self?.handleAuthError(error)
                    completion(false)
                    return
                }
                // Success — persist to Firestore
                firestore.setPhoneVerified { _ in completion(true) }
                self?.verificationID = nil
            }
        }
    }

    // MARK: - Error handling
    private func handleAuthError(_ error: Error) -> String {
        let nsError = error as NSError

        // Print full NSError for debugging
        print("[AuthViewModel] Firebase Auth error: \(nsError)")
        print("[AuthViewModel] domain=\(nsError.domain) code=\(nsError.code)")
        print("[AuthViewModel] userInfo=\(nsError.userInfo)")

        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] {
            print("[AuthViewModel] underlying error: \(underlying)")
        }

        // Try to map to AuthErrorCode for friendlier messages
        if let authCode = AuthErrorCode(rawValue: nsError.code) {
            print("[AuthViewModel] AuthErrorCode mapped: \(authCode)")
            switch authCode {
            case .invalidEmail:
                return "Invalid email address."
            case .emailAlreadyInUse:
                return "This email is already in use."
            case .weakPassword:
                return "Password is too weak. Try again."
            case .wrongPassword:
                return "Invalid password. Please try again."
            case .userNotFound:
                return "No user found for that email."
            case .userDisabled:
                return "This user account has been disabled."
            case .networkError:
                return "Network error. Please try again."
            case .internalError:
                // internalError is generic — include underlying description or give friendly guidance
                if let deserialized = nsError.userInfo["FIRAuthErrorUserInfoDeserializedResponseKey"] as? [String: Any],
                   let message = deserialized["message"] as? String {
                    // Common server-side messages: CONFIGURATION_NOT_FOUND, etc.
                    if message == "CONFIGURATION_NOT_FOUND" {
                        return "Firebase Auth is not configured for this app (configuration not found). Make sure your GoogleService-Info.plist is in the app bundle and FirebaseApp.configure() is called."
                    }
                }
                if let detail = nsError.userInfo[NSLocalizedDescriptionKey] as? String, !detail.isEmpty {
                    return "Authentication failed: \(detail)"
                } else {
                    return "An internal error occurred during authentication. Please try again or check Firebase configuration."
                }
            case .invalidCredential:
                return "Invalid credentials. Please try again."
            case .invalidVerificationCode, .invalidVerificationID:
                return "Invalid verification code."
            case .userTokenExpired, .requiresRecentLogin:
                return "Session expired — please sign in again."
            default:
                // For any other known auth codes, return a concise, user-friendly fallback
                return "Authentication failed. Please try again. (\(authCode))"
            }
        }

        // If the error contains a deserialized server response with a useful message, surface a friendly version
        if let deserialized = nsError.userInfo["FIRAuthErrorUserInfoDeserializedResponseKey"] as? [String: Any],
           let message = deserialized["message"] as? String {
            // Map a few server messages to nicer text
            switch message {
            case "CONFIGURATION_NOT_FOUND":
                return "Firebase Auth configuration not found — ensure GoogleService-Info.plist is added and Firebase is configured."
            default:
                return "Authentication failed: \(message)"
            }
        }

        // Fallback: prefer a concise, non-technical localized message
        let localized = nsError.localizedDescription
        if localized.isEmpty {
            return "Authentication failed. Please try again."
        }
        // Strip verbose technical prefixes if present (keep it short)
        return localized
    }
}
