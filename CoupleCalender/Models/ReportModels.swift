import Foundation

struct ReportReactionMetric: Codable, Hashable, Sendable, Identifiable {
    let reactionSet: String
    let reactionKey: String
    let displayValue: String?
    let count: Int

    var id: String { "\(reactionSet):\(reactionKey)" }

    enum CodingKeys: String, CodingKey {
        case reactionSet = "reaction_set"
        case reactionKey = "reaction_key"
        case displayValue = "display_value"
        case count
    }
}

struct ReportColorMetric: Codable, Hashable, Sendable, Identifiable {
    let colorKey: String
    let count: Int

    var id: String { colorKey }

    enum CodingKeys: String, CodingKey {
        case colorKey = "color_key"
        case count
    }
}

struct ReportActiveWeekMetric: Codable, Hashable, Sendable {
    let weekStart: CalendarDay
    let weekEnd: CalendarDay
    let memoryCount: Int

    enum CodingKeys: String, CodingKey {
        case weekStart = "week_start"
        case weekEnd = "week_end"
        case memoryCount = "memory_count"
    }
}

struct MonthlyReportMetricsV1: Codable, Hashable, Sendable {
    let schemaVersion: Int
    let memoryCount: Int
    let reactedMemoryCount: Int
    let reactionCount: Int
    let reactionCoverage: Double
    let reactionFrequency: [ReportReactionMetric]
    let mostUsedReaction: ReportReactionMetric?
    let dayColorFrequency: [ReportColorMetric]
    let mostUsedColor: ReportColorMetric?
    let memoryDayCount: Int
    let activeWeek: ReportActiveWeekMetric?
    let longestMemoryCharacterCount: Int
    let averageMemoryCharacterCount: Double

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case memoryCount = "memory_count"
        case reactedMemoryCount = "reacted_memory_count"
        case reactionCount = "reaction_count"
        case reactionCoverage = "reaction_coverage"
        case reactionFrequency = "reaction_frequency"
        case mostUsedReaction = "most_used_reaction"
        case dayColorFrequency = "day_color_frequency"
        case mostUsedColor = "most_used_color"
        case memoryDayCount = "memory_day_count"
        case activeWeek = "active_week"
        case longestMemoryCharacterCount = "longest_memory_character_count"
        case averageMemoryCharacterCount = "average_memory_character_count"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        memoryCount = try container.decodeIfPresent(Int.self, forKey: .memoryCount) ?? 0
        reactedMemoryCount = try container.decodeIfPresent(Int.self, forKey: .reactedMemoryCount) ?? 0
        reactionCount = try container.decodeIfPresent(Int.self, forKey: .reactionCount) ?? 0
        reactionCoverage = try container.decodeIfPresent(Double.self, forKey: .reactionCoverage) ?? 0
        reactionFrequency = try container.decodeIfPresent([ReportReactionMetric].self, forKey: .reactionFrequency) ?? []
        mostUsedReaction = try container.decodeIfPresent(ReportReactionMetric.self, forKey: .mostUsedReaction)
        dayColorFrequency = try container.decodeIfPresent([ReportColorMetric].self, forKey: .dayColorFrequency) ?? []
        mostUsedColor = try container.decodeIfPresent(ReportColorMetric.self, forKey: .mostUsedColor)
        memoryDayCount = try container.decodeIfPresent(Int.self, forKey: .memoryDayCount) ?? 0
        activeWeek = try container.decodeIfPresent(ReportActiveWeekMetric.self, forKey: .activeWeek)
        longestMemoryCharacterCount = try container.decodeIfPresent(Int.self, forKey: .longestMemoryCharacterCount) ?? 0
        averageMemoryCharacterCount = try container.decodeIfPresent(Double.self, forKey: .averageMemoryCharacterCount) ?? 0
    }
}

struct YearlyMonthlyBreakdown: Codable, Hashable, Sendable, Identifiable {
    let month: Int
    let memoryCount: Int
    let reactionCount: Int
    let reactedMemoryCount: Int
    let reactionCoverage: Double

    var id: Int { month }

    enum CodingKeys: String, CodingKey {
        case month
        case memoryCount = "memory_count"
        case reactionCount = "reaction_count"
        case reactedMemoryCount = "reacted_memory_count"
        case reactionCoverage = "reaction_coverage"
    }
}

