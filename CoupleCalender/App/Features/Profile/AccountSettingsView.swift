import SwiftUI
import UIKit
import UserNotifications

struct AccountSettingsView: View {
    let sessionStore: AppSessionStore
    let profile: Profile
    let partner: Profile

    @Environment(\.dismiss) private var dismiss
    @State private var isLeavingCouple = false
    @State private var isEditingProfile = false
    @State private var editedDisplayName = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    profileCard
                    connectionCard
                    notificationCard
                    dangerZone
                }
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, AppDesign.pagePadding)
                .padding(.vertical, 24)
            }
            .background(AppDesign.pageBackground.ignoresSafeArea())
            .navigationTitle("Hesap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
        .tint(AppDesign.accent)
        .confirmationDialog(
            "Bağlantıyı sonlandırmak ister misin?",
            isPresented: $isLeavingCouple,
            titleVisibility: .visible
        ) {
            Button("Bağlantıyı Sonlandır", role: .destructive) {
                Task { await sessionStore.leaveActiveCouple() }
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Anıların silinmez; ancak birbirinizin takvimlerine erişiminiz sona erer.")
        }
    }

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            AppSectionHeader("Profil")
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(AppDesign.accent)
                VStack(alignment: .leading, spacing: 3) {
                    if isEditingProfile {
                        TextField("Görünen ad", text: $editedDisplayName)
                            .textContentType(.name)
                            .appInputField()
                    } else {
                        Text(profile.displayName ?? "Sen")
                            .font(.headline)
                        Text("Takvimindeki görünen ad")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }

            if isEditingProfile {
                HStack(spacing: 10) {
                    Button("Vazgeç") {
                        isEditingProfile = false
                    }
                    .buttonStyle(AppSecondaryButtonStyle())
                    Button("Kaydet") {
                        isEditingProfile = false
                        Task { await sessionStore.saveProfile(displayName: editedDisplayName) }
                    }
                    .buttonStyle(AppSecondaryButtonStyle())
                    .disabled(editedDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else {
                Button("Görünen adı düzenle") {
                    editedDisplayName = profile.displayName ?? ""
                    isEditingProfile = true
                }
                .font(.subheadline.weight(.medium))
            }

            if let message = sessionStore.message {
                AppStatusMessage(text: message, isError: sessionStore.messageIsError)
            }
        }
        .appCard()
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            AppSectionHeader("Bağlantı", subtitle: "Aktif partnerin")
            HStack(spacing: 12) {
                Image(systemName: "person.2.fill")
                    .font(.title3)
                    .foregroundStyle(AppDesign.accent)
                    .frame(width: 40, height: 40)
                    .background(AppDesign.accent.opacity(0.12), in: Circle())
                Text(partner.displayName ?? "Partnerim")
                    .font(.headline)
                Spacer()
                Label("Bağlı", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }
        }
        .appCard()
    }

    private var notificationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppSectionHeader("Bildirimler", subtitle: "Yeni anılardan haberdar ol.")
            HStack {
                Label(notificationStatusText, systemImage: notificationStatusIcon)
                    .foregroundStyle(.secondary)
                Spacer()
                if sessionStore.pushNotifications.authorizationStatus == .denied {
                    Button("Ayarlar") { openSettings() }
                        .buttonStyle(AppSecondaryButtonStyle())
                } else if sessionStore.pushNotifications.authorizationStatus == .notDetermined {
                    Button("Aç") {
                        Task { await sessionStore.pushNotifications.requestAuthorization() }
                    }
                    .buttonStyle(AppSecondaryButtonStyle())
                }
            }
        }
        .appCard()
    }

    private var dangerZone: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppSectionHeader("Oturum")
            Button("Bağlantıyı sonlandır", role: .destructive) {
                isLeavingCouple = true
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.bordered)

            Button("Oturumu Kapat", role: .destructive) {
                Task { await sessionStore.signOut() }
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.bordered)
        }
        .appCard()
    }

    private var notificationStatusText: String {
        switch sessionStore.pushNotifications.authorizationStatus {
        case .authorized, .provisional, .ephemeral: "Açık"
        case .denied: "Kapalı"
        case .notDetermined: "Henüz seçilmedi"
        @unknown default: "Bilinmiyor"
        }
    }

    private var notificationStatusIcon: String {
        sessionStore.pushNotifications.authorizationStatus == .denied ? "bell.slash" : "bell"
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
