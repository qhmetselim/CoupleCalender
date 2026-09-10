import Foundation
import Observation

@MainActor
@Observable
final class CalendarStore {
    let profile: Profile
    let partner: Profile
    let engine: CalendarEngine

    private let dataService: SupabaseDataService
    private let profileID: UUID
    private let partnerID: UUID
    private var memoryCache: [MemoryRangeKey: [Memory]] = [:]
    private var loadingKey: MemoryRangeKey?

    var selectedDate: CalendarDay
    var mode: CalendarMode = .month
    var owner: CalendarOwner = .me
    private(set) var memories: [Memory] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    init(
        dataService: SupabaseDataService,
        profile: Profile,
        partner: Profile,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.dataService = dataService
        self.profile = profile
        self.partner = partner
        self.profileID = profile.id
        self.partnerID = partner.id
        self.engine = CalendarEngine(calendar: calendar)
        self.selectedDate = CalendarDay(date: Date(), calendar: calendar)
    }

    var ownerName: String {
        owner == .me ? (profile.displayName ?? "Benim") : (partner.displayName ?? "Partnerim")
    }

    var currentOwnerID: UUID {
        owner == .me ? profileID : partnerID
    }

    var visibleRange: (start: CalendarDay, end: CalendarDay) {
        engine.visibleRange(for: selectedDate, mode: mode)
    }

    var visiblePeriodKey: String {
        let range = visibleRange
        return [
            currentOwnerID.uuidString,
            mode.rawValue,
            range.start.rawValue,
            range.end.rawValue
        ].joined(separator: "|")
    }

    var memoryByDay: [CalendarDay: Memory] {
        Dictionary(uniqueKeysWithValues: memories.map { ($0.calendarDay, $0) })
    }

    func memory(on day: CalendarDay) -> Memory? {
        memoryByDay[day]
    }

    func select(_ day: CalendarDay) {
        selectedDate = day
    }

    func showMonth(containing day: CalendarDay) {
        selectedDate = day
        mode = .month
    }

    func moveToPreviousPeriod() {
        selectedDate = engine.adding(componentForNavigation, value: -1, to: selectedDate)
    }

    func moveToNextPeriod() {
        selectedDate = engine.adding(componentForNavigation, value: 1, to: selectedDate)
    }

    func moveToToday() {
        selectedDate = engine.today()
    }

    func loadVisiblePeriod(forceReload: Bool = false) async {
        let range = visibleRange
        let key = MemoryRangeKey(
            ownerID: currentOwnerID,
            startDay: range.start,
            endDay: range.end
        )

        if !forceReload, let cached = memoryCache[key] {
            memories = cached
            errorMessage = nil
            return
        }

        if forceReload {
            memoryCache[key] = nil
        }

        loadingKey = key
        isLoading = true
        errorMessage = nil
        defer {
            if loadingKey == key {
                loadingKey = nil
                isLoading = false
            }
        }

        do {
            let fetched = try await dataService.fetchMemories(
                ownerID: currentOwnerID,
                startDay: range.start,
                endDay: range.end
            )
            try Task.checkCancellation()
            memoryCache[key] = fetched
            if currentMemoryRangeKey == key {
                memories = fetched
            }
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled {
                errorMessage = "Takvim verileri yüklenemedi. Lütfen tekrar dene."
            }
        }
    }

    func reloadCurrentPeriod() async {
        await loadVisiblePeriod(forceReload: true)
    }

    func periodTitle() -> String {
        switch mode {
        case .day:
            return engine.date(for: selectedDate)
                .formatted(.dateTime.weekday(.wide).day().month(.wide).year())
        case .week:
            let days = engine.weekDays(containing: selectedDate)
            guard let first = days.first, let last = days.last else { return "" }
            return "\(engine.date(for: first).formatted(.dateTime.day().month(.wide).year())) – \(engine.date(for: last).formatted(.dateTime.day().month(.wide).year()))"
        case .month:
            return engine.date(for: selectedDate).formatted(.dateTime.month(.wide).year())
        case .year:
            return String(selectedDate.year)
        }
    }

    private var currentMemoryRangeKey: MemoryRangeKey {
        let range = visibleRange
        return MemoryRangeKey(ownerID: currentOwnerID, startDay: range.start, endDay: range.end)
    }

    private var componentForNavigation: Calendar.Component {
        switch mode {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
    }
}

private struct MemoryRangeKey: Hashable, Sendable {
    let ownerID: UUID
    let startDay: CalendarDay
    let endDay: CalendarDay
}
