import Foundation
import Supabase

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
