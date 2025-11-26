import SwiftUI

/// A replacement Auth screen that shows a loading spinner overlay tied to AuthViewModel.isLoading.
struct AuthScreenLoading: View {
    @EnvironmentObject var auth: AuthViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var isLogin = true

    var body: some View {
        ZStack {
            VStack(spacing: 20) {
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
                    Task {
                        if isLogin {
                            await auth.login(email: email, password: password)
                        } else {
                            await auth.signUp(email: email, password: password)
                        }
                    }
                }) {
                    HStack(spacing: 8) {
                        if auth.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        }
                        Text(isLogin ? "Login" : "Sign Up")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .disabled(auth.isLoading)

                Button(isLogin ? "Need an account? Sign up" : "Have an account? Login") {
                    isLogin.toggle()
                }
                .padding(.top)
                .disabled(auth.isLoading)
            }
            .padding()
            .disabled(auth.isLoading)

            if auth.isLoading {
                ZStack {
                    Color.black.opacity(0.25).edgesIgnoringSafeArea(.all)
                    ProgressView("Signing in...")
                        .padding(20)
                        .background(Color(UIColor.systemBackground))
                        .cornerRadius(12)
                }
                .transition(.opacity)
            }
        }
    }
}

struct AuthScreenLoading_Previews: PreviewProvider {
    static var previews: some View {
        AuthScreenLoading()
            .environmentObject(AuthViewModel())
    }
}
