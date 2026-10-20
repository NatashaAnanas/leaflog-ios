import XCTest
import SwiftData
import UserNotifications
@testable import Leaflog

/// Изменяемые часы: тесты не привязаны к сегодняшнему дню.
final class TestClock: @unchecked Sendable {
    var date: Date
    init(_ date: Date) { self.date = date }
}

func makeCal(_ tz: String = "Europe/Moscow") -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: tz)!
    c.firstWeekday = 2
    return c
}

func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ mi: Int = 0, _ cal: Calendar = makeCal()) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: mi))!
}

func comps(_ date: Date, _ cal: Calendar = makeCal()) -> DateComponents {
    cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
}

@MainActor
struct Env {
    let container: ModelContainer
    let context: ModelContext
    let clock: TestClock
    let cal: Calendar
    let provider: DateProvider
    let photos: PhotoStore
    let repo: CareRepository
    let settings: AppSettings
    let center: FakeNotificationCenter
    let service: NotificationService
    let tmp: URL

    var types: [CareType] { repo.allTypes() }
    func type(_ key: String) -> CareType { types.first { $0.builtinKey == key }! }

    init(now: Date = day(2026, 10, 15, 10, 0), tz: String = "Europe/Moscow", container: ModelContainer? = nil) throws {
        let cal = makeCal(tz)
        self.cal = cal
        self.clock = TestClock(now)
        let clock = self.clock
        self.provider = DateProvider(now: { clock.date }, calendar: cal)
        self.container = try container ?? PersistenceFactory.makeContainer(inMemory: true)
        self.context = ModelContext(self.container)
        self.tmp = FileManager.default.temporaryDirectory.appendingPathComponent("leaflog-test-\(UUID().uuidString)")
        self.photos = PhotoStore(root: tmp)
        let defaults = UserDefaults(suiteName: "leaflog-test-\(UUID().uuidString)")!
        self.settings = AppSettings(defaults: defaults)
        self.center = FakeNotificationCenter()
        self.service = NotificationService(center: center, settings: settings, context: context, provider: provider)
        self.repo = CareRepository(context: context, provider: provider, photos: photos, notifier: nil)
        try repo.ensureBuiltInCareTypes()
    }

    func plant(_ name: String = "Монстера") throws -> Plant { try repo.addPlant(name: name) }
}

final class FakeNotificationCenter: NotificationCenterProtocol {
    struct Item { var id: String; var title: String; var body: String; var fire: Date; var category: String; var userInfo: [String: Any] }
    var status: UNAuthorizationStatus = .authorized
    var pending: [String: Item] = [:]
    var deliveredItems: [(id: String, ruleIDs: [String])] = []
    var removedDelivered: [String] = []
    var requestCount = 0

    func authorizationStatus() async -> UNAuthorizationStatus { status }
    func requestAuthorization() async throws -> Bool { requestCount += 1; status = .authorized; return true }
    func pendingIdentifiers() async -> [String] { Array(pending.keys) }
    func add(identifier: String, title: String, body: String, fireDate: Date, calendar: Calendar, categoryID: String,
             threadID: String, userInfo: [String: Any]) async throws {
        pending[identifier] = Item(id: identifier, title: title, body: body, fire: fireDate, category: categoryID, userInfo: userInfo)
    }
    func removePending(_ ids: [String]) { ids.forEach { pending.removeValue(forKey: $0) } }
    func delivered() async -> [(id: String, ruleIDs: [String])] { deliveredItems }
    func removeDelivered(_ ids: [String]) { removedDelivered += ids; deliveredItems.removeAll { ids.contains($0.id) } }
    func registerCategories() {}
}
