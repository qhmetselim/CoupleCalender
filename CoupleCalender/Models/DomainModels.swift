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

    init(date: Date, calendar: Calendar = .autoupdatingCurrent) {
        let components = CalendarDay.storageCalendar(for: calendar)
            .dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            preconditionFailure("A calendar day requires year, month, and day components.")
        }
        rawValue = String(format: "%04ld-%02ld-%02ld", year, month, day)
    }

    var year: Int { Int(rawValue.prefix(4)) ?? 0 }
    var month: Int { Int(rawValue.dropFirst(5).prefix(2)) ?? 0 }
    var day: Int { Int(rawValue.dropFirst(8)) ?? 0 }

    func date(in calendar: Calendar = .autoupdatingCurrent) -> Date? {
        let storageCalendar = CalendarDay.storageCalendar(for: calendar)
        return storageCalendar.date(from: DateComponents(
            calendar: storageCalendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day
        ))
    }

    func dateComponents(in calendar: Calendar = .autoupdatingCurrent) -> DateComponents {
        let storageCalendar = CalendarDay.storageCalendar(for: calendar)
        return DateComponents(
            calendar: storageCalendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day
        )
    }

    private static func storageCalendar(for calendar: Calendar) -> Calendar {
        var storageCalendar = Calendar(identifier: .gregorian)
        storageCalendar.locale = calendar.locale
        storageCalendar.timeZone = calendar.timeZone
        return storageCalendar
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
        guard let date = components.date else { return false }
        let normalized = components.calendar?.dateComponents([.year, .month, .day], from: date)
        return normalized?.year == year && normalized?.month == month && normalized?.day == day
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

struct MemoryInsert: Codable, Sendable {
    let ownerID: UUID
    let calendarDay: CalendarDay
    let content: String

    enum CodingKeys: String, CodingKey {
        case ownerID = "owner_id"
        case calendarDay = "calendar_day"
        case content
    }
}

struct MemoryUpdate: Codable, Sendable {
    let content: String
}

enum MemoryContentValidationError: LocalizedError, Sendable {
    case empty
    case tooLong

    var errorDescription: String? {
        switch self {
        case .empty:
            "Memory content cannot be empty."
        case .tooLong:
            "Memory content cannot exceed 10,000 characters."
        }
    }
}

enum MemoryContentValidator {
    static let maximumCharacterCount = 10_000

    static func normalized(_ content: String) throws -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MemoryContentValidationError.empty }
        guard trimmed.unicodeScalars.count <= maximumCharacterCount else {
            throw MemoryContentValidationError.tooLong
        }
        return trimmed
    }

    static func characterCount(_ content: String) -> Int {
        content.unicodeScalars.count
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

    var stableID: String { "\(reactionSet):\(reactionKey)" }

    enum CodingKeys: String, CodingKey {
        case reactionSet = "reaction_set"
        case reactionKey = "reaction_key"
        case displayValue = "display_value"
        case assetName = "asset_name"
        case isActive = "is_active"
    }
}

struct MemoryReactionUpsert: Codable, Sendable {
    let memoryID: UUID
    let reactorID: UUID
    let reactionSet: String
    let reactionKey: String

    enum CodingKeys: String, CodingKey {
        case memoryID = "memory_id"
        case reactorID = "reactor_id"
        case reactionSet = "reaction_set"
        case reactionKey = "reaction_key"
    }
}

struct DayColorUpsert: Codable, Sendable {
    let calendarOwnerID: UUID
    let calendarDay: CalendarDay
    let assignedByID: UUID
    let colorKey: String

    enum CodingKeys: String, CodingKey {
        case calendarOwnerID = "calendar_owner_id"
        case calendarDay = "calendar_day"
        case assignedByID = "assigned_by_id"
        case colorKey = "color_key"
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

struct RegisterDeviceTokenParameters: Encodable, Sendable {
    let inputToken: String
    let inputEnvironment: String
    let inputAppVersion: String?

    enum CodingKeys: String, CodingKey {
        case inputToken = "input_token"
        case inputEnvironment = "input_environment"
        case inputAppVersion = "input_app_version"
    }
}

struct RemoveDeviceTokenParameters: Encodable, Sendable {
    let inputToken: String

    enum CodingKeys: String, CodingKey {
        case inputToken = "input_token"
    }
}

struct NotificationNavigationTarget: Equatable, Sendable {
    let memoryID: UUID
    let calendarDay: CalendarDay
    let calendarOwnerID: UUID

    init?(userInfo: [AnyHashable: Any]) {
        guard let type = userInfo["type"] as? String,
              type == "memory_created",
              let memoryValue = userInfo["memory_id"] as? String,
              let memoryID = UUID(uuidString: memoryValue),
              let dayValue = userInfo["calendar_day"] as? String,
              let calendarDay = try? CalendarDay(iso8601: dayValue),
              let ownerValue = userInfo["calendar_owner_id"] as? String,
              let calendarOwnerID = UUID(uuidString: ownerValue)
        else {
            return nil
        }

        self.memoryID = memoryID
        self.calendarDay = calendarDay
        self.calendarOwnerID = calendarOwnerID
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

struct EnsureMonthlyReportParameters: Encodable, Sendable {
    let inputYear: Int
    let inputMonth: Int

    enum CodingKeys: String, CodingKey {
        case inputYear = "input_year"
        case inputMonth = "input_month"
    }
}

struct EnsureYearlyReportParameters: Encodable, Sendable {
    let inputYear: Int

    enum CodingKeys: String, CodingKey {
        case inputYear = "input_year"
    }
}

struct PartnerInvite: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let code: String
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case id = "invite_id"
        case code = "invite_code"
        case expiresAt = "expires_at"
    }
}

struct PairingStatusResponse: Codable, Sendable {
    let status: String
    let coupleID: UUID?
    let partnerID: UUID?
    let pendingInviteExpiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case status
        case coupleID = "couple_id"
        case partnerID = "partner_id"
        case pendingInviteExpiresAt = "pending_invite_expires_at"
    }
}

struct PairingResultResponse: Codable, Sendable {
    let coupleID: UUID
    let partnerID: UUID

    enum CodingKeys: String, CodingKey {
        case coupleID = "couple_id"
        case partnerID = "partner_id"
    }
}

struct ProfileWrite: Codable, Sendable {
    let id: UUID
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
    }
}

struct AcceptPartnerInviteParameters: Codable, Sendable {
    let inputCode: String

    enum CodingKeys: String, CodingKey {
        case inputCode = "input_code"
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
