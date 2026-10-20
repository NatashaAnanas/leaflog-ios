import XCTest
import SwiftData
@testable import Leaflog

final class NotificationPlannerTests: XCTestCase {
    let cal = makeCal()
    let settings = NotifSettings(hour: 9, minute: 0, repeatOverdue: true)

    private func item(_ plant: String, _ type: String = "Полив", due: Date, snooze: Date? = nil) -> NotifItem {
        NotifItem(ruleID: UUID(), plantID: UUID(), plantName: plant, typeName: type, dueDay: due, snoozedUntil: snooze)
    }

    func testUpcomingTaskFiresOnDueDayAtChosenTimeWithFollowUps() {
        let now = day(2026, 10, 15, 10)
        let plan = NotificationPlanner.plan(items: [item("Орхидея", due: day(2026, 10, 20, 0))], settings: settings, now: now, calendar: cal)
        XCTAssertEqual(plan.count, 6) // срок + 1, 2, 3, 7, 14 дней
        XCTAssertEqual(comps(plan[0].fireDate).day, 20)
        XCTAssertEqual(comps(plan[0].fireDate).hour, 9)
        XCTAssertEqual(plan[0].title, "Орхидея")
        XCTAssertTrue(plan[0].body.contains("Полив"))
        XCTAssertEqual(plan.map { comps($0.fireDate).day }, [20, 21, 22, 23, 27, 3])
        XCTAssertTrue(plan[1].body.contains("просрочено"))
    }

    func testRepeatOffGivesSingleReminder() {
        let s = NotifSettings(hour: 9, minute: 0, repeatOverdue: false)
        let plan = NotificationPlanner.plan(items: [item("А", due: day(2026, 10, 20, 0))], settings: s, now: day(2026, 10, 15, 10), calendar: cal)
        XCTAssertEqual(plan.count, 1)
    }

    func testAlreadyOverdueStartsTomorrowIfTodaysTimePassed() {
        let it = item("А", due: day(2026, 10, 10, 0))
        let late = NotificationPlanner.plan(items: [it], settings: settings, now: day(2026, 10, 15, 10), calendar: cal)
        XCTAssertEqual(comps(late[0].fireDate).day, 16)
        XCTAssertTrue(late[0].body.contains("просрочено на 6 дней"), late[0].body)
        let early = NotificationPlanner.plan(items: [it], settings: settings, now: day(2026, 10, 15, 7), calendar: cal)
        XCTAssertEqual(comps(early[0].fireDate).day, 15)
    }

    func testSameDayTasksMergeIntoOneDigest() {
        let due = day(2026, 10, 20, 0)
        let plan = NotificationPlanner.plan(items: [item("Б", due: due), item("А", "Опрыскивание", due: due)], settings: settings, now: day(2026, 10, 15, 10), calendar: cal)
        XCTAssertEqual(plan.filter { comps($0.fireDate).day == 20 }.count, 1)
        let digest = plan[0]
        XCTAssertFalse(digest.isSingle)
        XCTAssertEqual(digest.plantIDs.count, 2)
        XCTAssertTrue(digest.body.contains("А — опрыскивание") && digest.body.contains("Б — полив"))
    }

    func testPendingLimitIsRespected() {
        let items = (0..<40).map { item("P\($0)", due: day(2026, 10, 16, 0).addingTimeInterval(Double($0) * 86_400)) }
        let plan = NotificationPlanner.plan(items: items, settings: settings, now: day(2026, 10, 15, 10), calendar: cal)
        XCTAssertLessThanOrEqual(plan.count, NotificationPlanner.maxPending)
        XCTAssertLessThan(NotificationPlanner.maxPending, 64)
        XCTAssertEqual(Set(plan.map(\.identifier)).count, plan.count, "один идентификатор на день")
        XCTAssertEqual(plan.map(\.fireDate), plan.map(\.fireDate).sorted(), "ближайшие дни имеют приоритет")
    }

    func testSnoozePushesReminderButNotBeforeDue() {
        let it = item("А", due: day(2026, 10, 10, 0), snooze: day(2026, 10, 17, 0))
        let plan = NotificationPlanner.plan(items: [it], settings: settings, now: day(2026, 10, 15, 10), calendar: cal)
        XCTAssertEqual(comps(plan[0].fireDate).day, 17)
    }

