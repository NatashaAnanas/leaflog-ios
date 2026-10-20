import XCTest
@testable import Leaflog

final class SchedulingTests: XCTestCase {
    let cal = makeCal()

    private func next(_ r: Recurrence?, last: Date?, anchor: Date? = nil, kind: AnchorKind = .firstDue, _ c: Calendar? = nil) -> Date? {
        CareScheduler.nextDue(recurrence: r, anchorDate: anchor, anchorKind: kind, lastPerformed: last, calendar: c ?? cal)
    }

    func testNormalCompletion() {
        let due = next(Recurrence(value: 7, unit: .day), last: day(2026, 10, 13))
        XCTAssertEqual(comps(due!).day, 20)
        XCTAssertEqual(comps(due!).hour, 0)
    }

    func testLateCompletionCountsFromActualDateNotOldPlan() {
        // Срок был 10 октября, полили 13-го → следующий 20-го.
        let due = next(Recurrence(value: 7, unit: .day), last: day(2026, 10, 13))
        XCTAssertEqual(due, day(2026, 10, 20, 0))
    }

    func testIntervalChangeRecalculatesFromLastActual() {
        let last = day(2026, 10, 13)
        XCTAssertEqual(next(Recurrence(value: 7, unit: .day), last: last), day(2026, 10, 20, 0))
        XCTAssertEqual(next(Recurrence(value: 10, unit: .day), last: last), day(2026, 10, 23, 0))
        // Если срок уже прошёл — просрочка.
        let due = next(Recurrence(value: 3, unit: .day), last: last)!
        XCTAssertEqual(CareScheduler.status(dueDay: due, today: day(2026, 10, 20, 0), calendar: cal), .overdue(days: 4))
    }

    func testStatusBoundaries() {
        let due = day(2026, 10, 20, 0)
        XCTAssertEqual(CareScheduler.status(dueDay: due, today: day(2026, 10, 18, 0), calendar: cal), .upcoming(daysLeft: 2))
        XCTAssertEqual(CareScheduler.status(dueDay: due, today: day(2026, 10, 20, 0), calendar: cal), .dueToday)
        XCTAssertEqual(CareScheduler.status(dueDay: due, today: day(2026, 10, 21, 0), calendar: cal), .overdue(days: 1))
    }

    func testNoScheduleMeansNoDue() {
        XCTAssertNil(next(nil, last: day(2026, 10, 13)))
    }

    func testFirstDateWithoutHistory() {
        let r = Recurrence(value: 7, unit: .day)
        XCTAssertEqual(next(r, last: nil, anchor: day(2026, 10, 18, 15), kind: .firstDue), day(2026, 10, 18, 0))
        XCTAssertEqual(next(r, last: nil, anchor: day(2026, 10, 10), kind: .lastCare), day(2026, 10, 17, 0))
        XCTAssertNil(next(r, last: nil, anchor: nil))
    }

    func testHistoryOverridesAnchor() {
        let r = Recurrence(value: 7, unit: .day)
        XCTAssertEqual(next(r, last: day(2026, 10, 13), anchor: day(2026, 12, 1), kind: .firstDue), day(2026, 10, 20, 0))
    }

    func testWeeksAndMonthsAreCalendarBased() {
        XCTAssertEqual(next(Recurrence(value: 2, unit: .week), last: day(2026, 10, 1)), day(2026, 10, 15, 0))
        // Месяц ≠ 30 дней: 15 января + 1 месяц = 15 февраля.
        XCTAssertEqual(next(Recurrence(value: 1, unit: .month), last: day(2026, 1, 15)), day(2026, 2, 15, 0))
        XCTAssertEqual(next(Recurrence(value: 3, unit: .month), last: day(2026, 11, 20)), day(2027, 2, 20, 0))
    }

