import Foundation
import Supabase

enum SupabaseDataServiceError: Error, Equatable, Sendable {
    case notAuthenticated
}

final class SupabaseDataService {
    let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func fetchProfile(userID: UUID) async throws -> Profile? {
        try await client
            .from("profiles")
            .select()
            .eq("id", value: userID.uuidString)
            .maybeSingle()
            .execute()
            .value
    }

    func saveProfile(userID: UUID, displayName: String) async throws -> Profile {
        let payload = ProfileWrite(id: userID, displayName: displayName)
        return try await client
            .from("profiles")
            .upsert(payload, onConflict: "id")
            .select()
            .single()
            .execute()
            .value
    }

    func fetchPairingStatus() async throws -> PairingStatusResponse {
        try await client
            .rpc("get_pairing_status")
            .single()
            .execute()
            .value
    }

    func fetchCouple(id: UUID) async throws -> Couple {
        try await client
            .from("couples")
            .select()
            .eq("id", value: id.uuidString)
            .single()
            .execute()
            .value
    }

    func fetchMemories(ownerID: UUID, startDay: CalendarDay, endDay: CalendarDay) async throws -> [Memory] {
        try await client
            .from("memories")
            .select()
            .eq("owner_id", value: ownerID.uuidString)
            .gte("calendar_day", value: startDay.rawValue)
            .lte("calendar_day", value: endDay.rawValue)
            .order("calendar_day", ascending: true)
            .execute()
            .value
    }

