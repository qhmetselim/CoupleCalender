import SwiftUI

struct AuthView: View {
    let sessionStore: AppSessionStore

    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("E-posta", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Parola", text: $password)
                        .textContentType(isSignUp ? .newPassword : .password)
                }

                if let message = sessionStore.message {
                    Section {
                        Text(message)
                            .foregroundStyle(sessionStore.messageIsError ? .red : .secondary)
                    }
                }

                Section {
                    Button(isSignUp ? "Kayıt Ol" : "Giriş Yap") {
                        Task {
                            if isSignUp {
                                await sessionStore.signUp(email: email, password: password)
                            } else {
                                await sessionStore.signIn(email: email, password: password)
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(sessionStore.state == .loading)

                    Button(isSignUp ? "Zaten hesabım var" : "Yeni hesap oluştur") {
                        isSignUp.toggle()
                        sessionStore.clearMessage()
                    }
                }
            }
            .navigationTitle("CoupleCalender")
            .overlay {
                if sessionStore.state == .loading {
                    ProgressView()
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
}
