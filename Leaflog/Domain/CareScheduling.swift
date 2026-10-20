import Foundation

enum IntervalUnit: String, Codable, CaseIterable, Sendable {
    case day, week, month
}

struct Recurrence: Codable, Equatable, Sendable {
    var value: Int
    var unit: IntervalUnit

    init(value: Int, unit: IntervalUnit) {
        self.value = max(1, value)
        self.unit = unit
    }

    /// Прибавляет интервал к началу дня `date` средствами Calendar.
    /// Месяц — календарный: 31 января + 1 месяц = 28/29 февраля (не «+30 дней»).
    func adding(to date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        let result: Date?
        switch unit {
        case .day: result = calendar.date(byAdding: .day, value: value, to: start)
        case .week: result = calendar.date(byAdding: .day, value: value * 7, to: start)
        case .month: result = calendar.date(byAdding: .month, value: value, to: start)
        }
        return calendar.startOfDay(for: result ?? start)
    }
}

/// Как трактовать `anchorDate`, пока у правила нет ни одного выполнения.
enum AnchorKind: String, Codable, CaseIterable, Sendable {
    /// Дата первой задачи.
    case firstDue
    /// Дата последнего ухода, о котором пользователь знает (событие в историю НЕ создаётся).
    case lastCare
}

enum TaskStatus: Equatable, Sendable {
    case upcoming(daysLeft: Int)
    case dueToday
    case overdue(days: Int)

    var isActionable: Bool {
        switch self {
        case .upcoming: false
        default: true
        }
    }
}

enum CareScheduler {
    /// Следующий срок (начало локального дня) или nil, если расписания нет.
    /// Считается от ФАКТИЧЕСКОЙ даты последнего выполнения; старый план не учитывается.
    static func nextDue(recurrence: Recurrence?,
                        anchorDate: Date?,
                        anchorKind: AnchorKind,
                        lastPerformed: Date?,
                        calendar: Calendar) -> Date? {
        guard let recurrence else { return nil }
        if let lastPerformed {
            return recurrence.adding(to: lastPerformed, calendar: calendar)
        }
        guard let anchorDate else { return nil }
        switch anchorKind {
        case .firstDue: return calendar.startOfDay(for: anchorDate)
        case .lastCare: return recurrence.adding(to: anchorDate, calendar: calendar)
        }
    }

    static func status(dueDay: Date, today: Date, calendar: Calendar) -> TaskStatus {
        let diff = calendar.dayDifference(from: today, to: dueDay)
        if diff > 0 { return .upcoming(daysLeft: diff) }
        if diff == 0 { return .dueToday }
        return .overdue(days: -diff)
    }

    /// Выполнение, внесённое задним числом, не сдвигает график назад: берётся самая поздняя дата.
    static func latest(_ dates: [Date]) -> Date? { dates.max() }
}
