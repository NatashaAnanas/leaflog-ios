import Foundation
import Observation

/// Настройки приложения (UserDefaults). Попадают в резервную копию.
@Observable
final class AppSettings {
    struct Snapshot: Codable, Equatable {
        var userName: String
        var notificationsEnabled: Bool
        var reminderHour: Int
        var reminderMinute: Int
        var repeatOverdue: Bool
        var hemisphere: Hemisphere
        var seasonOverride: Season?
    }

    private let defaults: UserDefaults
    private static let key = "leaflog.settings.v1"

    var userName: String { didSet { persist() } }
    var notificationsEnabled: Bool { didSet { persist() } }
    var reminderHour: Int { didSet { persist() } }
    var reminderMinute: Int { didSet { persist() } }
    var repeatOverdue: Bool { didSet { persist() } }
    var hemisphere: Hemisphere { didSet { persist() } }
    var seasonOverride: Season? { didSet { persist() } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let s = Self.load(defaults) ?? Snapshot(userName: "", notificationsEnabled: false, reminderHour: 9,
                                                 reminderMinute: 0, repeatOverdue: true, hemisphere: .north,
                                                 seasonOverride: nil)
        userName = s.userName
        notificationsEnabled = s.notificationsEnabled
        reminderHour = s.reminderHour
        reminderMinute = s.reminderMinute
        repeatOverdue = s.repeatOverdue
        hemisphere = s.hemisphere
        seasonOverride = s.seasonOverride
    }

    var snapshot: Snapshot {
        Snapshot(userName: userName, notificationsEnabled: notificationsEnabled, reminderHour: reminderHour,
                 reminderMinute: reminderMinute, repeatOverdue: repeatOverdue, hemisphere: hemisphere,
                 seasonOverride: seasonOverride)
    }

    func apply(_ s: Snapshot) {
        userName = s.userName
        notificationsEnabled = s.notificationsEnabled
        reminderHour = min(23, max(0, s.reminderHour))
        reminderMinute = min(59, max(0, s.reminderMinute))
        repeatOverdue = s.repeatOverdue
        hemisphere = s.hemisphere
        seasonOverride = s.seasonOverride
    }

    var notifSettings: NotifSettings {
        NotifSettings(hour: reminderHour, minute: reminderMinute, repeatOverdue: repeatOverdue)
    }

    func currentSeason(provider: DateProvider = .system) -> Season {
        seasonOverride ?? Season.current(for: provider.now(), hemisphere: hemisphere, calendar: provider.calendar)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(snapshot) { defaults.set(data, forKey: Self.key) }
    }

    private static func load(_ defaults: UserDefaults) -> Snapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }
}
