import SwiftUI

struct MemoryEditorRoute: Identifiable {
    let id = UUID()
    let day: CalendarDay
    let memory: Memory?
}

struct MemoryEditorView: View {
    let store: CalendarStore
    let day: CalendarDay
    let memory: Memory?

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isEditorFocused: Bool
    @State private var content: String

    init(store: CalendarStore, day: CalendarDay, memory: Memory?) {
        self.store = store
        self.day = day
        self.memory = memory
        _content = State(initialValue: memory?.content ?? "")
    }

    private var characterCount: Int {
        MemoryContentValidator.characterCount(content)
    }

    private var canSave: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && characterCount <= MemoryContentValidator.maximumCharacterCount
            && !store.isMutating
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    dateContext
                    writingSurface
                    characterCounter

                    if let error = store.mutationError {
                        AppStatusMessage(text: error, isError: true)
                    }
                }
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, AppDesign.pagePadding)
                .padding(.vertical, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppDesign.pageBackground.ignoresSafeArea())
            .navigationTitle(memory == nil ? "Anı ekle" : "Anıyı düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        HStack(spacing: 6) {
                            if store.isMutating { ProgressView().controlSize(.small) }
                            Text("Kaydet")
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Bitti") { isEditorFocused = false }
                }
            }
        }
        .tint(AppDesign.accent)
        .task {
            isEditorFocused = memory == nil
        }
    }

    private var dateContext: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(memory == nil ? "Bugünden bir iz bırak" : "Bu anıyı güncelle")
                .font(.system(.title2, design: .rounded).weight(.bold))
            Label(
                store.engine.date(for: day).formatted(.dateTime.weekday(.wide).day().month(.wide).year()),
                systemImage: "calendar"
            )
            .font(.subheadline.weight(.medium))
            .foregroundStyle(AppDesign.accent)
        }
    }

    private var writingSurface: some View {
        ZStack(alignment: .topLeading) {
            if content.isEmpty {
                Text("Bugününü veya bu güne dair küçük bir anını yaz…")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 18)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $content)
                .font(.body)
                .lineSpacing(5)
                .focused($isEditorFocused)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 260)
                .padding(12)
        }
        .background(AppDesign.cardBackground, in: RoundedRectangle(cornerRadius: AppDesign.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppDesign.cornerRadius, style: .continuous)
                .strokeBorder(isEditorFocused ? AppDesign.accent.opacity(0.55) : .primary.opacity(0.06), lineWidth: isEditorFocused ? 1.5 : 0.5)
        }
    }

    private var characterCounter: some View {
        HStack {
            Text(characterCount > MemoryContentValidator.maximumCharacterCount ? "Karakter sınırı aşıldı" : "Anının uzunluğu")
            Spacer()
            Text("\(characterCount) / \(MemoryContentValidator.maximumCharacterCount)")
                .monospacedDigit()
                .fontWeight(.medium)
        }
        .font(.caption)
        .foregroundStyle(characterCount > MemoryContentValidator.maximumCharacterCount ? .red : .secondary)
        .accessibilityElement(children: .combine)
    }

    private func save() {
        guard canSave else { return }
        Task {
            let didSave: Bool
            if let memory {
                didSave = await store.updateMemory(memory, content: content)
            } else {
                didSave = await store.createMemory(calendarDay: day, content: content)
            }
            if didSave {
                AppHaptics.success()
                dismiss()
            }
        }
    }
}
