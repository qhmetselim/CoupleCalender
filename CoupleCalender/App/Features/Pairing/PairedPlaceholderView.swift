import SwiftUI

struct PairedPlaceholderView: View {
    let sessionStore: AppSessionStore

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.pink)
                Text("Connected")
                    .font(.title2.weight(.semibold))
                if case let .signedInPaired(profile, partner, _) = sessionStore.state {
                    Text("\(profile.displayName ?? "Sen") + \(partner.displayName ?? "Partnerin")")
                        .foregroundStyle(.secondary)
                }
                Text("Takvim özellikleri sonraki aşamalarda burada olacak.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Oturumu Kapat", role: .destructive) {
                    Task { await sessionStore.signOut() }
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .navigationTitle("CoupleCalender")
        }
    }
}
