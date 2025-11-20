import SwiftUI

struct AuthScreen: View {
    @EnvironmentObject var auth: AuthViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var isLogin = true

    var body: some View {
        VStack(spacing: 20) {
            Text(isLogin ? "Login" : "Sign Up")
                .font(.largeTitle)
                .bold()

            TextField("Email", text: $email)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)

            SecureField("Password", text: $password)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)

            if let err = auth.errorMessage {
                Text(err)
                    .foregroundColor(.red)
            }

            Button(isLogin ? "Login" : "Sign Up") {
                Task {
                    if isLogin {
                        await auth.login(email: email, password: password)
                    } else {
                        await auth.signUp(email: email, password: password)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)

            Button(isLogin ? "Need an account? Sign up" : "Have an account? Login") {
                isLogin.toggle()
            }
            .padding(.top)
        }
        .padding()
    }
}

// MARK: - Preview
struct AuthScreen_Previews: PreviewProvider {
    static var previews: some View {
        AuthScreen()
            .environmentObject(AuthViewModel())
    }
}

