import SwiftUI

struct MonthCalendarView: View {
    let store: CalendarStore

    var body: some View {
        let days = store.engine.monthGrid(containing: store.selectedDate)
        let symbols = store.engine.weekdaySymbols()

        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 6) {
                ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(days, id: \.rawValue) { day in
                    CalendarDayCell(
                        day: day,
                        isCurrentMonth: day.month == store.selectedDate.month && day.year == store.selectedDate.year,
                        isToday: day == store.engine.today(),
                        isSelected: day == store.selectedDate,
                        hasMemory: store.memory(on: day) != nil,
                        dayColor: store.dayColor(on: day).map { DayColorPalette.color(for: $0.colorKey) },
                        reactionDisplayValue: store.reactionDisplayValue(on: day),
                        compact: false
                    ) {
                        store.select(day)
                    }
                }
            }
            .padding(.vertical)
        }
        .padding(8)
        .appCard(padding: 0, cornerRadius: AppDesign.cornerRadius)
        .padding(.vertical, 12)
        .scrollIndicators(.hidden)
    }
}
