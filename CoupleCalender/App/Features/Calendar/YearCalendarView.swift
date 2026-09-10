import SwiftUI

struct YearCalendarView: View {
    let store: CalendarStore

    var body: some View {
        let months = store.engine.yearMonths(containing: store.selectedDate)

        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 14) {
                ForEach(months, id: \.rawValue) { month in
                    MiniMonthView(month: month, store: store)
                }
            }
            .padding(.vertical)
        }
    }
}

private struct MiniMonthView: View {
    let month: CalendarDay
    let store: CalendarStore

    var body: some View {
        Button {
            store.showMonth(containing: month)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(store.engine.date(for: month).formatted(.dateTime.month(.wide)))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)

                let days = store.engine.monthGrid(containing: month)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 7), spacing: 2) {
                    ForEach(days, id: \.rawValue) { day in
                        Text(String(day.day))
                            .font(.system(size: 8))
                            .foregroundStyle(day.month == month.month ? .primary : .tertiary)
                            .frame(maxWidth: .infinity, minHeight: 10)
                            .overlay(alignment: .bottom) {
                                if store.memory(on: day) != nil {
                                    Circle()
                                        .fill(.tint)
                                        .frame(width: 2, height: 2)
                                }
                            }
                    }
                }
            }
            .padding(7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(month.year)-\(month.month) ayını aç")
    }
}
