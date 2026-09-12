import SwiftUI

struct DayCalendarView: View {
    let store: CalendarStore

    @State private var editorRoute: MemoryEditorRoute?
    @State private var memoryToDelete: Memory?
    @State private var deleteError: String?
    @State private var reactionPickerMemory: Memory?
    @State private var colorPickerMemory: Memory?
    @State private var isDeleting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                dayHeader

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
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 14)
        }
        .scrollIndicators(.hidden)
        .overlay(alignment: .bottom) {
            if isDeleting {
                ProgressView("Anı siliniyor…")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 12)
            }
        }
        .sheet(item: $editorRoute) { route in
            MemoryEditorView(store: store, day: route.day, memory: route.memory)
                .presentationDetents([.large])
        }
        .sheet(item: $reactionPickerMemory) { memory in
            ReactionPickerView(memory: memory, store: store)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $colorPickerMemory) { memory in
            DayColorPickerView(memory: memory, store: store)
                .presentationDetents([.medium, .large])
        }
        .alert(item: $memoryToDelete) { memory in
            Alert(
                title: Text("Anıyı silmek istiyor musun?"),
                message: Text("Bu işlem geri alınamaz."),
                primaryButton: .destructive(Text("Sil")) {
                    Task { await delete(memory) }
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

    private var dayHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: store.owner == .me ? "person.fill" : "person.2.fill")
                    .foregroundStyle(AppDesign.accent)
                    .frame(width: 36, height: 36)
                    .background(AppDesign.accent.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.ownerName)
                        .font(.subheadline.weight(.semibold))
                    Text(store.periodTitle())
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .lineLimit(2)
                }
            }
            Rectangle()
                .fill(.quaternary)
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: store.owner == .partner ? "eye" : "square.and.pencil")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(AppDesign.accent)
                .frame(width: 64, height: 64)
                .background(AppDesign.accent.opacity(0.10), in: Circle())
            Text("Bu güne henüz bir anı eklenmemiş.")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(emptyStateDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if store.canCreateMemoryForSelectedDate {
                Button {
                    editorRoute = MemoryEditorRoute(day: store.selectedDate, memory: nil)
                } label: {
                    Label("Anı Ekle", systemImage: "plus")
                }
                .buttonStyle(AppPrimaryButtonStyle())
                .frame(maxWidth: 260)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
        .appCard(padding: 22)
    }

    private var emptyStateDescription: String {
        if store.owner == .me, store.isFuture(store.selectedDate) {
            return "Bu gün henüz yaşanmadı."
        }
        if store.owner == .partner {
            return "Partnerin bu gün için bir anı eklediğinde burada görebilirsin."
        }
        return "Bugününü veya bu güne dair küçük bir anını yazabilirsin."
    }

    private var deleteErrorBinding: Binding<Bool> {
        Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )
    }

    @ViewBuilder
    private func decorationSection(for memory: Memory) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            AppSectionHeader(
                store.owner == .partner ? "Bu güne eşlik et" : "Partnerinin dokunuşu",
                subtitle: store.owner == .partner ? "Anıya bir tepki veya renk bırak." : nil
            )

            if let reaction = store.reaction(for: memory) {
                HStack(spacing: 12) {
                    Text(reactionDisplayValue(for: reaction))
                        .font(.system(size: 34))
                        .accessibilityLabel("\(reaction.reactionKey) tepkisi")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.owner == .partner ? "Tepkin" : "Partnerinin tepkisi")
                            .font(.subheadline.weight(.semibold))
                        Text(store.owner == .partner ? "İstersen değiştirebilirsin." : "Bu tepki yalnızca görüntülenebilir.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            } else if store.owner == .me {
                Label("Henüz tepki bırakılmadı.", systemImage: "face.smiling")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Label("Bir tepki bırak.", systemImage: "face.smiling")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let color = store.dayColor(on: memory.calendarDay) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(DayColorPalette.color(for: color.colorKey))
                        .frame(width: 20, height: 20)
                        .overlay(Circle().stroke(.primary.opacity(0.15), lineWidth: 1))
                    Text("Günün rengi: \(DayColorPalette.label(for: color.colorKey))")
                        .font(.subheadline.weight(.medium))
                }
                .accessibilityElement(children: .combine)
            }

            if store.canInteractWithDecoration {
                HStack(spacing: 10) {
                    Button {
                        reactionPickerMemory = memory
                    } label: {
                        Label(store.reaction(for: memory) == nil ? "Tepki bırak" : "Tepkiyi değiştir", systemImage: "face.smiling")
                    }
                    .buttonStyle(AppSecondaryButtonStyle())
                    .disabled(store.isReactionMutating || store.isDayColorMutating)

                    Button {
                        colorPickerMemory = memory
                    } label: {
                        Label(store.dayColor(on: memory.calendarDay) == nil ? "Renk ekle" : "Rengi değiştir", systemImage: "paintpalette")
                    }
                    .buttonStyle(AppSecondaryButtonStyle())
                    .disabled(store.isReactionMutating || store.isDayColorMutating)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .appCard(padding: 16)
    }

    private func reactionDisplayValue(for reaction: MemoryReaction) -> String {
        store.reactionCatalog.first {
            $0.reactionSet == reaction.reactionSet && $0.reactionKey == reaction.reactionKey
        }?.displayValue ?? reaction.reactionKey
    }

    private func delete(_ memory: Memory) async {
        isDeleting = true
        let didDelete = await store.deleteMemory(memory)
        isDeleting = false
        if didDelete {
            AppHaptics.success()
        } else {
            deleteError = store.mutationError ?? "Anı silinemedi."
        }
    }
}

