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
    func signUp(email: String, password: String, userType: String? = nil) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false } // ensure we always clear loading
        
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            self.user = result.user

            // After creating the auth user, write the chosen user type to Firestore
            if let uid = result.user.uid as String?, let type = userType {
                let db = Firestore.firestore()
                db.collection("userType").document(uid).setData(["type": type]) { err in
                    if let err = err {
                        print("AuthViewModel: failed to write userType for uid=\(uid): \(err)")
                        // Don't treat Firestore write failure as fatal for signup; surface warning
                        DispatchQueue.main.async {
                            self.errorMessage = "Account created but failed to save user type. Please try again later."
                        }
                    } else {
                        print("AuthViewModel: userType \(type) written for uid=\(uid)")
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
        do {
            try Auth.auth().signOut()
            self.user = nil
        } catch {
            print("Error signing out: \(error)")
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
                return "The password is too weak. Try a longer password."
            case .wrongPassword:
                return "Invalid password. Please try again."
            case .userNotFound:
                return "No user found for that email."
            case .userDisabled:
                return "This user account has been disabled."
            case .networkError:
                return "Network error. Check your internet connection and try again."
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