    func testFireTimesInThePastAreDropped() {
        let plan = NotificationPlanner.plan(items: [item("А", due: day(2026, 10, 15, 0))], settings: NotifSettings(hour: 9, minute: 0, repeatOverdue: false), now: day(2026, 10, 15, 12), calendar: cal)
        XCTAssertTrue(plan.isEmpty || comps(plan[0].fireDate).day != 15)
    }
}

@MainActor
final class NotificationServiceTests: XCTestCase {
    private func setup(now: Date = day(2026, 10, 15, 10)) throws -> (Env, Plant, CareRule) {
        let e = try Env(now: now)
        e.settings.notificationsEnabled = true
        let p = try e.plant("Каланхоэ")
        let rule = try e.repo.setRule(plant: p, typeID: e.type("water").id, recurrence: Recurrence(value: 7, unit: .day),
                                      anchorDate: day(2026, 10, 18), anchorKind: .firstDue)
        return (e, p, rule)
    }

    func testSyncSchedulesFromRulesAndCompletionReschedules() async throws {
        let (e, p, _) = try setup()
        await e.service.sync()
        XCTAssertEqual(e.center.pending.count, 6)
        XCTAssertNotNil(e.center.pending["leaflog.day.20261018"])
        // Полили 16-го → старые напоминания (18, 19, …) убраны, новые от 23-го.
        e.clock.date = day(2026, 10, 16, 10)
        try e.repo.logCare(plant: p, typeID: e.type("water").id)
        await e.service.sync()
        XCTAssertNil(e.center.pending["leaflog.day.20261018"])
        XCTAssertNotNil(e.center.pending["leaflog.day.20261023"])
        XCTAssertEqual(e.center.pending["leaflog.day.20261023"]?.title, "Каланхоэ")
    }

    func testIntervalChangeArchiveAndDeleteSyncNotifications() async throws {
        let (e, p, _) = try setup()
        try e.repo.logCare(plant: p, typeID: e.type("water").id, date: day(2026, 10, 15, 9))
        await e.service.sync()
        XCTAssertNotNil(e.center.pending["leaflog.day.20261022"])
        try e.repo.setRule(plant: p, typeID: e.type("water").id, recurrence: Recurrence(value: 10, unit: .day), anchorDate: nil, anchorKind: .firstDue)
        await e.service.sync()
        XCTAssertNil(e.center.pending["leaflog.day.20261022"])
        XCTAssertNotNil(e.center.pending["leaflog.day.20261025"])
        try e.repo.setArchived(p, true)
        await e.service.sync()
        XCTAssertTrue(e.center.pending.isEmpty)
        try e.repo.setArchived(p, false)
        await e.service.sync()
        XCTAssertFalse(e.center.pending.isEmpty)
        try e.repo.deletePlant(p)
        await e.service.sync()
        XCTAssertTrue(e.center.pending.isEmpty)
    }

    func testRespectsGlobalPlantTypeAndRuleToggles() async throws {
        let (e, p, rule) = try setup()
        e.settings.notificationsEnabled = false
        await e.service.sync()
        XCTAssertTrue(e.center.pending.isEmpty)
        e.settings.notificationsEnabled = true
        p.notificationsEnabled = false
        await e.service.sync(); XCTAssertTrue(e.center.pending.isEmpty)
        p.notificationsEnabled = true
        e.type("water").notificationsEnabled = false
        await e.service.sync(); XCTAssertTrue(e.center.pending.isEmpty)
        e.type("water").notificationsEnabled = true
        rule.notificationsEnabled = false
        await e.service.sync(); XCTAssertTrue(e.center.pending.isEmpty)
        rule.notificationsEnabled = true
        await e.service.sync(); XCTAssertFalse(e.center.pending.isEmpty)
    }

    func testDeniedPermissionSchedulesNothingAndDoesNotCrash() async throws {
        let (e, _, _) = try setup()
        e.center.status = .denied
        await e.service.sync()
        XCTAssertTrue(e.center.pending.isEmpty)
    }

