import SwiftUI

struct DayCalendarView: View {
    let store: CalendarStore

    @State private var editorRoute: MemoryEditorRoute?
    @State private var memoryToDelete: Memory?
    @State private var deleteError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.periodTitle())
                        .font(.title3.weight(.semibold))
                    Text(store.ownerName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let memory = store.memory(on: store.selectedDate) {
                    MemoryCard(memory: memory, canEdit: store.canWriteMemory) {
                        editorRoute = MemoryEditorRoute(day: memory.calendarDay, memory: memory)
                    } onDelete: {
                        memoryToDelete = memory
                    }
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical)
        }
        .overlay {
            if store.isMutating {
                ProgressView()
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .sheet(item: $editorRoute) { route in
            MemoryEditorView(store: store, day: route.day, memory: route.memory)
        }
        .alert(item: $memoryToDelete) { memory in
            Alert(
                title: Text("Anıyı silmek istiyor musun?"),
                message: Text("Bu işlem geri alınamaz."),
                primaryButton: .destructive(Text("Sil")) {
                    Task {
                        let didDelete = await store.deleteMemory(memory)
                        if !didDelete {
                            deleteError = store.mutationError ?? "Anı silinemedi."
                        }
                    }
                },
                secondaryButton: .cancel(Text("İptal"))
            )
        }
        .alert("Anı silinemedi", isPresented: deleteErrorBinding) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(deleteError ?? "Lütfen tekrar dene.")
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            ContentUnavailableView(
                "Bu güne henüz bir anı eklenmemiş.",
                systemImage: "calendar",
                description: Text(emptyStateDescription)
            )
            if store.canCreateMemoryForSelectedDate {
                Button("Anı Ekle") {
                    editorRoute = MemoryEditorRoute(day: store.selectedDate, memory: nil)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyStateDescription: String {
        if store.owner == .me, store.isFuture(store.selectedDate) {
            return "Gelecek bir güne henüz anı eklenemez."
        }
        return "Anı ekleme özelliğini kullanmak için kendi takviminde geçmiş veya bugünü seç."
    }

    private var deleteErrorBinding: Binding<Bool> {
        Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )
    }
}

private struct MemoryCard: View {
    let memory: Memory
    let canEdit: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Anı", systemImage: "book.closed")
                .font(.headline)
            Text(memory.content)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))

            if canEdit {
                HStack {
                    Button("Düzenle", action: onEdit)
                    Button("Sil", role: .destructive, action: onDelete)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
