//
//  CoupleCalenderTests.swift
//  CoupleCalenderTests
//
//  Created by Ahmet Selim Arslantürk on 10.09.2026.
//

import Foundation
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

}
