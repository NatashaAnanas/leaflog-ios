import Foundation
import SwiftData
import UIKit

/// Синтетические демо-данные для Preview, тестов и скриншотов.
/// Включаются только аргументом запуска `-LEAFLOG_DEMO` и живут в изолированном хранилище (память + временная папка):
/// обычная коллекция пользователя никогда не заполняется автоматически.
enum DemoData {
    static var isRequested: Bool {
        let a = ProcessInfo.processInfo.arguments
        return a.contains("-LEAFLOG_DEMO") || a.contains("-LEAFLOG_EMPTY")
    }
    /// `-LEAFLOG_EMPTY`: изолированное пустое хранилище для проверки пустых состояний и создания данных.
    static var isEmpty: Bool { ProcessInfo.processInfo.arguments.contains("-LEAFLOG_EMPTY") }

    @MainActor
    static func makeEnvironment() throws -> AppEnvironment {
        let container = try PersistenceFactory.makeContainer(inMemory: true)
        let defaults = UserDefaults(suiteName: "leaflog.demo.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        settings.userName = "Алиса"
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("leaflog-demo-\(UUID().uuidString)")
        let env = AppEnvironment(container: container, settings: settings, photos: PhotoStore(root: root))
        env.bootstrap()
        if !isEmpty { try seed(env) }
        return env
    }

    @MainActor
    static func seed(_ env: AppEnvironment) throws {
        let repo = env.repository
        let cal = env.provider.calendar
        let now = env.provider.now()
        func ago(_ d: Int, hour: Int = 9) -> Date {
            let base = cal.date(byAdding: .day, value: -d, to: env.provider.today) ?? now
            return cal.date(bySettingHour: hour, minute: 15, second: 0, of: base) ?? base
        }
        let types = repo.allTypes()
        func type(_ key: String) -> CareType { types.first { $0.builtinKey == key }! }
        func img(_ seed: Int, symbol: String = "leaf.fill") throws -> ProcessedImage {
            try ImageProcessing.process(placeholder(seed, symbol: symbol))
        }

        let kal = try repo.addPlant(name: "Каланхоэ", species: "Kalanchoe blossfeldiana", photo: try img(0, symbol: "camera.macro"), photoTakenAt: ago(40), referenceProfileID: "kalanchoe")
        let orchid = try repo.addPlant(name: "Орхидея", species: "Phalaenopsis", photo: try img(1, symbol: "sparkle"), photoTakenAt: ago(20), referenceProfileID: "phalaenopsis")
        let monstera = try repo.addPlant(name: "Монстера у большого южного окна в гостиной", species: "Monstera deliciosa", photo: try img(2), photoTakenAt: ago(100), referenceProfileID: "monstera")
        let aloe = try repo.addPlant(name: "Алоэ", photo: nil)
        let old = try repo.addPlant(name: "Старый фикус", species: "Ficus benjamina")

        func rule(_ p: Plant, _ key: String, _ r: Recurrence, anchorAgo: Int) throws {
            try repo.setRule(plant: p, typeID: type(key).id, recurrence: r, anchorDate: ago(anchorAgo), anchorKind: .lastCare)
        }
        // Каланхоэ: всё в порядке.
        try rule(kal, "water", Recurrence(value: 10, unit: .day), anchorAgo: 2)
        try repo.logCare(plant: kal, typeID: type("water").id, date: ago(2), comment: "Немного, под корень", debounce: false)
        // Орхидея: просрочен полив, сегодня опрыскивание.
        try rule(orchid, "water", Recurrence(value: 7, unit: .day), anchorAgo: 12)
        try repo.logCare(plant: orchid, typeID: type("water").id, date: ago(12), debounce: false)
        try rule(orchid, "mist", Recurrence(value: 3, unit: .day), anchorAgo: 3)
        try repo.logCare(plant: orchid, typeID: type("mist").id, date: ago(3), debounce: false)
        // Монстера: несколько видов ухода и ежемесячное удобрение.
        try rule(monstera, "water", Recurrence(value: 1, unit: .week), anchorAgo: 4)
        for d in [25, 18, 11, 4] { try repo.logCare(plant: monstera, typeID: type("water").id, date: ago(d), debounce: false) }
        try rule(monstera, "fertilize", Recurrence(value: 1, unit: .month), anchorAgo: 20)
        try repo.logCare(plant: monstera, typeID: type("fertilize").id, date: ago(20), comment: "Слабый раствор", debounce: false)
        try repo.logCare(plant: monstera, typeID: type("shower").id, date: ago(9), debounce: false)
        try repo.logCare(plant: monstera, typeID: type("repot").id, date: ago(60), comment: "Новый горшок на размер больше", debounce: false)
        try repo.logCare(plant: monstera, typeID: type("mist").id, date: ago(4, hour: 18), debounce: false)
        // Фото монстеры: дата снимка отличается от даты добавления.
        let old1 = try repo.addPhoto(to: monstera, image: try img(3), takenAt: ago(150))
        old1.caption = "Первый лист, как купили"
        _ = try repo.addPhoto(to: monstera, image: try img(4), takenAt: ago(45))
        // Заметки.
        _ = try repo.addNote(to: monstera, text: "Не любит сквозняки. Поворачивать на 90° раз в неделю.", showsDate: false)
        _ = try repo.addNote(to: monstera, text: "Появился новый лист с разрезами 🌿", showsDate: true)
        _ = try repo.addNote(to: kal, text: "Цветёт уже третью неделю.", showsDate: true)
        try repo.setArchived(old, true)
        try repo.commit()
        _ = aloe
    }

    static func placeholder(_ seed: Int, symbol: String) -> Data {
        let palettes: [(UIColor, UIColor)] = [
            (UIColor(red: 0.85, green: 0.93, blue: 0.80, alpha: 1), UIColor(red: 0.35, green: 0.60, blue: 0.35, alpha: 1)),
            (UIColor(red: 0.96, green: 0.88, blue: 0.92, alpha: 1), UIColor(red: 0.70, green: 0.42, blue: 0.62, alpha: 1)),
            (UIColor(red: 0.84, green: 0.92, blue: 0.86, alpha: 1), UIColor(red: 0.18, green: 0.45, blue: 0.32, alpha: 1)),
            (UIColor(red: 0.93, green: 0.90, blue: 0.80, alpha: 1), UIColor(red: 0.50, green: 0.55, blue: 0.25, alpha: 1)),
            (UIColor(red: 0.88, green: 0.90, blue: 0.95, alpha: 1), UIColor(red: 0.30, green: 0.45, blue: 0.40, alpha: 1)),
        ]
        let (a, b) = palettes[seed % palettes.count]
        let size = CGSize(width: 1200, height: 1200)
        return UIGraphicsImageRenderer(size: size).jpegData(withCompressionQuality: 0.9) { ctx in
            let colors = [a.cgColor, b.cgColor] as CFArray
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            let cfg = UIImage.SymbolConfiguration(pointSize: 520, weight: .regular)
            if let img = UIImage(systemName: symbol, withConfiguration: cfg)?.withTintColor(UIColor.white.withAlphaComponent(0.85), renderingMode: .alwaysOriginal) {
                img.draw(at: CGPoint(x: (size.width - img.size.width) / 2, y: (size.height - img.size.height) / 2))
            }
        }
    }
}
