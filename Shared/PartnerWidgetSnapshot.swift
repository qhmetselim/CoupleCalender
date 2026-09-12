import Foundation

enum CoupleCalenderWidgetConfiguration {
    static let appGroupIdentifier = "group.asa.CoupleCalender"
    static let snapshotKey = "partner_widget_snapshot_v1"
    static let widgetKind = "CoupleCalenderWidget"
}

struct PartnerWidgetSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let generatedAt: Date
    let userID: UUID
    let coupleID: UUID
    let partnerID: UUID
    let partnerDisplayName: String
    let memories: [PartnerWidgetMemory]
}

struct PartnerWidgetMemory: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let calendarDay: String
    let contentPreview: String
    let reactionSet: String?
    let reactionKey: String?
    let reactionDisplayValue: String?
    let dayColorKey: String?
}

struct PartnerWidgetSnapshotStore: Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults? = UserDefaults(suiteName: CoupleCalenderWidgetConfiguration.appGroupIdentifier)) {
        self.defaults = defaults ?? .standard
    }

    func read() -> PartnerWidgetSnapshot? {
        guard let data = defaults.data(forKey: CoupleCalenderWidgetConfiguration.snapshotKey) else {
            return nil
        }

        guard let snapshot = try? JSONDecoder().decode(PartnerWidgetSnapshot.self, from: data),
              snapshot.schemaVersion == PartnerWidgetSnapshot.currentSchemaVersion
        else {
            return nil
        }
        return snapshot
    }

    func save(_ snapshot: PartnerWidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: CoupleCalenderWidgetConfiguration.snapshotKey)
    }

    func clear() {
        defaults.removeObject(forKey: CoupleCalenderWidgetConfiguration.snapshotKey)
    }
}

enum PartnerWidgetContentPreview {
    static let maximumScalarCount = 280

    static func truncated(_ content: String) -> String {
        let scalars = content.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars
        guard scalars.count > maximumScalarCount else {
            return String(scalars)
        }
        return String(scalars.prefix(maximumScalarCount)) + "…"
    }
}

struct WidgetDeepLinkTarget: Equatable, Sendable {
    let calendarDay: String
    let memoryID: UUID?
}

enum WidgetDeepLink {
    static let scheme = "couplecalender"

    static func url(calendarDay: String, memoryID: UUID?) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "partner"
        components.path = "/day/\(calendarDay)"
        if let memoryID {
            components.queryItems = [URLQueryItem(name: "memory_id", value: memoryID.uuidString)]
        }
        return components.url
    }

    static func parse(_ url: URL) -> WidgetDeepLinkTarget? {
        guard url.scheme?.lowercased() == scheme,
              url.host?.lowercased() == "partner"
        else { return nil }

        let path = url.pathComponents
        guard path.count == 3,
              path[1].lowercased() == "day",
              isValidCalendarDay(path[2])
        else { return nil }

        let memoryID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "memory_id" })?
            .value
            .flatMap(UUID.init(uuidString:))

        return WidgetDeepLinkTarget(calendarDay: path[2], memoryID: memoryID)
    }

    private static func isValidCalendarDay(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count == 10,
              bytes[4] == 45,
              bytes[7] == 45,
              let year = Int(value.prefix(4)),
              let month = Int(value.dropFirst(5).prefix(2)),
              let day = Int(value.dropFirst(8))
        else { return false }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        guard let date = calendar.date(from: components) else { return false }
        let normalized = calendar.dateComponents([.year, .month, .day], from: date)
        return normalized.year == year && normalized.month == month && normalized.day == day
    }
}
