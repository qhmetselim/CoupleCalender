import SwiftUI

struct DayCalendarView: View {
    let store: CalendarStore

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
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Anı", systemImage: "book.closed")
                            .font(.headline)
                        Text(memory.content)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    }
                } else {
                    ContentUnavailableView(
                        "Bu güne henüz bir anı eklenmemiş.",
                        systemImage: "calendar",
                        description: Text("Anı ekleme özelliği sonraki aşamada gelecek.")
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical)
        }
    }
}
