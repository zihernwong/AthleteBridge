import Foundation
import FirebaseAuth

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
    func signUp(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false } // ensure we always clear loading
        
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            self.user = result.user
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
                return "The password is too weak."
            case .wrongPassword:
                return "Incorrect password."
            case .userNotFound:
                return "No user found for that email."
            case .userDisabled:
                return "This user account has been disabled."
            case .networkError:
                return "Network error. Check your internet connection."
            case .internalError:
                // internalError is generic — include underlying description if available
                if let detail = nsError.userInfo[NSLocalizedDescriptionKey] as? String {
                    return "Internal error: \(detail)"
                } else {
                    return "An internal error has occurred. Check console logs for details."
                }
            default:
                // Fall back to localized description including the AuthErrorCode for easier debugging
                return "\(nsError.localizedDescription) (\(authCode))"
            }
        }

        // Fallback: return localized description
        return nsError.localizedDescription
    }
}
