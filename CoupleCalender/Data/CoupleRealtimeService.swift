import Foundation
import Supabase

enum CoupleRealtimeChange: Sendable, Hashable {
    case memoryUpsert(Memory)
    case memoryDelete(Memory)
    case reactionUpsert(MemoryReaction)
    case reactionDelete(MemoryReaction)
    case dayColorUpsert(DayColor)
    case dayColorDelete(DayColor)
}

private struct RealtimeChangePayload: Decodable, Sendable {
    let schema: String?
    let table: String?
    let eventType: String?
    let newRecord: JSONObject?
    let oldRecord: JSONObject?

    enum CodingKeys: String, CodingKey {
        case schema
        case table
        case eventType
        case newRecord = "new"
        case oldRecord = "old"
    }
}

enum CoupleRealtimeChangeParser {
    static func parse(_ payload: JSONObject) -> CoupleRealtimeChange? {
        do {
            let messagePayload = payload["payload"]?.objectValue ?? payload
            let change = try AnyJSON.object(messagePayload).decode(as: RealtimeChangePayload.self)
            guard change.schema == "public", let table = change.table else { return nil }

            switch (table, change.eventType?.uppercased()) {
            case ("memories", "INSERT"), ("memories", "UPDATE"):
                guard let record = change.newRecord else { return nil }
                return .memoryUpsert(try decode(record))
            case ("memories", "DELETE"):
                guard let record = change.oldRecord else { return nil }
                return .memoryDelete(try decode(record))
            case ("memory_reactions", "INSERT"), ("memory_reactions", "UPDATE"):
                guard let record = change.newRecord else { return nil }
                return .reactionUpsert(try decode(record))
            case ("memory_reactions", "DELETE"):
                guard let record = change.oldRecord else { return nil }
                return .reactionDelete(try decode(record))
            case ("day_colors", "INSERT"), ("day_colors", "UPDATE"):
                guard let record = change.newRecord else { return nil }
                return .dayColorUpsert(try decode(record))
            case ("day_colors", "DELETE"):
                guard let record = change.oldRecord else { return nil }
                return .dayColorDelete(try decode(record))
            default:
                return nil
            }
        } catch {
            return nil
        }
    }

    private static func decode<T: Decodable>(_ record: JSONObject) throws -> T {
        try AnyJSON.object(record).decode(as: T.self)
    }
}

@MainActor
final class CoupleRealtimeCoordinator {
    private let client: SupabaseClient
    private var channel: RealtimeChannelV2?
    private var streamTasks: [Task<Void, Never>] = []
    private var subscribedCoupleID: UUID?

    init(client: SupabaseClient) {
        self.client = client
    }

    func start(coupleID: UUID, store: CalendarStore) async {
        if subscribedCoupleID == coupleID, channel != nil { return }

        await stop()

        let channel = client.channel("couple:\(coupleID.uuidString.lowercased())") {
            $0.isPrivate = true
        }
        self.channel = channel
        self.subscribedCoupleID = coupleID

        for event in ["INSERT", "UPDATE", "DELETE"] {
            let stream = channel.broadcastStream(event: event)
            let task = Task { @MainActor [weak store] in
                for await payload in stream {
                    guard let store else { return }
                    guard let change = CoupleRealtimeChangeParser.parse(payload) else { continue }
                    store.applyRealtimeChange(change)
                }
            }
            streamTasks.append(task)
        }

        do {
            try await channel.subscribeWithError()
        } catch {
            streamTasks.forEach { $0.cancel() }
            streamTasks.removeAll()
            await client.removeChannel(channel)
            self.channel = nil
            subscribedCoupleID = nil
        }
    }

    func stop() async {
        streamTasks.forEach { $0.cancel() }
        streamTasks.removeAll()
        guard let channel else {
            subscribedCoupleID = nil
            return
        }
        await client.removeChannel(channel)
        self.channel = nil
        subscribedCoupleID = nil
    }
}
