import SwiftUI

struct WeekCalendarView: View {
    let store: CalendarStore

    var body: some View {
        let days = store.engine.weekDays(containing: store.selectedDate)
        let symbols = store.engine.weekdaySymbols()

        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 8) {
                ForEach(Array(days.enumerated()), id: \.element.rawValue) { index, day in
                    VStack(spacing: 8) {
                        Text(symbols[index])
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        CalendarDayCell(
                            day: day,
                            isCurrentMonth: true,
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
            }
            .padding(.vertical)
        }
    }
}