    func testEnableRemindersRequestsPermissionInContext() async throws {
        let (e, _, _) = try setup()
        e.settings.notificationsEnabled = false
        e.center.status = .notDetermined
        let granted = await e.service.enableReminders()
        XCTAssertTrue(granted)
        XCTAssertEqual(e.center.requestCount, 1)
        XCTAssertFalse(e.center.pending.isEmpty)
    }

    func testPendingRegistryIsNotSourceOfTruth() async throws {
        let (e, _, _) = try setup()
        await e.service.sync()
        e.center.pending.removeAll()     // система потеряла запросы
        await e.service.sync()
        XCTAssertEqual(e.center.pending.count, 6, "запросы восстановлены из правил и истории")
        e.center.pending["leaflog.day.99999999"] = .init(id: "leaflog.day.99999999", title: "x", body: "x", fire: Date(), category: "", userInfo: [:])
        await e.service.sync()
        XCTAssertNil(e.center.pending["leaflog.day.99999999"], "устаревшие запросы удаляются")
    }

    func testDoneActionIsIdempotent() async throws {
        let (e, p, rule) = try setup(now: day(2026, 10, 18, 10))
        let key = NotificationPlanner.dayKey(day(2026, 10, 18), calendar: e.cal)
        XCTAssertEqual(e.service.handleDone(ruleID: rule.id, dueKey: key, repository: e.repo), .logged)
        XCTAssertEqual(p.events.count, 1)
        // Повторная доставка того же действия (в том числе позже) не создаёт дубликат.
        e.clock.date = day(2026, 10, 18, 10).addingTimeInterval(60)
        XCTAssertEqual(e.service.handleDone(ruleID: rule.id, dueKey: key, repository: e.repo), .duplicate)
        XCTAssertEqual(p.events.count, 1)
        XCTAssertEqual(p.events[0].sourceKey, "notif-done:\(rule.id.uuidString):\(key)")
    }

    func testDoneActionIgnoredWhenAlreadyHandledInApp() async throws {
        let (e, p, rule) = try setup(now: day(2026, 10, 18, 10))
        let key = NotificationPlanner.dayKey(day(2026, 10, 18), calendar: e.cal)
        try e.repo.logCare(plant: p, typeID: e.type("water").id)    // уже полили в приложении
        e.clock.date = e.clock.date.addingTimeInterval(120)
        XCTAssertEqual(e.service.handleDone(ruleID: rule.id, dueKey: key, repository: e.repo), .stale)
        XCTAssertEqual(p.events.count, 1)
        XCTAssertEqual(e.service.handleDone(ruleID: UUID(), dueKey: key, repository: e.repo), .notFound)
    }

    func testSnoozeActionDoesNotCountAsCare() async throws {
        let (e, p, rule) = try setup(now: day(2026, 10, 19, 10))
        XCTAssertEqual(e.service.handleSnooze(ruleID: rule.id, repository: e.repo), .snoozed)
        XCTAssertEqual(p.events.count, 0)
        XCTAssertEqual(rule.snoozedUntil, day(2026, 10, 20, 0))
    }

    func testStaleDeliveredNotificationsAreRemovedAfterCompletion() async throws {
        let (e, p, rule) = try setup(now: day(2026, 10, 18, 10))
        e.center.deliveredItems = [("leaflog.day.20261018", [rule.id.uuidString])]
        await e.service.sync()
        XCTAssertTrue(e.center.removedDelivered.isEmpty, "задача всё ещё актуальна")
        try e.repo.logCare(plant: p, typeID: e.type("water").id)
        await e.service.sync()
        XCTAssertEqual(e.center.removedDelivered, ["leaflog.day.20261018"])
    }

    func testUserInfoCarriesRoutingData() async throws {
        let (e, p, rule) = try setup()
        await e.service.sync()
        let item = e.center.pending["leaflog.day.20261018"]!
        XCTAssertEqual(item.userInfo["plantIDs"] as? [String], [p.id.uuidString])
        XCTAssertEqual(item.userInfo["ruleIDs"] as? [String], [rule.id.uuidString])
        XCTAssertEqual(item.category, SystemNotificationCenter.singleCategory)
    }
}