struct YearlyReportMetricsV1: Codable, Hashable, Sendable {
    let schemaVersion: Int
    let memoryCount: Int
    let reactedMemoryCount: Int
    let reactionCount: Int
    let reactionCoverage: Double
    let reactionFrequency: [ReportReactionMetric]
    let mostUsedReaction: ReportReactionMetric?
    let dayColorFrequency: [ReportColorMetric]
    let mostUsedColor: ReportColorMetric?
    let mostActiveMonth: Int?
    let mostActiveMonthMemoryCount: Int
    let monthlyBreakdown: [YearlyMonthlyBreakdown]
    let longestMemoryCharacterCount: Int
    let averageMemoryCharacterCount: Double

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case memoryCount = "memory_count"
        case reactedMemoryCount = "reacted_memory_count"
        case reactionCount = "reaction_count"
        case reactionCoverage = "reaction_coverage"
        case reactionFrequency = "reaction_frequency"
        case mostUsedReaction = "most_used_reaction"
        case dayColorFrequency = "day_color_frequency"
        case mostUsedColor = "most_used_color"
        case mostActiveMonth = "most_active_month"
        case mostActiveMonthMemoryCount = "most_active_month_memory_count"
        case monthlyBreakdown = "monthly_breakdown"
        case longestMemoryCharacterCount = "longest_memory_character_count"
        case averageMemoryCharacterCount = "average_memory_character_count"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        memoryCount = try container.decodeIfPresent(Int.self, forKey: .memoryCount) ?? 0
        reactedMemoryCount = try container.decodeIfPresent(Int.self, forKey: .reactedMemoryCount) ?? 0
        reactionCount = try container.decodeIfPresent(Int.self, forKey: .reactionCount) ?? 0
        reactionCoverage = try container.decodeIfPresent(Double.self, forKey: .reactionCoverage) ?? 0
        reactionFrequency = try container.decodeIfPresent([ReportReactionMetric].self, forKey: .reactionFrequency) ?? []
        mostUsedReaction = try container.decodeIfPresent(ReportReactionMetric.self, forKey: .mostUsedReaction)
        dayColorFrequency = try container.decodeIfPresent([ReportColorMetric].self, forKey: .dayColorFrequency) ?? []
        mostUsedColor = try container.decodeIfPresent(ReportColorMetric.self, forKey: .mostUsedColor)
        mostActiveMonth = try container.decodeIfPresent(Int.self, forKey: .mostActiveMonth)
        mostActiveMonthMemoryCount = try container.decodeIfPresent(Int.self, forKey: .mostActiveMonthMemoryCount) ?? 0
        monthlyBreakdown = try container.decodeIfPresent([YearlyMonthlyBreakdown].self, forKey: .monthlyBreakdown) ?? []
        longestMemoryCharacterCount = try container.decodeIfPresent(Int.self, forKey: .longestMemoryCharacterCount) ?? 0
        averageMemoryCharacterCount = try container.decodeIfPresent(Double.self, forKey: .averageMemoryCharacterCount) ?? 0
    }
}

enum ReportMetricsDecoder {
    static func decodeMonthly(_ metrics: [String: JSONValue]) -> MonthlyReportMetricsV1? {
        decode(MonthlyReportMetricsV1.self, from: metrics)
    }

    static func decodeYearly(_ metrics: [String: JSONValue]) -> YearlyReportMetricsV1? {
        decode(YearlyReportMetricsV1.self, from: metrics)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from metrics: [String: JSONValue]) -> T? {
        guard let data = try? JSONEncoder().encode(metrics) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

extension MonthlyReport {
    var metricsV1: MonthlyReportMetricsV1? {
        ReportMetricsDecoder.decodeMonthly(metrics)
    }
}

extension YearlyReport {
    var metricsV1: YearlyReportMetricsV1? {
        ReportMetricsDecoder.decodeYearly(metrics)
    }
}

enum ReportPeriodEligibility {
    static func isCompleted(month: Int, year: Int, today: CalendarDay) -> Bool {
        year < today.year || (year == today.year && month < today.month)
    }

    static func isCompleted(year: Int, today: CalendarDay) -> Bool {
        year < today.year
    }
}