    func fetchRecentMemories(ownerID: UUID, limit: Int = 7) async throws -> [Memory] {
        guard limit > 0 else { return [] }
        return try await client
            .from("memories")
            .select()
            .eq("owner_id", value: ownerID.uuidString)
            .order("calendar_day", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    func fetchReactionCatalog() async throws -> [ReactionCatalogItem] {
        try await client
            .from("reaction_catalog")
            .select()
            .eq("is_active", value: true)
            .order("reaction_set", ascending: true)
            .order("reaction_key", ascending: true)
            .execute()
            .value
    }

    func fetchReactions(memoryIDs: [UUID]) async throws -> [MemoryReaction] {
        guard !memoryIDs.isEmpty else { return [] }
        return try await client
            .from("memory_reactions")
            .select()
            .in("memory_id", values: memoryIDs.map(\.uuidString))
            .execute()
            .value
    }

    func fetchDayColors(ownerID: UUID, startDay: CalendarDay, endDay: CalendarDay) async throws -> [DayColor] {
        try await client
            .from("day_colors")
            .select()
            .eq("calendar_owner_id", value: ownerID.uuidString)
            .gte("calendar_day", value: startDay.rawValue)
            .lte("calendar_day", value: endDay.rawValue)
            .order("calendar_day", ascending: true)
            .execute()
            .value
    }

    func fetchMonthlyReport(year: Int, month: Int) async throws -> MonthlyReport? {
        guard client.auth.currentSession?.user.id != nil else {
            throw SupabaseDataServiceError.notAuthenticated
        }
        return try await client
            .from("monthly_reports")
            .select()
            .eq("year", value: year)
            .eq("month", value: month)
            .maybeSingle()
            .execute()
            .value
    }

    func ensureMonthlyReport(year: Int, month: Int) async throws -> MonthlyReport {
        try await client
            .rpc(
                "ensure_completed_monthly_report",
                params: EnsureMonthlyReportParameters(inputYear: year, inputMonth: month)
            )
            .single()
            .execute()
            .value
    }

    func fetchYearlyReport(year: Int) async throws -> YearlyReport? {
        guard client.auth.currentSession?.user.id != nil else {
            throw SupabaseDataServiceError.notAuthenticated
        }
        return try await client
            .from("yearly_reports")
            .select()
            .eq("year", value: year)
            .maybeSingle()
            .execute()
            .value
    }

    func ensureYearlyReport(year: Int) async throws -> YearlyReport {
        try await client
            .rpc(
                "ensure_completed_yearly_report",
                params: EnsureYearlyReportParameters(inputYear: year)
            )
            .single()
            .execute()
            .value
    }

    func upsertReaction(for memoryID: UUID, reactionSet: String, reactionKey: String) async throws -> MemoryReaction {
        guard let reactorID = client.auth.currentSession?.user.id else {
            throw SupabaseDataServiceError.notAuthenticated
        }
        let payload = MemoryReactionUpsert(
            memoryID: memoryID,
            reactorID: reactorID,
            reactionSet: reactionSet,
            reactionKey: reactionKey
        )
        return try await client
            .from("memory_reactions")
            .upsert(payload, onConflict: "memory_id,reactor_id")
            .select()
            .single()
            .execute()
            .value
    }

    func deleteReaction(for memoryID: UUID) async throws {
        guard let reactorID = client.auth.currentSession?.user.id else {
            throw SupabaseDataServiceError.notAuthenticated
        }
        _ = try await client
            .from("memory_reactions")
            .delete()
            .eq("memory_id", value: memoryID.uuidString)
            .eq("reactor_id", value: reactorID.uuidString)
            .execute()
    }

    func upsertDayColor(for memory: Memory, colorKey: String) async throws -> DayColor {
        guard let assignedByID = client.auth.currentSession?.user.id else {
            throw SupabaseDataServiceError.notAuthenticated
        }
        let payload = DayColorUpsert(
            calendarOwnerID: memory.ownerID,
            calendarDay: memory.calendarDay,
            assignedByID: assignedByID,
            colorKey: colorKey
        )
        return try await client
            .from("day_colors")
            .upsert(payload, onConflict: "calendar_owner_id,calendar_day")
            .select()
            .single()
            .execute()
            .value
    }

    func deleteDayColor(for memory: Memory) async throws {
        guard let assignedByID = client.auth.currentSession?.user.id else {
            throw SupabaseDataServiceError.notAuthenticated
        }
        _ = try await client
            .from("day_colors")
            .delete()
            .eq("calendar_owner_id", value: memory.ownerID.uuidString)
            .eq("calendar_day", value: memory.calendarDay.rawValue)
            .eq("assigned_by_id", value: assignedByID.uuidString)
            .execute()
    }

    func createMemory(calendarDay: CalendarDay, content: String) async throws -> Memory {
        guard let ownerID = client.auth.currentSession?.user.id else {
            throw SupabaseDataServiceError.notAuthenticated
        }
        let payload = MemoryInsert(
            ownerID: ownerID,
            calendarDay: calendarDay,
            content: try MemoryContentValidator.normalized(content)
        )
        return try await client
            .from("memories")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
    }

    func updateMemory(id: UUID, content: String) async throws -> Memory {
        let payload = MemoryUpdate(content: try MemoryContentValidator.normalized(content))
        return try await client
            .from("memories")
            .update(payload)
            .eq("id", value: id.uuidString)
            .select()
            .single()
            .execute()
            .value
    }

    func deleteMemory(id: UUID) async throws {
        _ = try await client
            .from("memories")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    func createOrRefreshInvite() async throws -> PartnerInvite {
        try await client
            .rpc("create_partner_invite")
            .single()
            .execute()
            .value
    }

    func acceptInvite(code: String) async throws -> PairingResultResponse {
        try await client
            .rpc("accept_partner_invite", params: AcceptPartnerInviteParameters(inputCode: code))
            .single()
            .execute()
            .value
    }

    func cancelPendingInvite() async throws {
        _ = try await client
            .rpc("cancel_partner_invite")
            .execute()
    }

    func leaveActiveCouple() async throws {
        _ = try await client
            .rpc("leave_active_couple")
            .execute()
    }

    func registerDeviceToken(
        token: String,
        environment: String,
        appVersion: String?
    ) async throws -> DeviceToken {
        try await client
            .rpc(
                "register_device_token",
                params: RegisterDeviceTokenParameters(
                    inputToken: token,
                    inputEnvironment: environment,
                    inputAppVersion: appVersion
                )
            )
            .single()
            .execute()
            .value
    }

    func removeDeviceToken(token: String) async throws {
        _ = try await client
            .rpc(
                "remove_device_token",
                params: RemoveDeviceTokenParameters(inputToken: token)
            )
            .execute()
    }
}
