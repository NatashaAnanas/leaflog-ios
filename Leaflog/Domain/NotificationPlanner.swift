import Foundation

/// Одна задача, по которой может понадобиться напоминание.
struct NotifItem: Equatable, Sendable {
    var ruleID: UUID
    var plantID: UUID
    var plantName: String
    var typeName: String
    var dueDay: Date
    var snoozedUntil: Date?
}

struct NotifSettings: Equatable, Sendable {
    var hour: Int
    var minute: Int
    var repeatOverdue: Bool
}

struct PlannedNotification: Equatable, Sendable {
    var identifier: String
    var fireDate: Date
    var title: String
    var body: String
    var plantIDs: [UUID]
    var ruleIDs: [UUID]
    /// Для одиночного напоминания: срок, к которому оно относится (для идемпотентного «Выполнено»).
    var dueKey: String?
    var isSingle: Bool
}

/// Чистая функция «задачи → список уведомлений». Источник истины — правила и история,
/// а не реестр ожидающих запросов iOS.
///
/// Стратегия: одно уведомление на календарный день (сводка), чтобы уложиться в лимит 64 ожидающих
/// запросов. Для каждой задачи дни показа: срок D; при включённом повторе — ещё D+1, D+2, D+3, D+7, D+14.
/// Для уже просроченных — ближайшее будущее время показа и те же смещения от сегодняшнего дня.
enum NotificationPlanner {
    static let idPrefix = "leaflog.day."
    static let followUpOffsets = [1, 2, 3, 7, 14]
    static let maxPending = 60 // запас до системного лимита 64

    static func dayKey(_ day: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func fireDate(on day: Date, settings: NotifSettings, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: settings.hour, minute: settings.minute, second: 0, of: day)
    }

    /// Дни показа для одной задачи (начала дней).
    static func fireDays(for item: NotifItem, settings: NotifSettings, now: Date, calendar: Calendar) -> [Date] {
        let today = calendar.startOfDay(for: now)
        func add(_ d: Int, to day: Date) -> Date { calendar.startOfDay(for: calendar.date(byAdding: .day, value: d, to: day) ?? day) }
        func isFuture(_ day: Date) -> Bool {
            guard let f = fireDate(on: day, settings: settings, calendar: calendar) else { return false }
            return f > now
        }
        var base = item.dueDay
        if let s = item.snoozedUntil { base = max(base, calendar.startOfDay(for: s)) }
        var days: [Date] = []
        if base >= today {
            days.append(base)
            if settings.repeatOverdue { days += followUpOffsets.map { add($0, to: base) } }
            return days.filter(isFuture)
        }
        // Уже просрочено: ближайшее время показа — сегодня (если ещё не прошло) или завтра.
        let first = isFuture(today) ? today : add(1, to: today)
        days.append(first)
        if settings.repeatOverdue { days += followUpOffsets.map { add($0, to: first) } }
        return days.filter(isFuture)
    }

    static func plan(items: [NotifItem], settings: NotifSettings, now: Date, calendar: Calendar,
                     limit: Int = maxPending) -> [PlannedNotification] {
        var byDay: [Date: [NotifItem]] = [:]
        for item in items {
            for day in fireDays(for: item, settings: settings, now: now, calendar: calendar) {
                byDay[day, default: []].append(item)
            }
        }
        var result: [PlannedNotification] = []
        for day in byDay.keys.sorted().prefix(limit) {
            guard let fire = fireDate(on: day, settings: settings, calendar: calendar) else { continue }
            let group = (byDay[day] ?? []).sorted { ($0.plantName, $0.typeName) < ($1.plantName, $1.typeName) }
            result.append(makeNotification(day: day, fire: fire, items: group, calendar: calendar))
        }
        return result
    }

    private static func makeNotification(day: Date, fire: Date, items: [NotifItem], calendar: Calendar) -> PlannedNotification {
        let id = idPrefix + dayKey(day, calendar: calendar)
        if items.count == 1, let item = items.first {
            let late = calendar.dayDifference(from: item.dueDay, to: day)
            let body: String
            if late > 0 {
                body = String(localized: "\(item.typeName): просрочено на \(RuPlural.days(late))")
            } else {
                body = String(localized: "Пора: \(item.typeName)")
            }
            return PlannedNotification(identifier: id, fireDate: fire, title: item.plantName, body: body,
                                       plantIDs: [item.plantID], ruleIDs: [item.ruleID],
                                       dueKey: dayKey(item.dueDay, calendar: calendar), isSingle: true)
        }
        let plantIDs = Array(NSOrderedSet(array: items.map(\.plantID))) as? [UUID] ?? []
        let title = String(localized: "Нужен уход за растениями: \(items.count)")
        var seen: [String] = []
        var parts: [String] = []
        for item in items {
            if !seen.contains(item.plantName) { seen.append(item.plantName) }
            parts.append("\(item.plantName) — \(item.typeName.lowercased())")
        }
        return PlannedNotification(identifier: id, fireDate: fire, title: title, body: parts.joined(separator: "; "),
                                   plantIDs: plantIDs, ruleIDs: items.map(\.ruleID), dueKey: nil, isSingle: false)
    }
}
