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
    private(set) var isMutating = false
    private(set) var mutationError: String?

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

    var canWriteMemory: Bool { owner == .me }

    var canCreateMemoryForSelectedDate: Bool {
        canWriteMemory && memory(on: selectedDate) == nil && !isFuture(selectedDate)
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

    func isFuture(_ day: CalendarDay) -> Bool {
        engine.date(for: day) > Date()
    }

    func createMemory(calendarDay: CalendarDay, content: String) async -> Bool {
        guard canWriteMemory else {
            mutationError = "Partnerinin takvimine anı ekleyemezsin."
            return false
        }
        guard !isFuture(calendarDay) else {
            mutationError = "Gelecek bir güne anı ekleyemezsin."
            return false
        }
        guard memory(on: calendarDay) == nil else {
            mutationError = "Bu gün için zaten bir anı bulunuyor."
            return false
        }

        mutationError = nil
        isMutating = true
        defer { isMutating = false }
        do {
            let memory = try await dataService.createMemory(calendarDay: calendarDay, content: content)
            guard memory.ownerID == profileID, memory.calendarDay == calendarDay else {
                mutationError = "Anı kaydedilemedi."
                return false
            }
            applyCreatedMemory(memory)
            return true
        } catch {
            mutationError = AppErrorMessage.memory(error)
            if isDuplicateMemoryError(error) {
                await loadVisiblePeriod(forceReload: true)
            }
            return false
        }
    }

    func updateMemory(_ memory: Memory, content: String) async -> Bool {
        guard canWriteMemory, memory.ownerID == profileID else {
            mutationError = "Bu anı üzerinde değişiklik yapma yetkin yok."
            return false
        }

        mutationError = nil
        isMutating = true
        defer { isMutating = false }
        do {
            let updatedMemory = try await dataService.updateMemory(id: memory.id, content: content)
            guard updatedMemory.ownerID == profileID,
                  updatedMemory.calendarDay == memory.calendarDay else {
                mutationError = "Anının sahibi veya tarihi değiştirilemez."
                return false
            }
            applyUpdatedMemory(updatedMemory)
            return true
        } catch {
            mutationError = AppErrorMessage.memory(error)
            return false
        }
    }

    func deleteMemory(_ memory: Memory) async -> Bool {
        guard canWriteMemory, memory.ownerID == profileID else {
            mutationError = "Bu anıyı silme yetkin yok."
            return false
        }

        mutationError = nil
        isMutating = true
        defer { isMutating = false }
        do {
            try await dataService.deleteMemory(id: memory.id)
            applyDeletedMemory(memory)
            return true
        } catch {
            mutationError = AppErrorMessage.memory(error)
            return false
        }
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

        memories = []
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

    private func applyCreatedMemory(_ memory: Memory) {
        mutateCachedMemories { key, cached in
            guard key.ownerID == memory.ownerID, key.contains(memory.calendarDay) else { return cached }
            return upserting(memory, into: cached)
        }
        if currentOwnerID == memory.ownerID, currentMemoryRangeKey.contains(memory.calendarDay) {
            memories = upserting(memory, into: memories)
        }
        mutationError = nil
    }

    private func applyUpdatedMemory(_ memory: Memory) {
        mutateCachedMemories { key, cached in
            guard key.ownerID == memory.ownerID else { return cached }
            guard cached.contains(where: { $0.id == memory.id }) || key.contains(memory.calendarDay) else {
                return cached
            }
            return upserting(memory, into: cached)
        }
        if currentOwnerID == memory.ownerID,
           memories.contains(where: { $0.id == memory.id }) || currentMemoryRangeKey.contains(memory.calendarDay) {
            memories = upserting(memory, into: memories)
        }
        mutationError = nil
    }

    private func applyDeletedMemory(_ memory: Memory) {
        mutateCachedMemories { _, cached in cached.filter { $0.id != memory.id } }
        memories.removeAll { $0.id == memory.id }
        mutationError = nil
    }

    private func mutateCachedMemories(_ mutation: (MemoryRangeKey, [Memory]) -> [Memory]) {
        let keys = Array(memoryCache.keys)
        for key in keys {
            guard let cached = memoryCache[key] else { continue }
            memoryCache[key] = mutation(key, cached).sorted { $0.calendarDay.rawValue < $1.calendarDay.rawValue }
        }
    }

    private func upserting(_ memory: Memory, into memories: [Memory]) -> [Memory] {
        var result = memories
        if let index = result.firstIndex(where: { $0.id == memory.id || $0.calendarDay == memory.calendarDay }) {
            result[index] = memory
        } else {
            result.append(memory)
        }
        return result.sorted { $0.calendarDay.rawValue < $1.calendarDay.rawValue }
    }

    private func isDuplicateMemoryError(_ error: Error) -> Bool {
        let value = error.localizedDescription.lowercased()
        return value.contains("duplicate key") || value.contains("memories_owner_id_calendar_day_key")
    }
}

private struct MemoryRangeKey: Hashable, Sendable {
    let ownerID: UUID
    let startDay: CalendarDay
    let endDay: CalendarDay

    func contains(_ day: CalendarDay) -> Bool {
        startDay.rawValue <= day.rawValue && day.rawValue <= endDay.rawValue
    }
}
