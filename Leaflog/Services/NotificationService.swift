import Foundation
import SwiftData
import UserNotifications
import UIKit

/// Тонкая обёртка над UNUserNotificationCenter, чтобы подменять её в тестах.
protocol NotificationCenterProtocol: AnyObject {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func pendingIdentifiers() async -> [String]
    func add(identifier: String, title: String, body: String, fireDate: Date, calendar: Calendar,
             categoryID: String, threadID: String, userInfo: [String: Any]) async throws
    func removePending(_ ids: [String])
    /// Доставленные уведомления приложения: (id, ruleIDs).
    func delivered() async -> [(id: String, ruleIDs: [String])]
    func removeDelivered(_ ids: [String])
    func registerCategories()
}

final class SystemNotificationCenter: NotificationCenterProtocol {
    private let center = UNUserNotificationCenter.current()
    static let singleCategory = "leaflog.single"
    static let digestCategory = "leaflog.digest"
    static let doneAction = "leaflog.action.done"
    static let snoozeAction = "leaflog.action.snooze"

    func authorizationStatus() async -> UNAuthorizationStatus { await center.notificationSettings().authorizationStatus }
    func requestAuthorization() async throws -> Bool { try await center.requestAuthorization(options: [.alert, .sound, .badge]) }
    func pendingIdentifiers() async -> [String] { await center.pendingNotificationRequests().map(\.identifier) }

    func add(identifier: String, title: String, body: String, fireDate: Date, calendar: Calendar,
             categoryID: String, threadID: String, userInfo: [String: Any]) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = categoryID
        content.threadIdentifier = threadID
        content.userInfo = userInfo
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    func removePending(_ ids: [String]) { center.removePendingNotificationRequests(withIdentifiers: ids) }

    func delivered() async -> [(id: String, ruleIDs: [String])] {
        await center.deliveredNotifications().map {
            ($0.request.identifier, $0.request.content.userInfo["ruleIDs"] as? [String] ?? [])
        }
    }
    func removeDelivered(_ ids: [String]) { center.removeDeliveredNotifications(withIdentifiers: ids) }

    func registerCategories() {
        let done = UNNotificationAction(identifier: Self.doneAction, title: String(localized: "Выполнено"), options: [])
        let snooze = UNNotificationAction(identifier: Self.snoozeAction, title: String(localized: "Отложить до завтра"), options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.singleCategory, actions: [done, snooze], intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.digestCategory, actions: [], intentIdentifiers: []),
        ])
    }
}

enum NotificationActionOutcome: Equatable { case logged, duplicate, stale, notFound, snoozed }

/// Сверка расписаний и локальных уведомлений. Источник истины — правила и история в базе;
/// запросы в системе пересоздаются из них при каждой сверке.
@MainActor
final class NotificationService: NotificationSyncing {
    private let center: NotificationCenterProtocol
    private let settings: AppSettings
    private let context: ModelContext
    private let provider: DateProvider
    private var running = false
    private var again = false
    private(set) var lastPlan: [PlannedNotification] = []

    init(center: NotificationCenterProtocol, settings: AppSettings, context: ModelContext, provider: DateProvider = .system) {
        self.center = center
        self.settings = settings
        self.context = context
        self.provider = provider
    }

    func registerCategories() { center.registerCategories() }

