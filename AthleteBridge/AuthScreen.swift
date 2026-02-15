import SwiftUI

struct AuthScreen: View {
    @EnvironmentObject var auth: AuthViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var isLogin = true
    @State private var selectedRole: String = "CLIENT" // default for signups
    @State private var selectedAdditionalTypes: Set<String> = []

    var body: some View {
        ZStack {
            VStack(spacing: 20) {
                // App logo (load via helper that tries asset name and bundle filename)
                if let logo = appLogoImageSwiftUI() {
                    logo
                        .resizable()
                        .scaledToFit()
                        // slightly smaller max logo so it doesn't push content down on smaller screens
                        .frame(width: min(300, UIScreen.main.bounds.width * 0.7), height: min(220, UIScreen.main.bounds.width * 0.7))
                        .padding(.bottom, 8)
                } else {
                    Text("AthletesBridge")
                        .font(.system(size: 56, weight: .bold, design: .default))
                         .padding(.bottom, 8)
                }

                Text(isLogin ? "Login" : "Create An Account")
                    .font(.largeTitle)
                    .bold()

                if !isLogin {
                    // Show role toggle only during sign up
                    Picker("I am a", selection: $selectedRole) {
                        Text("Client").tag("CLIENT")
                        Text("Coach").tag("COACH")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)

                    // Additional types selection
                    VStack(alignment: .leading, spacing: 8) {
                        Text("I am also a... (optional)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        ForEach(AdditionalUserType.allCases) { type in
                            Button(action: {
                                if selectedAdditionalTypes.contains(type.rawValue) {
                                    selectedAdditionalTypes.remove(type.rawValue)
                                } else {
                                    selectedAdditionalTypes.insert(type.rawValue)
                                }
                            }) {
                                HStack(spacing: 10) {
                                    Image(systemName: selectedAdditionalTypes.contains(type.rawValue) ? "checkmark.square.fill" : "square")
                                        .foregroundColor(selectedAdditionalTypes.contains(type.rawValue) ? Color("LogoGreen") : .secondary)
                                    Image(systemName: type.iconName)
                                        .foregroundColor(type.badgeColor)
                                    Text(type.displayName)
                                        .foregroundColor(.primary)
                                    Spacer()
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal)
                }

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
                            await auth.signUp(email: trimmedEmail, password: trimmedPassword, userType: selectedRole, additionalTypes: Array(selectedAdditionalTypes))
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
            // Anchor VStack to bottom so both Login and Create Account variants share the same bottom position
            .frame(maxHeight: .infinity, alignment: .bottom)
            // increase bottom inset so content sits higher on screen and both variants align
            .padding(.bottom, 120)
             .padding(.horizontal)

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
