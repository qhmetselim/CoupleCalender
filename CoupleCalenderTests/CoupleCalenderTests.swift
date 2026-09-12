//
//  CoupleCalenderTests.swift
//  CoupleCalenderTests
//
//  Created by Ahmet Selim Arslantürk on 10.09.2026.
//

import Foundation
import Supabase
import Testing
@testable import CoupleCalender

@MainActor
struct CoupleCalenderTests {

    @Test func example() async throws {
        #expect(true)
    }

    @Test func calendarDayRoundTripsLocalDateWithoutUtcShift() throws {
        for identifier in ["America/Los_Angeles", "Europe/Istanbul", "Asia/Tokyo"] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try #require(TimeZone(identifier: identifier))
            let localDate = try #require(calendar.date(from: DateComponents(
                year: 2026,
                month: 9,
                day: 10,
                hour: 12
            )))

            let day = CalendarDay(date: localDate, calendar: calendar)

            #expect(day.rawValue == "2026-09-10")
            #expect(CalendarDay(date: try #require(day.date(in: calendar)), calendar: calendar) == day)
        }
    }

    @Test func calendarDayPreservesDstAndLeapDay() throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try #require(TimeZone(identifier: "America/New_York"))

        for rawValue in ["2024-02-29", "2026-03-08", "2026-11-01"] {
            let day = CalendarDay(rawValue: rawValue)
            let date = try #require(day.date(in: newYork))
            #expect(CalendarDay(date: date, calendar: newYork) == day)
        }

        var rejectedInvalidDate = false
        do {
            _ = try CalendarDay(iso8601: "2026-02-30")
        } catch {
            rejectedInvalidDate = true
        }
        #expect(rejectedInvalidDate)
    }

    @Test func calendarEngineBuildsExpectedMonthGrids() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Istanbul"))
        calendar.firstWeekday = 1
        let engine = CalendarEngine(calendar: calendar)

        #expect(engine.monthGrid(containing: CalendarDay(rawValue: "2026-02-10")).count == 28)
        #expect(engine.monthGrid(containing: CalendarDay(rawValue: "2026-09-10")).count == 35)
        #expect(engine.monthGrid(containing: CalendarDay(rawValue: "2026-08-10")).count == 42)
    }

    @Test func calendarEngineHandlesWeekAndYearBoundaries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        calendar.firstWeekday = 2
        let engine = CalendarEngine(calendar: calendar)
        let newYear = CalendarDay(rawValue: "2027-01-01")
        let week = engine.weekDays(containing: newYear)

        #expect(week.count == 7)
        #expect(week.contains(newYear))
        #expect(week.first?.rawValue == "2026-12-28")
        #expect(week.last?.rawValue == "2027-01-03")
        #expect(engine.adding(.year, value: -1, to: newYear).rawValue == "2026-01-01")
        #expect(engine.adding(.month, value: -1, to: newYear).rawValue == "2026-12-01")
    }

    @Test func calendarEngineReturnsDateRangesForEachMode() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Istanbul"))
        calendar.firstWeekday = 2
        let engine = CalendarEngine(calendar: calendar)
        let selected = CalendarDay(rawValue: "2026-09-10")

        let dayRange = engine.visibleRange(for: selected, mode: .day)
        #expect(dayRange.start == selected && dayRange.end == selected)

        let weekRange = engine.visibleRange(for: selected, mode: .week)
        #expect(weekRange.start.rawValue == "2026-09-07")
        #expect(weekRange.end.rawValue == "2026-09-13")

        let monthRange = engine.visibleRange(for: selected, mode: .month)
        #expect(monthRange.start.rawValue == "2026-08-31")
        #expect(monthRange.end.rawValue == "2026-10-04")

        let yearRange = engine.visibleRange(for: selected, mode: .year)
        #expect(yearRange.start.rawValue == "2026-01-01")
        #expect(yearRange.end.rawValue == "2026-12-31")
    }

    @Test func memoryContentValidationMatchesDatabaseConstraints() throws {
        #expect(try MemoryContentValidator.normalized("  hello world  ") == "hello world")
        #expect(MemoryContentValidator.characterCount(String(repeating: "a", count: 10_000)) == 10_000)

        var rejectedEmpty = false
        do {
            _ = try MemoryContentValidator.normalized(" \n\t ")
        } catch MemoryContentValidationError.empty {
            rejectedEmpty = true
        }
        #expect(rejectedEmpty)

        var rejectedTooLong = false
        do {
            _ = try MemoryContentValidator.normalized(String(repeating: "a", count: 10_001))
        } catch MemoryContentValidationError.tooLong {
            rejectedTooLong = true
        }
        #expect(rejectedTooLong)
    }

    @Test func futureDayRuleDistinguishesPastTodayAndFuture() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Istanbul"))
        let engine = CalendarEngine(calendar: calendar)
        let today = CalendarDay(date: Date(), calendar: calendar)
        let past = engine.adding(.day, value: -1, to: today)
        let future = engine.adding(.day, value: 1, to: today)

        #expect(engine.date(for: past) < Date())
        #expect(engine.date(for: today) <= Date())
        #expect(engine.date(for: future) > Date())
    }

    @Test func dayColorPaletteUsesStableKeys() {
        let keys = DayColorPalette.options.map(\.key)

        #expect(keys.count == 12)
        #expect(Set(keys).count == keys.count)
        #expect(DayColorPalette.color(for: "rose") != DayColorPalette.color(for: "unknown"))
        #expect(DayColorPalette.label(for: "blue") == "Mavi")
    }

    @Test func realtimeMemoryBroadcastParsesAsAnIdempotentDomainEvent() throws {
        let memory = Memory(
            id: try #require(UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")),
            ownerID: try #require(UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")),
            calendarDay: CalendarDay(rawValue: "2026-09-10"),
            content: "Bugün",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let record = try JSONObject(memory)
        let change: JSONObject = [
            "schema": "public",
            "table": "memories",
            "eventType": "INSERT",
            "new": .object(record),
            "old": .null
        ]
        let payload: JSONObject = [
            "event": "INSERT",
            "type": "broadcast",
            "payload": .object(change)
        ]

        guard case let .memoryUpsert(parsed) = CoupleRealtimeChangeParser.parse(payload) else {
            Issue.record("Expected an INSERT memory change")
            return
        }

        #expect(parsed.id == memory.id)
        #expect(parsed.calendarDay == memory.calendarDay)
        #expect(parsed.content == memory.content)
    }

    @Test func notificationNavigationRejectsMalformedOrMissingDate() throws {
        let ownerID = try #require(UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"))
        let memoryID = try #require(UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"))
        let valid: [AnyHashable: Any] = [
            "type": "memory_created",
            "memory_id": memoryID.uuidString,
            "calendar_day": "2026-09-10",
            "calendar_owner_id": ownerID.uuidString
        ]
        let invalid = [
            "type": "memory_created",
            "memory_id": memoryID.uuidString,
            "calendar_day": "2026-02-30",
            "calendar_owner_id": ownerID.uuidString
        ] as [AnyHashable: Any]

        #expect(NotificationNavigationTarget(userInfo: valid) != nil)
        #expect(NotificationNavigationTarget(userInfo: invalid) == nil)
    }

    @Test func partnerWidgetSnapshotSortsLimitsAndKeepsDecorations() throws {
        let userID = try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000001"))
        let coupleID = try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000002"))
        let partnerID = try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000003"))
        let memoryID = try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000004"))
        let memories = (1...8).map { offset in
            Memory(
                id: UUID(),
                ownerID: partnerID,
                calendarDay: CalendarDay(rawValue: "2026-09-\(String(format: "%02d", offset))"),
                content: String(repeating: "a", count: 300),
                createdAt: Date(timeIntervalSince1970: Double(offset)),
                updatedAt: Date(timeIntervalSince1970: Double(offset))
            )
        } + [Memory(
            id: memoryID,
            ownerID: partnerID,
            calendarDay: CalendarDay(rawValue: "2026-09-10"),
            content: "Özel anı",
            createdAt: Date(),
            updatedAt: Date()
        )]
        let reaction = MemoryReaction(
            id: UUID(),
            memoryID: memoryID,
            reactorID: userID,
            reactionSet: "unicode-v1",
            reactionKey: "heart",
            createdAt: Date(),
            updatedAt: Date()
        )
        let color = DayColor(
            id: UUID(),
            calendarOwnerID: partnerID,
            calendarDay: CalendarDay(rawValue: "2026-09-10"),
            assignedByID: userID,
            colorKey: "rose",
            createdAt: Date(),
            updatedAt: Date()
        )
        let catalogItem = ReactionCatalogItem(
            reactionSet: "unicode-v1",
            reactionKey: "heart",
            displayValue: "❤️",
            assetName: nil,
            isActive: true
        )

        let snapshot = PartnerWidgetSnapshotBuilder.make(
            userID: userID,
            coupleID: coupleID,
            partnerID: partnerID,
            partnerDisplayName: "Partner",
            memories: memories,
            reactions: [reaction],
            dayColors: [color],
            reactionCatalog: [catalogItem]
        )

        #expect(snapshot.memories.count == 7)
        #expect(snapshot.memories.first?.calendarDay == "2026-09-10")
        #expect(snapshot.memories.first?.reactionDisplayValue == "❤️")
        #expect(snapshot.memories.first?.dayColorKey == "rose")
        #expect(snapshot.memories.first?.contentPreview == "Özel anı")
        #expect(snapshot.memories.dropFirst().allSatisfy { $0.contentPreview.hasSuffix("…") })
    }

    @Test func partnerWidgetSnapshotRoundTripsAndClearsFromSharedStore() throws {
        let suiteName = "CoupleCalenderTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let store = PartnerWidgetSnapshotStore(defaults: defaults)
        let snapshot = PartnerWidgetSnapshot(
            schemaVersion: PartnerWidgetSnapshot.currentSchemaVersion,
            generatedAt: Date(timeIntervalSince1970: 1),
            userID: try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000001")),
            coupleID: try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000002")),
            partnerID: try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000003")),
            partnerDisplayName: "Partner",
            memories: []
        )

        store.save(snapshot)
        #expect(store.read() == snapshot)
        store.clear()
        #expect(store.read() == nil)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func widgetDeepLinkIsPartnerDayOnlyAndRejectsForeignRoutes() throws {
        let memoryID = try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000004"))
        let url = try #require(WidgetDeepLink.url(calendarDay: "2026-09-10", memoryID: memoryID))
        let target = try #require(WidgetDeepLink.parse(url))

        #expect(target.calendarDay == "2026-09-10")
        #expect(target.memoryID == memoryID)
        let foreignURL = try #require(URL(string: "couplecalender://other/day/2026-09-10"))
        let invalidDateURL = try #require(URL(string: "couplecalender://partner/day/2026-02-30"))
        #expect(WidgetDeepLink.parse(foreignURL) == nil)
        #expect(WidgetDeepLink.parse(invalidDateURL) == nil)
    }

}
