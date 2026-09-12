import SwiftUI
import UIKit

struct PairingView: View {
    let sessionStore: AppSessionStore
    @State private var inviteCode = ""
    @FocusState private var isCodeFocused: Bool

    private var pendingInviteExpiresAt: Date? {
        if case let .signedInUnpaired(_, expiry) = sessionStore.state { return expiry }
        return nil
    }

    private var isLoading: Bool { sessionStore.state == .loading }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    inviteCard
                    joinCard
                    if let message = sessionStore.message {
                        AppStatusMessage(text: message, isError: sessionStore.messageIsError)
                    }
                    signOutButton
                }
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, AppDesign.pagePadding)
                .padding(.vertical, 28)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppDesign.pageBackground.ignoresSafeArea())
            .navigationBarHidden(true)
            .overlay {
                if isLoading {
                    ProgressView("Hazırlanıyor…")
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppDesign.smallCornerRadius, style: .continuous))
                }
            }
        }
        .tint(AppDesign.accent)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "person.2.circle")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(AppDesign.accent)
            Text("Partnerinle bağlan")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
            Text("Bir davet kodu paylaşın veya partnerinin kodunu girerek takvimlerinizi buluşturun.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var inviteCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            AppSectionHeader("Partnerini davet et", subtitle: "Tek kullanımlık kod 24 saat geçerlidir.")

            if let invite = sessionStore.latestInvite {
                InviteCodeCard(invite: invite) { code in
                    UIPasteboard.general.string = code
                    AppHaptics.selection()
                    sessionStore.clearMessage()
                }
                Button("Bekleyen daveti iptal et", role: .destructive) {
                    Task { await sessionStore.cancelPendingInvite() }
                }
                .font(.subheadline.weight(.medium))
            } else {
                Button {
                    Task { await sessionStore.createOrRefreshInvite() }
                } label: {
                    Label("Davet kodu oluştur", systemImage: "plus.circle.fill")
                }
                .buttonStyle(AppPrimaryButtonStyle())
                if let pendingInviteExpiresAt {
                    HStack(spacing: 0) {
                        Text("Bekleyen davet ")
                        Text(pendingInviteExpiresAt, style: .relative)
                            .fontWeight(.semibold)
                        Text(" içinde sona eriyor.")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .appCard()
    }

    private var joinCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            AppSectionHeader("Davet kodum var", subtitle: "Partnerinin paylaştığı kodu buraya gir.")

            TextField("ABC 123 XYZ", text: $inviteCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .textContentType(.oneTimeCode)
                .submitLabel(.go)
                .focused($isCodeFocused)
                .onChange(of: inviteCode) { _, newValue in
                    inviteCode = newValue
                        .uppercased()
                        .filter { $0.isLetter || $0.isNumber }
                }
                .onSubmit { join() }
                .appInputField()

            Button(action: join) {
                HStack(spacing: 8) {
                    if isLoading { ProgressView().tint(.white) }
                    Text("Bağlan")
                }
            }
            .buttonStyle(AppPrimaryButtonStyle())
            .disabled(inviteCode.isEmpty || isLoading)
        }
        .appCard()
    }

    private var signOutButton: some View {
        Button("Oturumu Kapat", role: .destructive) {
            Task { await sessionStore.signOut() }
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(.bordered)
    }

    private func join() {
        guard !inviteCode.isEmpty, !isLoading else { return }
        isCodeFocused = false
        Task { await sessionStore.acceptInvite(code: inviteCode) }
    }
}

private struct InviteCodeCard: View {
    let invite: PartnerInvite
    let onCopy: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(invite.code)
                .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                .tracking(3)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
                .accessibilityLabel("Davet kodu (invite.code)")

            Label("Son geçerlilik: (invite.expiresAt, style: .relative)", systemImage: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button {
                    onCopy(invite.code)
                } label: {
                    Label("Kopyala", systemImage: "doc.on.doc")
                }
                .buttonStyle(AppSecondaryButtonStyle())

                ShareLink(item: invite.code) {
                    Label("Paylaş", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(AppSecondaryButtonStyle())
            }
        }
        .padding(14)
        .background(AppDesign.fieldBackground, in: RoundedRectangle(cornerRadius: AppDesign.smallCornerRadius, style: .continuous))
    }
}
