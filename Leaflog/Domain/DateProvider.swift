import Foundation

/// Подменяемые часы и календарь. Вся календарная арифметика идёт через `calendar`,
/// а не через прибавление секунд, поэтому переходы на летнее время и конец месяца обрабатываются корректно.
struct DateProvider: Sendable {
    var now: @Sendable () -> Date
    var calendar: Calendar

    static var system: DateProvider {
        DateProvider(now: { Date() }, calendar: .autoupdatingCurrent)
    }

    static func fixed(_ date: Date, calendar: Calendar = .autoupdatingCurrent) -> DateProvider {
        DateProvider(now: { date }, calendar: calendar)
    }

    var today: Date { calendar.startOfDay(for: now()) }
}

extension Calendar {
    func dayDifference(from a: Date, to b: Date) -> Int {
        dateComponents([.day], from: startOfDay(for: a), to: startOfDay(for: b)).day ?? 0
    }
}
