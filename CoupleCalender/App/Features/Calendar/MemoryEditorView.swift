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
            Form {
                Section {
                    Text(store.engine.date(for: day)
                        .formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                        .foregroundStyle(.secondary)
                    ZStack(alignment: .topLeading) {
                        if content.isEmpty {
                            Text("Bugününü veya bu güne dair bir anını yaz…")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                        }
                        TextEditor(text: $content)
                            .frame(minHeight: 220)
                    }
                }

                Section {
                    HStack {
                        Text("Karakter")
                        Spacer()
                        Text("\(characterCount) / \(MemoryContentValidator.maximumCharacterCount)")
                            .foregroundStyle(characterCount > MemoryContentValidator.maximumCharacterCount ? .red : .secondary)
                    }
                    .font(.footnote)
                }

                if let error = store.mutationError {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(memory == nil ? "Anı Ekle" : "Anıyı Düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if store.isMutating {
                            ProgressView()
                        } else {
                            Text("Kaydet")
                        }
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private func save() async {
        let didSave: Bool
        if let memory {
            didSave = await store.updateMemory(memory, content: content)
        } else {
            didSave = await store.createMemory(calendarDay: day, content: content)
        }
        if didSave {
            dismiss()
        }
    }
}
