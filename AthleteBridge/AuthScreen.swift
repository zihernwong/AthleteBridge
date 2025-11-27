import SwiftUI

struct AuthScreen: View {
    @EnvironmentObject var auth: AuthViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var isLogin = true

    var body: some View {
        ZStack {
            VStack(spacing: 20) {
                // App logo (load via helper that tries asset name and bundle filename)
                if let logo = appLogoImageSwiftUI() {
                    logo
                        .resizable()
                        .scaledToFit()
                        .frame(width: 160, height: 160)
                        .padding(.bottom, 8)
                } else {
                    Text("AthletesBridge")
                        .font(.largeTitle)
                        .bold()
                }

                Text(isLogin ? "Login" : "Sign Up")
                    .font(.largeTitle)
                    .bold()

                TextField("Email", text: $email)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
                    .disabled(auth.isLoading)

                SecureField("Password", text: $password)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
                    .disabled(auth.isLoading)

                if let err = auth.errorMessage {
                    Text(err)
                        .foregroundColor(.red)
                }

                Button(action: {
                    // Basic client-side validation before starting authentication
                    auth.errorMessage = nil
                    let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedEmail.isEmpty && !trimmedPassword.isEmpty else {
                        auth.errorMessage = "Email and password are required."
                        return
                    }
                    guard trimmedEmail.contains("@") && trimmedEmail.contains(".") else {
                        auth.errorMessage = "Please enter a valid email address."
                        return
                    }

                    Task {
                        if isLogin {
                            await auth.login(email: trimmedEmail, password: trimmedPassword)
                        } else {
                            await auth.signUp(email: trimmedEmail, password: trimmedPassword)
                        }
                    }
                }) {
                    HStack(spacing: 8) {
                        if auth.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        }
                        Text(auth.isLoading ? (isLogin ? "Logging in..." : "Signing up...") : (isLogin ? "Login" : "Sign Up"))
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .disabled(auth.isLoading || email.isEmpty || password.isEmpty)

                Button(isLogin ? "Need an account? Sign up" : "Have an account? Login") {
                    isLogin.toggle()
                }
                .padding(.top)
            }
            .padding()

            // Full-screen dim and centered spinner while authenticating
            if auth.isLoading {
                Color.black.opacity(0.25).ignoresSafeArea()
                ProgressView("Validating credentials...")
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemBackground)))
                    .shadow(radius: 6)
            }
        }
    }
}

// MARK: - Preview
struct AuthScreen_Previews: PreviewProvider {
    static var previews: some View {
        AuthScreen()
            .environmentObject(AuthViewModel())
    }
}
