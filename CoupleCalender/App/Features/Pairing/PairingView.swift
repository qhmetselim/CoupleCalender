import SwiftUI
import UIKit

struct PairingView: View {
    let sessionStore: AppSessionStore
    @State private var inviteCode = ""

    private var pendingInviteExpiresAt: Date? {
        if case let .signedInUnpaired(_, expiry) = sessionStore.state { return expiry }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Partnerinle güvenli bir davet kodu paylaş veya onun koduna katıl.")
                        .foregroundStyle(.secondary)
                }

                Section("Partnerini davet et") {
                    Button(sessionStore.latestInvite == nil ? "Davet kodu oluştur" : "Kodu yenile") {
                        Task { await sessionStore.createOrRefreshInvite() }
                    }
                    if let invite = sessionStore.latestInvite {
                        InviteCodeCard(invite: invite) { code in
                            UIPasteboard.general.string = code
                            sessionStore.clearMessage()
                        }
                        Button("Bekleyen daveti iptal et", role: .destructive) {
                            Task { await sessionStore.cancelPendingInvite() }
                        }
                    } else if let pendingInviteExpiresAt {
                        Text("Bekleyen davet \(pendingInviteExpiresAt, style: .relative) içinde sona eriyor. Yeni kod oluşturabilirsin.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Bir koda katıl") {
                    TextField("Davet kodu", text: $inviteCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Button("Bağlan") {
                        Task { await sessionStore.acceptInvite(code: inviteCode) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let message = sessionStore.message {
                    Section {
                        Text(message)
                            .foregroundStyle(sessionStore.messageIsError ? .red : .secondary)
                    }
                }

                Section {
                    Button("Oturumu Kapat", role: .destructive) {
                        Task { await sessionStore.signOut() }
                    }
                }
            }
            .navigationTitle("Partner bağlantısı")
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

private struct InviteCodeCard: View {
    let invite: PartnerInvite
    let onCopy: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(invite.code)
                .font(.system(.title2, design: .monospaced).weight(.semibold))
                .tracking(2)
                .textSelection(.enabled)
            Text("Son geçerlilik: \(invite.expiresAt, style: .relative)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack {
                Button("Kodu Kopyala") { onCopy(invite.code) }
                ShareLink(item: invite.code) {
                    Label("Paylaş", systemImage: "square.and.arrow.up")
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }
}
