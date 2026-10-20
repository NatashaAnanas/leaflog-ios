import Foundation

enum Hemisphere: String, Codable, CaseIterable, Sendable {
    case north, south
}

enum Season: String, Codable, CaseIterable, Sendable {
    case spring, summer, autumn, winter

    /// Метеорологические сезоны; для Южного полушария сдвиг на полгода.
    static func current(for date: Date, hemisphere: Hemisphere, calendar: Calendar) -> Season {
        let month = calendar.component(.month, from: date)
        let northern: Season
        switch month {
        case 3...5: northern = .spring
        case 6...8: northern = .summer
        case 9...11: northern = .autumn
        default: northern = .winter
        }
        guard hemisphere == .south else { return northern }
        switch northern {
        case .spring: return .autumn
        case .summer: return .winter
        case .autumn: return .spring
        case .winter: return .summer
        }
    }
}

/// Русское склонение: 1 день, 2 дня, 5 дней.
enum RuPlural {
    static func pick(_ n: Int, one: String, few: String, many: String) -> String {
        let m100 = abs(n) % 100, m10 = abs(n) % 10
        if m100 >= 11 && m100 <= 14 { return many }
        if m10 == 1 { return one }
        if m10 >= 2 && m10 <= 4 { return few }
        return many
    }
    static func days(_ n: Int) -> String { "\(n) " + pick(n, one: "день", few: "дня", many: "дней") }
    static func weeks(_ n: Int) -> String { "\(n) " + pick(n, one: "неделя", few: "недели", many: "недель") }
    static func months(_ n: Int) -> String { "\(n) " + pick(n, one: "месяц", few: "месяца", many: "месяцев") }
}