    func testMonthEndClamping() {
        let m = Recurrence(value: 1, unit: .month)
        XCTAssertEqual(next(m, last: day(2026, 1, 31)), day(2026, 2, 28, 0))
        XCTAssertEqual(next(m, last: day(2028, 1, 31)), day(2028, 2, 29, 0))   // високосный
        XCTAssertEqual(next(m, last: day(2026, 3, 31)), day(2026, 4, 30, 0))
        XCTAssertEqual(next(m, last: day(2026, 12, 31)), day(2027, 1, 31, 0))
        // От фактической даты, а не от «31-го»: 28 февраля → 28 марта.
        XCTAssertEqual(next(m, last: day(2026, 2, 28)), day(2026, 3, 28, 0))
    }

    func testDSTDoesNotShiftCalendarDay() {
        let ny = makeCal("America/New_York")
        // В США переход на летнее время 8 марта 2026: +7 дней от 7 марта — это 14 марта 00:00 по местному, а не 23:00 13-го.
        let due = next(Recurrence(value: 7, unit: .day), last: day(2026, 3, 7, 18, 0, ny), ny)!
        XCTAssertEqual(comps(due, ny).day, 14)
        XCTAssertEqual(comps(due, ny).hour, 0)
        // Осенний переход (1 ноября 2026).
        let fall = next(Recurrence(value: 1, unit: .day), last: day(2026, 10, 31, 23, 30, ny), ny)!
        XCTAssertEqual(comps(fall, ny).day, 1)
        XCTAssertEqual(comps(fall, ny).hour, 0)
    }

    func testTimezoneChangeReinterpretsSameInstantConsistently() {
        let ny = makeCal("America/New_York")
        let auckland = makeCal("Pacific/Auckland")
        let instant = day(2026, 10, 13, 22, 30, ny) // 13 окт вечером в Нью-Йорке = 14 окт в Окленде
        let r = Recurrence(value: 7, unit: .day)
        let dueNY = next(r, last: instant, ny)!
        let dueAK = next(r, last: instant, auckland)!
        XCTAssertEqual(comps(dueNY, ny).day, 20)
        XCTAssertEqual(comps(dueAK, auckland).day, 21)
        // В обоих случаях срок — начало местного дня, а статус считается в том же календаре.
        XCTAssertEqual(comps(dueNY, ny).hour, 0)
        XCTAssertEqual(comps(dueAK, auckland).hour, 0)
        XCTAssertEqual(CareScheduler.status(dueDay: dueNY, today: ny.startOfDay(for: day(2026, 10, 20, 8, 0, ny)), calendar: ny), .dueToday)
    }

    func testLatestWinsSoOldEntryDoesNotMoveScheduleBack() {
        let last = CareScheduler.latest([day(2026, 10, 13), day(2026, 10, 5), day(2026, 9, 1)])
        XCTAssertEqual(next(Recurrence(value: 7, unit: .day), last: last), day(2026, 10, 20, 0))
    }

    func testRecurrenceClampsToAtLeastOne() {
        XCTAssertEqual(Recurrence(value: 0, unit: .day).value, 1)
        XCTAssertEqual(Recurrence(value: -4, unit: .week).value, 1)
    }

    func testSeasonsFollowHemisphere() {
        XCTAssertEqual(Season.current(for: day(2026, 10, 20), hemisphere: .north, calendar: cal), .autumn)
        XCTAssertEqual(Season.current(for: day(2026, 10, 20), hemisphere: .south, calendar: cal), .spring)
        XCTAssertEqual(Season.current(for: day(2026, 1, 5), hemisphere: .north, calendar: cal), .winter)
        XCTAssertEqual(Season.current(for: day(2026, 1, 5), hemisphere: .south, calendar: cal), .summer)
    }

    func testRussianPlurals() {
        XCTAssertEqual(RuPlural.days(1), "1 день"); XCTAssertEqual(RuPlural.days(2), "2 дня")
        XCTAssertEqual(RuPlural.days(5), "5 дней"); XCTAssertEqual(RuPlural.days(11), "11 дней")
        XCTAssertEqual(RuPlural.days(21), "21 день"); XCTAssertEqual(RuPlural.days(112), "112 дней")
    }
}
