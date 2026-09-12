import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class CalendarStore {
    let profile: Profile
    let partner: Profile
    let engine: CalendarEngine

    private let dataService: SupabaseDataService
    private let realtimeCoordinator: CoupleRealtimeCoordinator
    private let profileID: UUID
    private let partnerID: UUID
    private let coupleID: UUID?
    private var memoryCache: [MemoryRangeKey: [Memory]] = [:]
    private var reactionCache: [MemoryRangeKey: [MemoryReaction]] = [:]
    private var dayColorCache: [MemoryRangeKey: [DayColor]] = [:]
    private var loadingKey: MemoryRangeKey?
    private var widgetRefreshTask: Task<Void, Never>?
    private var hasLoadedReactionCatalog = false

    var selectedDate: CalendarDay
    var mode: CalendarMode = .month
    var owner: CalendarOwner = .me
    private(set) var memories: [Memory] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var isMutating = false
    private(set) var mutationError: String?
    private(set) var reactions: [MemoryReaction] = []
    private(set) var dayColors: [DayColor] = []
    private(set) var reactionCatalog: [ReactionCatalogItem] = []
    private(set) var isLoadingReactionCatalog = false
    private(set) var isReactionMutating = false
    private(set) var isDayColorMutating = false
    private(set) var decorationError: String?

    init(
        dataService: SupabaseDataService,
        profile: Profile,
        partner: Profile,
        coupleID: UUID? = nil,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.dataService = dataService
        self.profile = profile
        self.partner = partner
        self.profileID = profile.id
        self.partnerID = partner.id
        self.coupleID = coupleID
        self.engine = CalendarEngine(calendar: calendar)
        self.realtimeCoordinator = CoupleRealtimeCoordinator(client: dataService.client)
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

    func reaction(for memory: Memory) -> MemoryReaction? {
        let expectedReactorID = memory.ownerID == profileID ? partnerID : profileID
        return reactions.first { $0.memoryID == memory.id && $0.reactorID == expectedReactorID }
    }

    func reaction(on day: CalendarDay) -> MemoryReaction? {
        guard let memory = memory(on: day) else { return nil }
        return reaction(for: memory)
    }

    func reactionDisplayValue(on day: CalendarDay) -> String? {
        guard let reaction = reaction(on: day) else { return nil }
        return reactionCatalog.first {
            $0.reactionSet == reaction.reactionSet && $0.reactionKey == reaction.reactionKey
        }?.displayValue ?? reaction.reactionKey
    }

    func dayColor(on day: CalendarDay) -> DayColor? {
        guard memory(on: day) != nil else { return nil }
        return dayColors.first { $0.calendarOwnerID == currentOwnerID && $0.calendarDay == day }
    }

    var canInteractWithDecoration: Bool {
        owner == .partner
    }

    func select(_ day: CalendarDay) {
        selectedDate = day
    }

    func openNotificationTarget(_ target: NotificationNavigationTarget) {
        guard target.calendarOwnerID == partnerID else { return }
        owner = .partner
        mode = .day
        selectedDate = target.calendarDay
    }

    func openWidgetTarget(_ target: WidgetDeepLinkTarget) {
        guard let day = try? CalendarDay(iso8601: target.calendarDay) else { return }
        owner = .partner
        mode = .day
        selectedDate = day
    }

    func startRealtime(coupleID: UUID) async {
        await realtimeCoordinator.start(coupleID: coupleID, store: self)
    }

    func refreshPartnerWidgetSnapshot() async {
        guard let coupleID,
              dataService.client.auth.currentSession?.user.id == profileID
        else { return }

        do {
            let recentMemories = try await dataService.fetchRecentMemories(
                ownerID: partnerID,
                limit: PartnerWidgetSnapshotBuilder.memoryLimit
            )
            let recentMemoryIDs = recentMemories.map(\.id)
            let fetchedReactions = try await dataService.fetchReactions(memoryIDs: recentMemoryIDs)
            let fetchedDayColors: [DayColor]
            if let firstDay = recentMemories.map(\.calendarDay.rawValue).min(),
               let lastDay = recentMemories.map(\.calendarDay.rawValue).max(),
               let startDay = try? CalendarDay(iso8601: firstDay),
               let endDay = try? CalendarDay(iso8601: lastDay) {
                fetchedDayColors = try await dataService.fetchDayColors(
                    ownerID: partnerID,
                    startDay: startDay,
                    endDay: endDay
                )
            } else {
                fetchedDayColors = []
            }

            await loadReactionCatalogIfNeeded()
            try Task.checkCancellation()
            let snapshot = PartnerWidgetSnapshotBuilder.make(
                userID: profileID,
                coupleID: coupleID,
                partnerID: partnerID,
                partnerDisplayName: partner.displayName ?? "Partnerim",
                memories: recentMemories,
                reactions: fetchedReactions,
                dayColors: fetchedDayColors,
                reactionCatalog: reactionCatalog
            )
            PartnerWidgetSnapshotWriter.saveIfChanged(snapshot)
        } catch is CancellationError {
            return
        } catch {
            // A failed reconciliation must not erase the last valid private snapshot.
        }
    }

    func stopRealtime() async {
        await realtimeCoordinator.stop()
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

    func loadReactionCatalogIfNeeded() async {
        guard !hasLoadedReactionCatalog else { return }
        isLoadingReactionCatalog = true
        defer { isLoadingReactionCatalog = false }
        do {
            let catalog = try await dataService.fetchReactionCatalog()
            try Task.checkCancellation()
            reactionCatalog = catalog
            hasLoadedReactionCatalog = true
            decorationError = nil
        } catch is CancellationError {
            return
        } catch {
            decorationError = "Tepkiler yüklenemedi. Lütfen tekrar dene."
        }
    }

    func setReaction(_ item: ReactionCatalogItem, for memory: Memory) async -> Bool {
        guard owner == .partner, memory.ownerID == partnerID else {
            decorationError = "Bu anıya tepki verme yetkin yok."
            return false
        }
        guard item.isActive else { return false }
        isReactionMutating = true
        decorationError = nil
        defer { isReactionMutating = false }
        do {
            let reaction = try await dataService.upsertReaction(
                for: memory.id,
                reactionSet: item.reactionSet,
                reactionKey: item.reactionKey
            )
            applyReactionUpsert(reaction)
            schedulePartnerWidgetSnapshotRefresh()
            return true
        } catch {
            decorationError = AppErrorMessage.reaction(error)
            return false
        }
    }

    func removeReaction(for memory: Memory) async -> Bool {
        guard owner == .partner, memory.ownerID == partnerID else {
            decorationError = "Bu anının tepkisini değiştirme yetkin yok."
            return false
        }
        isReactionMutating = true
        decorationError = nil
        defer { isReactionMutating = false }
        do {
            try await dataService.deleteReaction(for: memory.id)
            applyReactionRemoval(memoryID: memory.id, reactorID: profileID)
            schedulePartnerWidgetSnapshotRefresh()
            return true
        } catch {
            decorationError = AppErrorMessage.reaction(error)
            return false
        }
    }

    func setDayColor(_ colorKey: String, for memory: Memory) async -> Bool {
        guard owner == .partner, memory.ownerID == partnerID else {
            decorationError = "Bu güne renk verme yetkin yok."
            return false
        }
        isDayColorMutating = true
        decorationError = nil
        defer { isDayColorMutating = false }
        do {
            let color = try await dataService.upsertDayColor(for: memory, colorKey: colorKey)
            applyDayColorUpsert(color)
            schedulePartnerWidgetSnapshotRefresh()
            return true
        } catch {
            decorationError = AppErrorMessage.dayColor(error)
            return false
        }
    }

    func removeDayColor(for memory: Memory) async -> Bool {
        guard owner == .partner, memory.ownerID == partnerID else {
            decorationError = "Bu günün rengini değiştirme yetkin yok."
            return false
        }
        isDayColorMutating = true
        decorationError = nil
        defer { isDayColorMutating = false }
        do {
            try await dataService.deleteDayColor(for: memory)
            applyDayColorRemoval(ownerID: memory.ownerID, day: memory.calendarDay, assignedByID: profileID)
            schedulePartnerWidgetSnapshotRefresh()
            return true
        } catch {
            decorationError = AppErrorMessage.dayColor(error)
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
            if let cachedReactions = reactionCache[key] {
                reactions = cachedReactions
            } else {
                reactions = []
            }
            if let cachedDayColors = dayColorCache[key] {
                dayColors = cachedDayColors
            } else {
                dayColors = []
            }
            errorMessage = nil
            await loadReactionCatalogIfNeeded()
            if reactionCache[key] == nil || dayColorCache[key] == nil {
                await loadDecorations(for: key, memoryIDs: cached.map(\.id))
            }
            return
        }

        if forceReload {
            memoryCache[key] = nil
            reactionCache[key] = nil
            dayColorCache[key] = nil
        }

        memories = []
        reactions = []
        dayColors = []
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
            await loadReactionCatalogIfNeeded()
            await loadDecorations(for: key, memoryIDs: fetched.map(\.id))
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
        mutateCachedReactions { _, cached in cached.filter { $0.memoryID != memory.id } }
        mutateCachedDayColors { key, cached in
            guard key.ownerID == memory.ownerID else { return cached }
            return cached.filter { $0.calendarDay != memory.calendarDay }
        }
        memories.removeAll { $0.id == memory.id }
        reactions.removeAll { $0.memoryID == memory.id }
        dayColors.removeAll { $0.calendarOwnerID == memory.ownerID && $0.calendarDay == memory.calendarDay }
        mutationError = nil
    }

    private func loadDecorations(for key: MemoryRangeKey, memoryIDs: [UUID]) async {
        do {
            let fetched = try await dataService.fetchReactions(memoryIDs: memoryIDs)
            reactionCache[key] = fetched
            if currentMemoryRangeKey == key { reactions = fetched }
        } catch is CancellationError {
            return
        } catch {
            decorationError = "Tepkiler yüklenemedi. Lütfen tekrar dene."
        }

        do {
            let fetched = try await dataService.fetchDayColors(
                ownerID: key.ownerID,
                startDay: key.startDay,
                endDay: key.endDay
            )
            dayColorCache[key] = fetched
            if currentMemoryRangeKey == key { dayColors = fetched }
        } catch is CancellationError {
            return
        } catch {
            decorationError = "Gün renkleri yüklenemedi. Lütfen tekrar dene."
        }
    }

    private func mutateCachedMemories(_ mutation: (MemoryRangeKey, [Memory]) -> [Memory]) {
        let keys = Array(memoryCache.keys)
        for key in keys {
            guard let cached = memoryCache[key] else { continue }
            memoryCache[key] = mutation(key, cached).sorted { $0.calendarDay.rawValue < $1.calendarDay.rawValue }
        }
    }

    private func mutateCachedReactions(_ mutation: (MemoryRangeKey, [MemoryReaction]) -> [MemoryReaction]) {
        let keys = Array(reactionCache.keys)
        for key in keys {
            guard let cached = reactionCache[key] else { continue }
            reactionCache[key] = mutation(key, cached)
        }
    }

    private func mutateCachedDayColors(_ mutation: (MemoryRangeKey, [DayColor]) -> [DayColor]) {
        let keys = Array(dayColorCache.keys)
        for key in keys {
            guard let cached = dayColorCache[key] else { continue }
            dayColorCache[key] = mutation(key, cached)
        }
    }

    func applyReactionUpsert(_ reaction: MemoryReaction) {
        mutateCachedReactions { key, cached in
            guard key.ownerID == currentOwnerID,
                  memoryCache[key]?.contains(where: { $0.id == reaction.memoryID }) == true else { return cached }
            return upserting(reaction, into: cached)
        }
        if memories.contains(where: { $0.id == reaction.memoryID }) {
            reactions = upserting(reaction, into: reactions)
        }
    }

    func applyReactionRemoval(memoryID: UUID, reactorID: UUID) {
        mutateCachedReactions { _, cached in
            cached.filter { !($0.memoryID == memoryID && $0.reactorID == reactorID) }
        }
        reactions.removeAll { $0.memoryID == memoryID && $0.reactorID == reactorID }
    }

    func applyDayColorUpsert(_ color: DayColor) {
        mutateCachedDayColors { key, cached in
            guard key.ownerID == color.calendarOwnerID, key.contains(color.calendarDay) else { return cached }
            return upserting(color, into: cached)
        }
        if currentOwnerID == color.calendarOwnerID, currentMemoryRangeKey.contains(color.calendarDay) {
            dayColors = upserting(color, into: dayColors)
        }
    }

    func applyDayColorRemoval(ownerID: UUID, day: CalendarDay, assignedByID: UUID) {
        mutateCachedDayColors { _, cached in
            cached.filter { !($0.calendarOwnerID == ownerID && $0.calendarDay == day && $0.assignedByID == assignedByID) }
        }
        dayColors.removeAll { $0.calendarOwnerID == ownerID && $0.calendarDay == day && $0.assignedByID == assignedByID }
    }

    func applyRealtimeChange(_ change: CoupleRealtimeChange) {
        switch change {
        case let .memoryUpsert(memory):
            guard isKnownCalendarOwner(memory.ownerID) else { return }
            applyUpdatedMemory(memory)
            if memory.ownerID == partnerID { schedulePartnerWidgetSnapshotRefresh() }
        case let .memoryDelete(memory):
            guard isKnownCalendarOwner(memory.ownerID) else { return }
            applyDeletedMemory(memory)
            if memory.ownerID == partnerID { schedulePartnerWidgetSnapshotRefresh() }
        case let .reactionUpsert(reaction):
            guard isAuthorizedReaction(reaction) else { return }
            applyReactionUpsert(reaction)
            schedulePartnerWidgetSnapshotRefresh()
        case let .reactionDelete(reaction):
            guard isAuthorizedReaction(reaction) else { return }
            applyReactionRemoval(memoryID: reaction.memoryID, reactorID: reaction.reactorID)
            schedulePartnerWidgetSnapshotRefresh()
        case let .dayColorUpsert(color):
            guard isAuthorizedDayColor(color) else { return }
            applyDayColorUpsert(color)
            schedulePartnerWidgetSnapshotRefresh()
        case let .dayColorDelete(color):
            guard isAuthorizedDayColor(color) else { return }
            applyDayColorRemoval(
                ownerID: color.calendarOwnerID,
                day: color.calendarDay,
                assignedByID: color.assignedByID
            )
            schedulePartnerWidgetSnapshotRefresh()
        }
    }

    private func schedulePartnerWidgetSnapshotRefresh() {
        widgetRefreshTask?.cancel()
        widgetRefreshTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                await self?.refreshPartnerWidgetSnapshot()
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    private func upserting(_ reaction: MemoryReaction, into reactions: [MemoryReaction]) -> [MemoryReaction] {
        var result = reactions
        if let index = result.firstIndex(where: { $0.memoryID == reaction.memoryID && $0.reactorID == reaction.reactorID }) {
            result[index] = reaction
        } else {
            result.append(reaction)
        }
        return result
    }

    private func upserting(_ color: DayColor, into colors: [DayColor]) -> [DayColor] {
        var result = colors
        if let index = result.firstIndex(where: { $0.calendarOwnerID == color.calendarOwnerID && $0.calendarDay == color.calendarDay }) {
            result[index] = color
        } else {
            result.append(color)
        }
        return result
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

    private func isKnownCalendarOwner(_ ownerID: UUID) -> Bool {
        ownerID == profileID || ownerID == partnerID
    }

    private func isAuthorizedReaction(_ reaction: MemoryReaction) -> Bool {
        guard let memory = memoryCache.values.flatMap({ $0 }).first(where: { $0.id == reaction.memoryID })
                ?? memories.first(where: { $0.id == reaction.memoryID })
        else {
            return false
        }

        let expectedReactorID = memory.ownerID == profileID ? partnerID : profileID
        return isKnownCalendarOwner(memory.ownerID) && reaction.reactorID == expectedReactorID
    }

    private func isAuthorizedDayColor(_ color: DayColor) -> Bool {
        guard isKnownCalendarOwner(color.calendarOwnerID) else { return false }
        let expectedAssignerID = color.calendarOwnerID == profileID ? partnerID : profileID
        return color.assignedByID == expectedAssignerID
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
