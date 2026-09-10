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
}