    func requestSync() {
        again = true
        guard !running else { return }
        running = true
        Task { [weak self] in
            while let self, self.again {
                self.again = false
                await self.sync()
            }
            self?.running = false
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus { await center.authorizationStatus() }

    /// Запрашивается в момент включения напоминаний. Возвращает true, если разрешение получено.
    func enableReminders() async -> Bool {
        let status = await center.authorizationStatus()
        var granted = status == .authorized || status == .provisional || status == .ephemeral
        if status == .notDetermined { granted = (try? await center.requestAuthorization()) ?? false }
        settings.notificationsEnabled = granted
        await sync()
        return granted
    }

    func currentTasks() -> [CareTask] {
        let plants = (try? context.fetch(FetchDescriptor<Plant>())) ?? []
        let types = (try? context.fetch(FetchDescriptor<CareType>())) ?? []
        return TaskBuilder.tasks(plants: plants, types: types, provider: provider)
    }

    /// Полная сверка: пересоздаёт ожидающие запросы из сохранённых правил и убирает устаревшие доставленные.
    func sync() async {
        let tasks = currentTasks()
        let pending = await center.pendingIdentifiers().filter { $0.hasPrefix(NotificationPlanner.idPrefix) }
        center.removePending(pending)
        await cleanDelivered(tasks: tasks)

        let status = await center.authorizationStatus()
        let allowed = status == .authorized || status == .provisional || status == .ephemeral
        guard settings.notificationsEnabled, allowed else { lastPlan = []; return }

        let items = TaskBuilder.notifItems(from: tasks)
        let plan = NotificationPlanner.plan(items: items, settings: settings.notifSettings,
                                            now: provider.now(), calendar: provider.calendar)
        lastPlan = plan
        for p in plan {
            let info: [String: Any] = [
                "plantIDs": p.plantIDs.map(\.uuidString),
                "ruleIDs": p.ruleIDs.map(\.uuidString),
                "dueKey": p.dueKey ?? "",
            ]
            try? await center.add(identifier: p.identifier, title: p.title, body: p.body, fireDate: p.fireDate,
                                  calendar: provider.calendar,
                                  categoryID: p.isSingle ? SystemNotificationCenter.singleCategory : SystemNotificationCenter.digestCategory,
                                  threadID: "leaflog.care", userInfo: info)
        }
    }

    /// Убирает из центра уведомлений доставленные напоминания, по которым больше нечего делать.
    private func cleanDelivered(tasks: [CareTask]) async {
        let actionable = Set(tasks.filter { $0.status.isActionable }.map { $0.rule.id.uuidString })
        let stale = await center.delivered().filter { d in
            d.id.hasPrefix(NotificationPlanner.idPrefix) && !d.ruleIDs.contains(where: actionable.contains)
        }.map(\.id)
        if !stale.isEmpty { center.removeDelivered(stale) }
    }

    // MARK: Действия из уведомления

    /// Идемпотентно: повторная обработка того же уведомления не создаёт вторую запись.
    func handleDone(ruleID: UUID, dueKey: String, repository: CareRepository) -> NotificationActionOutcome {
        guard let rule = (try? context.fetch(FetchDescriptor<CareRule>(predicate: #Predicate { $0.id == ruleID })))?.first,
              let plant = rule.plant else { return .notFound }
        let sourceKey = "notif-done:\(ruleID.uuidString):\(dueKey)"
        if plant.events.contains(where: { $0.sourceKey == sourceKey }) { return .duplicate }
        let types = Dictionary(uniqueKeysWithValues: ((try? context.fetch(FetchDescriptor<CareType>())) ?? []).map { ($0.id, $0) })
        guard let task = TaskBuilder.task(for: rule, types: types, provider: provider),
              NotificationPlanner.dayKey(task.dueDay, calendar: provider.calendar) == dueKey else { return .stale }
        guard let result = try? repository.logCare(plant: plant, typeID: rule.careTypeID, sourceKey: sourceKey) else { return .notFound }
        return result.wasDuplicate ? .duplicate : .logged
    }

    func handleSnooze(ruleID: UUID, repository: CareRepository) -> NotificationActionOutcome {
        guard let rule = (try? context.fetch(FetchDescriptor<CareRule>(predicate: #Predicate { $0.id == ruleID })))?.first
        else { return .notFound }
        let tomorrow = provider.calendar.date(byAdding: .day, value: 1, to: provider.today) ?? provider.today
        try? repository.snooze(rule, until: tomorrow)
        return .snoozed
    }
}

// MARK: - Делегат и маршрутизация

enum AppRoute: Equatable {
    case plant(UUID)
    case tasks
}

@Observable
final class AppRouter {
    var route: AppRoute?
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    @MainActor static var environment: AppEnvironment?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let plantIDs = (info["plantIDs"] as? [String] ?? []).compactMap(UUID.init)
        let ruleIDs = (info["ruleIDs"] as? [String] ?? []).compactMap(UUID.init)
        let dueKey = info["dueKey"] as? String ?? ""
        let action = response.actionIdentifier
        await MainActor.run {
            guard let env = AppDelegate.environment else { return }
            switch action {
            case SystemNotificationCenter.doneAction:
                if let rid = ruleIDs.first {
                    _ = env.notifications.handleDone(ruleID: rid, dueKey: dueKey, repository: env.repository)
                    env.notifications.requestSync()
                }
            case SystemNotificationCenter.snoozeAction:
                if let rid = ruleIDs.first {
                    _ = env.notifications.handleSnooze(ruleID: rid, repository: env.repository)
                }
            default:
                if plantIDs.count == 1, let id = plantIDs.first { env.router.route = .plant(id) }
                else { env.router.route = .tasks }
            }
        }
    }
}
