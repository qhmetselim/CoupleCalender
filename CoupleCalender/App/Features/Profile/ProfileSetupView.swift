import SwiftUI

struct ProfileSetupView: View {
    let sessionStore: AppSessionStore
    @State private var displayName = ""
    @FocusState private var isNameFocused: Bool

    private var canContinue: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && sessionStore.state != .loading
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 42, weight: .medium))
                        .foregroundStyle(AppDesign.accent)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Takviminde nasıl görünmek istersin?")
                            .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        Text("Partnerin seni bu adla görecek. Daha sonra istediğin zaman değiştirebilirsin.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        AppSectionHeader("Görünen ad")
                        TextField("Örneğin: Deniz", text: $displayName)
                            .textContentType(.name)
                            .submitLabel(.done)
                            .focused($isNameFocused)
                            .onSubmit { save() }
                            .appInputField()

                        Text("1–80 karakter")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let message = sessionStore.message {
                            AppStatusMessage(text: message, isError: sessionStore.messageIsError)
                        }

                        Button(action: save) {
                            HStack(spacing: 8) {
                                if sessionStore.state == .loading { ProgressView().tint(.white) }
                                Text("Devam Et")
                            }
                        }
                        .buttonStyle(AppPrimaryButtonStyle())
                        .disabled(!canContinue)
                    }
                    .appCard()
                }
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, AppDesign.pagePadding)
                .padding(.vertical, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppDesign.pageBackground.ignoresSafeArea())
            .navigationBarHidden(true)
        }
        .tint(AppDesign.accent)
    }

    private func save() {
        guard canContinue else { return }
        isNameFocused = false
        Task { await sessionStore.saveProfile(displayName: displayName) }
    }
}