private struct MemoryCard: View {
    let memory: Memory
    let canEdit: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Anı", systemImage: "book.closed.fill")
                    .font(.headline)
                Spacer()
                if !canEdit {
                    Text("Salt okunur")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            Text(memory.content)
                .font(.body)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(AppDesign.fieldBackground, in: RoundedRectangle(cornerRadius: AppDesign.smallCornerRadius, style: .continuous))

            if canEdit {
                HStack(spacing: 10) {
                    Button("Düzenle", action: onEdit)
                        .buttonStyle(AppSecondaryButtonStyle())
                    Button("Sil", role: .destructive, action: onDelete)
                        .buttonStyle(.bordered)
                }
            }
        }
        .appCard(padding: 16)
    }
}

private struct ReactionPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let memory: Memory
    let store: CalendarStore

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Bir tepki seç")
                            .font(.title3.weight(.bold))
                        Text("Bu anı için yalnızca bir tepkin olabilir.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if store.isLoadingReactionCatalog && store.reactionCatalog.isEmpty {
                        ProgressView("Tepkiler yükleniyor…")
                            .frame(maxWidth: .infinity, minHeight: 180)
                    } else if store.reactionCatalog.isEmpty {
                        ContentUnavailableView(
                            "Tepkiler yüklenemedi",
                            systemImage: "face.smiling",
                            description: Text("Bağlantını kontrol edip tekrar dene.")
                        )
                    } else {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(store.reactionCatalog, id: \.stableID) { item in
                                Button {
                                    Task {
                                        if await store.setReaction(item, for: memory) {
                                            AppHaptics.selection()
                                            dismiss()
                                        }
                                    }
                                } label: {
                                    Text(item.displayValue)
                                        .font(.system(size: 32))
                                        .frame(maxWidth: .infinity, minHeight: 62)
                                        .background(isSelected(item) ? AppDesign.accent.opacity(0.14) : AppDesign.fieldBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        .overlay {
                                            if isSelected(item) {
                                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                    .strokeBorder(AppDesign.accent, lineWidth: 2)
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                                .disabled(store.isReactionMutating)
                                .accessibilityLabel("\(item.reactionKey) tepkisi")
                                .accessibilityAddTraits(isSelected(item) ? .isSelected : [])
                            }
                        }

                        if store.reaction(for: memory) != nil {
                            Button("Tepkiyi Kaldır", role: .destructive) {
                                Task {
                                    if await store.removeReaction(for: memory) {
                                        AppHaptics.warning()
                                        dismiss()
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .buttonStyle(.bordered)
                            .disabled(store.isReactionMutating)
                        }

                        if let error = store.decorationError {
                            AppStatusMessage(text: error, isError: true)
                        }
                    }
                }
                .padding(AppDesign.pagePadding)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("Tepki")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
        .tint(AppDesign.accent)
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

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Günün rengi")
                            .font(.title3.weight(.bold))
                        Text("Takvimde bu günü sakin bir vurgu ile işaretle.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(DayColorPalette.options) { option in
                            let isSelected = store.dayColor(on: memory.calendarDay)?.colorKey == option.key
                            DayColorOptionButton(
                                option: option,
                                isSelected: isSelected,
                                isDisabled: store.isDayColorMutating
                            ) {
                                Task {
                                    if await store.setDayColor(option.key, for: memory) {
                                        AppHaptics.selection()
                                        dismiss()
                                    }
                                }
                            }
                        }
                    }

                    if store.dayColor(on: memory.calendarDay) != nil {
                        Button("Rengi Kaldır", role: .destructive) {
                            Task {
                                if await store.removeDayColor(for: memory) {
                                    AppHaptics.warning()
                                    dismiss()
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.bordered)
                        .disabled(store.isDayColorMutating)
                    }

                    if let error = store.decorationError {
                        AppStatusMessage(text: error, isError: true)
                    }
                }
                .padding(AppDesign.pagePadding)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("Günün rengi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
        .tint(AppDesign.accent)
    }
}

private struct DayColorOptionButton: View {
    let option: DayColorPalette.Option
    let isSelected: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Circle()
                    .fill(option.color)
                    .frame(width: 46, height: 46)
                    .overlay {
                        Circle().stroke(isSelected ? Color.primary : Color.primary.opacity(0.12), lineWidth: isSelected ? 3 : 1)
                    }
                    .overlay {
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.primary)
                        }
                    }
                Text(option.label)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 76)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel("\(option.label) rengi")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
