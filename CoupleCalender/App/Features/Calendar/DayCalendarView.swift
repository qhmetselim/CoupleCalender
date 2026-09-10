import SwiftUI

struct DayCalendarView: View {
    let store: CalendarStore

    @State private var editorRoute: MemoryEditorRoute?
    @State private var memoryToDelete: Memory?
    @State private var deleteError: String?
    @State private var reactionPickerMemory: Memory?
    @State private var colorPickerMemory: Memory?

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
                    decorationSection(for: memory)
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
        .sheet(item: $reactionPickerMemory) { memory in
            ReactionPickerView(memory: memory, store: store)
        }
        .sheet(item: $colorPickerMemory) { memory in
            DayColorPickerView(memory: memory, store: store)
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

    @ViewBuilder
    private func decorationSection(for memory: Memory) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let reaction = store.reaction(for: memory) {
                HStack(spacing: 8) {
                    Text(store.owner == .partner ? "Tepkin" : "Partnerinin tepkisi")
                        .font(.subheadline.weight(.semibold))
                    Text(reactionDisplayValue(for: reaction))
                        .font(.title2)
                        .accessibilityLabel("\(reaction.reactionKey) tepkisi")
                }
            } else if store.owner == .me {
                Text("Henüz bir tepki yok")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let color = store.dayColor(on: memory.calendarDay) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(DayColorPalette.color(for: color.colorKey))
                        .frame(width: 18, height: 18)
                    Text("Günün rengi: (DayColorPalette.label(for: color.colorKey))")
                        .font(.subheadline)
                }
            }

            if store.canInteractWithDecoration {
                HStack {
                    Button {
                        reactionPickerMemory = memory
                    } label: {
                        Label(store.reaction(for: memory) == nil ? "Tepki seç" : "Tepkiyi değiştir", systemImage: "face.smiling")
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.isReactionMutating || store.isDayColorMutating)

                    Button {
                        colorPickerMemory = memory
                    } label: {
                        Label(store.dayColor(on: memory.calendarDay) == nil ? "Günün rengi" : "Rengi değiştir", systemImage: "paintpalette")
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.isReactionMutating || store.isDayColorMutating)
                }
            }
        }
        .padding(.top, 4)
    }

    private func reactionDisplayValue(for reaction: MemoryReaction) -> String {
        store.reactionCatalog.first {
            $0.reactionSet == reaction.reactionSet && $0.reactionKey == reaction.reactionKey
        }?.displayValue ?? reaction.reactionKey
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

private struct ReactionPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let memory: Memory
    let store: CalendarStore

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        NavigationStack {
            VStack {
                if store.isLoadingReactionCatalog && store.reactionCatalog.isEmpty {
                    ProgressView("Tepkiler yükleniyor…")
                } else if store.reactionCatalog.isEmpty {
                    ContentUnavailableView(
                        "Tepkiler yüklenemedi",
                        systemImage: "face.smiling",
                        description: Text(store.decorationError ?? "Lütfen tekrar dene.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(store.reactionCatalog, id: \.stableID) { item in
                                Button {
                                    Task {
                                        if await store.setReaction(item, for: memory) { dismiss() }
                                    }
                                } label: {
                                    Text(item.displayValue)
                                        .font(.largeTitle)
                                        .frame(maxWidth: .infinity, minHeight: 54)
                                        .background(isSelected(item) ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 12))
                                        .overlay {
                                            if isSelected(item) {
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(.tint, lineWidth: 2)
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                                .disabled(store.isReactionMutating)
                                .accessibilityLabel("\(item.reactionKey) tepkisi \(item.displayValue)")
                            }
                        }
                        .padding()

                        if store.reaction(for: memory) != nil {
                            Button("Tepkiyi Kaldır", role: .destructive) {
                                Task {
                                    if await store.removeReaction(for: memory) { dismiss() }
                                }
                            }
                            .disabled(store.isReactionMutating)
                            .padding(.bottom)
                        }

                        if let error = store.decorationError {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .padding(.horizontal)
                        }
                    }
                }
            }
            .navigationTitle("Tepki seç")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
        .task { await store.loadReactionCatalogIfNeeded() }
    }

    private func isSelected(_ item: ReactionCatalogItem) -> Bool {
        guard let current = store.reaction(for: memory) else { return false }
        return current.reactionSet == item.reactionSet && current.reactionKey == item.reactionKey
    }
}

private struct DayColorPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let memory: Memory
    let store: CalendarStore

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 4)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(DayColorPalette.options) { option in
                        Button {
                            Task {
                                if await store.setDayColor(option.key, for: memory) { dismiss() }
                            }
                        } label: {
                            VStack(spacing: 6) {
                                Circle()
                                    .fill(option.color)
                                    .frame(width: 42, height: 42)
                                    .overlay {
                                        if store.dayColor(on: memory.calendarDay)?.colorKey == option.key {
                                            Circle().stroke(.primary, lineWidth: 3).padding(2)
                                        }
                                    }
                                Text(option.label)
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(store.isDayColorMutating)
                        .accessibilityLabel(option.label)
                        .accessibilityAddTraits(store.dayColor(on: memory.calendarDay)?.colorKey == option.key ? .isSelected : [])
                    }
                }
                .padding()

                if store.dayColor(on: memory.calendarDay) != nil {
                    Button("Rengi Kaldır", role: .destructive) {
                        Task {
                            if await store.removeDayColor(for: memory) { dismiss() }
                        }
                    }
                    .disabled(store.isDayColorMutating)
                }

                if let error = store.decorationError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding()
                }
            }
            .navigationTitle("Günün rengi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }
}
