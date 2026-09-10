import Foundation

struct CalendarDay: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(iso8601 value: String) throws {
        guard Self.isValid(value) else {
            throw CalendarDayError.invalidValue(value)
        }
        rawValue = value
    }

    private static func isValid(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count == 10,
              bytes[4] == 45,
              bytes[7] == 45,
              let year = Int(value.prefix(4)),
              let month = Int(value.dropFirst(5).prefix(2)),
              let day = Int(value.dropFirst(8))
        else {
            return false
        }

        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        return components.date != nil
    }
}

enum CalendarDayError: LocalizedError {
    case invalidValue(String)

    var errorDescription: String? {
        switch self {
        case let .invalidValue(value):
            "Expected a calendar day in YYYY-MM-DD format, got \(value)."
        }
    }
}

struct Profile: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var displayName: String?
    var avatarURL: String?
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct Couple: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let memberAID: UUID
    let memberBID: UUID?
    let status: Status
    let createdAt: Date
    var updatedAt: Date

    enum Status: String, Codable, Sendable {
        case pending
        case active
        case ended
    }

    enum CodingKeys: String, CodingKey {
        case id
        case memberAID = "member_a_id"
        case memberBID = "member_b_id"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct Memory: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let ownerID: UUID
    let calendarDay: CalendarDay
    var content: String
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case ownerID = "owner_id"
        case calendarDay = "calendar_day"
        case content
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct MemoryReaction: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let memoryID: UUID
    let reactorID: UUID
    var reactionSet: String
    var reactionKey: String
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case memoryID = "memory_id"
        case reactorID = "reactor_id"
        case reactionSet = "reaction_set"
        case reactionKey = "reaction_key"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct ReactionCatalogItem: Codable, Hashable, Sendable {
    let reactionSet: String
    let reactionKey: String
    let displayValue: String
    let assetName: String?
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case reactionSet = "reaction_set"
        case reactionKey = "reaction_key"
        case displayValue = "display_value"
        case assetName = "asset_name"
        case isActive = "is_active"
    }
}

struct DayColor: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let calendarOwnerID: UUID
    let calendarDay: CalendarDay
    let assignedByID: UUID
    var colorKey: String
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case calendarOwnerID = "calendar_owner_id"
        case calendarDay = "calendar_day"
        case assignedByID = "assigned_by_id"
        case colorKey = "color_key"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct DeviceToken: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    var token: String
    var platform: String
    var environment: String
    var appVersion: String?
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case token
        case platform
        case environment
        case appVersion = "app_version"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct MonthlyReport: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    let year: Int
    let month: Int
    var metrics: [String: JSONValue]
    let generatedAt: Date?
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case year
        case month
        case metrics
        case generatedAt = "generated_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct YearlyReport: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    let year: Int
    var metrics: [String: JSONValue]
    let generatedAt: Date?
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case year
        case metrics
        case generatedAt = "generated_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum JSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            self = .array(try container.decode([JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}
