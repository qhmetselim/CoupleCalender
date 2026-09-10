import Foundation

struct CalendarEngine: Sendable {
    let calendar: Calendar

    init(calendar: Calendar = .autoupdatingCurrent) {
        self.calendar = calendar
    }

    func today() -> CalendarDay {
        CalendarDay(date: Date(), calendar: calendar)
    }

    func date(for day: CalendarDay) -> Date {
        guard let date = day.date(in: calendar) else {
            preconditionFailure("CalendarDay contains an invalid date: \(day.rawValue)")
        }
        return date
    }

    func day(for date: Date) -> CalendarDay {
        CalendarDay(date: date, calendar: calendar)
    }

    func adding(_ component: Calendar.Component, value: Int, to day: CalendarDay) -> CalendarDay {
        let date = calendar.date(byAdding: component, value: value, to: date(for: day)) ?? date(for: day)
        return self.day(for: date)
    }

    func weekDays(containing day: CalendarDay) -> [CalendarDay] {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date(for: day)) else {
            return [day]
        }
        return days(from: interval.start, through: interval.end.addingTimeInterval(-1))
    }

    func monthGrid(containing day: CalendarDay) -> [CalendarDay] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: date(for: day)),
              let firstWeek = calendar.dateInterval(of: .weekOfYear, for: monthInterval.start),
              let lastMonthDate = calendar.date(byAdding: .second, value: -1, to: monthInterval.end),
              let lastWeek = calendar.dateInterval(of: .weekOfYear, for: lastMonthDate)
        else {
            return [day]
        }
        return days(from: firstWeek.start, through: lastWeek.end.addingTimeInterval(-1))
    }

    func monthDays(containing day: CalendarDay) -> [CalendarDay] {
        guard let interval = calendar.dateInterval(of: .month, for: date(for: day)) else {
            return [day]
        }
        return days(from: interval.start, through: interval.end.addingTimeInterval(-1))
    }

    func yearMonths(containing day: CalendarDay) -> [CalendarDay] {
        let year = day.year
        return (1...12).compactMap { month in
            guard let date = CalendarDay(
                rawValue: String(format: "%04ld-%02ld-01", year, month)
            ).date(in: calendar) else {
                return nil
            }
            return self.day(for: date)
        }
    }

    func visibleRange(for day: CalendarDay, mode: CalendarMode) -> (start: CalendarDay, end: CalendarDay) {
        switch mode {
        case .day:
            return (day, day)
        case .week:
            let days = weekDays(containing: day)
            return (days.first ?? day, days.last ?? day)
        case .month:
            let days = monthGrid(containing: day)
            return (days.first ?? day, days.last ?? day)
        case .year:
            return (
                CalendarDay(rawValue: String(format: "%04ld-01-01", day.year)),
                CalendarDay(rawValue: String(format: "%04ld-12-31", day.year))
            )
        }
    }

    func weekdaySymbols() -> [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let firstWeekdayIndex = max(0, min(symbols.count - 1, calendar.firstWeekday - 1))
        return Array(symbols[firstWeekdayIndex...]) + Array(symbols[..<firstWeekdayIndex])
    }

    private func days(from start: Date, through end: Date) -> [CalendarDay] {
        var result: [CalendarDay] = []
        var current = start
        while current <= end {
            result.append(day(for: current))
            guard let next = calendar.date(byAdding: .day, value: 1, to: current), next > current else {
                break
            }
            current = next
        }
        return result
    }
}

enum CalendarMode: String, CaseIterable, Identifiable, Sendable {
    case day
    case week
    case month
    case year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: "Gün"
        case .week: "Hafta"
        case .month: "Ay"
        case .year: "Yıl"
        }
    }
}

enum CalendarOwner: String, CaseIterable, Identifiable, Sendable {
    case me
    case partner

    var id: String { rawValue }

    var title: String {
        switch self {
        case .me: "Benim Takvimim"
        case .partner: "Partnerimin Takvimi"
        }
    }
}
