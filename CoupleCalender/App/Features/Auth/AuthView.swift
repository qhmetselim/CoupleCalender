import SwiftUI

struct AuthView: View {
    let sessionStore: AppSessionStore

    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case password
    }

    private var isLoading: Bool { sessionStore.state == .loading }
    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && password.count >= 8 && !isLoading
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    branding
                    introduction
                    formCard
                    modeSwitch
                }
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, AppDesign.pagePadding)
                .padding(.vertical, 28)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppDesign.pageBackground.ignoresSafeArea())
            .navigationBarHidden(true)
        }
        .tint(AppDesign.accent)
    }

    private var branding: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(AppDesign.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("CoupleCalender")
                    .font(.title3.weight(.bold))
                Text("Birlikte geçen günlere yer aç.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isSignUp ? "Kendi takvimini oluşturmaya başla." : "Takvimine geri dön.")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            Text(isSignUp
                 ? "Günün küçük anılarını güvenle sakla ve partnerinle paylaş."
                 : "Partnerinle paylaştığın anılar seni bekliyor.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            AppSectionHeader(isSignUp ? "Hesap oluştur" : "Giriş yap")

            TextField("E-posta", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .focused($focusedField, equals: .email)
                .onSubmit { focusedField = .password }
                .appInputField()

            SecureField("Parola", text: $password)
                .textContentType(isSignUp ? .newPassword : .password)
                .submitLabel(.go)
                .focused($focusedField, equals: .password)
                .onSubmit { submit() }
                .appInputField()

            if isSignUp {
                Text("Parolan en az 8 karakter olmalı.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let message = sessionStore.message {
                AppStatusMessage(text: message, isError: sessionStore.messageIsError)
            }

            Button(action: submit) {
                HStack(spacing: 8) {
                    if isLoading { ProgressView().tint(.white) }
                    Text(isSignUp ? "Kayıt Ol" : "Giriş Yap")
                }
            }
            .buttonStyle(AppPrimaryButtonStyle())
            .disabled(!canSubmit)
            .accessibilityHint(isLoading ? "İşlem sürüyor" : "")
        }
        .appCard()
    }

    private var modeSwitch: some View {
        Button {
            isSignUp.toggle()
            sessionStore.clearMessage()
            focusedField = nil
        } label: {
            HStack(spacing: 4) {
                Text(isSignUp ? "Zaten hesabın var mı?" : "Henüz hesabın yok mu?")
                    .foregroundStyle(.secondary)
                Text(isSignUp ? "Giriş yap" : "Hesap oluştur")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppDesign.accent)
    }

    private func submit() {
        guard canSubmit else { return }
        focusedField = nil
        Task {
            if isSignUp {
                await sessionStore.signUp(email: email, password: password)
            } else {
                await sessionStore.signIn(email: email, password: password)
            }
        }
    }
}
