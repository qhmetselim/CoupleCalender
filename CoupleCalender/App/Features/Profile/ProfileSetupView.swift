import SwiftUI

struct ProfileSetupView: View {
    let sessionStore: AppSessionStore
    @State private var displayName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Partnerin seni tanıyabilsin diye görünen adını ekle.")
                        .foregroundStyle(.secondary)
                    TextField("Görünen ad", text: $displayName)
                        .textContentType(.name)
                }

                if let message = sessionStore.message {
                    Section {
                        Text(message).foregroundStyle(.red)
                    }
                }

                Section {
                    Button("Devam Et") {
                        Task { await sessionStore.saveProfile(displayName: displayName) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Profilini oluştur")
        }
    }
}
