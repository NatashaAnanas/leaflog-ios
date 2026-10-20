import Foundation
import SwiftData

@Model
final class Plant {
    @Attribute(.unique) var id: UUID
    var name: String
    /// Вид/сорт — отдельно от домашнего названия, необязательно.
    var species: String
    var createdAt: Date
    var isArchived: Bool
    var archivedAt: Date?
    var coverPhotoID: UUID?
    /// Выбранный справочный профиль (ключ из TipsCatalog) или nil.
    var referenceProfileID: String?
    /// Собственные рекомендации пользователя.
    var ownTips: String
    var notificationsEnabled: Bool

    @Relationship(deleteRule: .cascade, inverse: \PlantPhoto.plant) var photos: [PlantPhoto] = []
    @Relationship(deleteRule: .cascade, inverse: \PlantNote.plant) var notes: [PlantNote] = []
    @Relationship(deleteRule: .cascade, inverse: \CareRule.plant) var rules: [CareRule] = []
    @Relationship(deleteRule: .cascade, inverse: \CareEvent.plant) var events: [CareEvent] = []

    init(id: UUID = UUID(), name: String, species: String = "", createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.species = species
        self.createdAt = createdAt
        self.isArchived = false
        self.archivedAt = nil
        self.coverPhotoID = nil
        self.referenceProfileID = nil
        self.ownTips = ""
        self.notificationsEnabled = true
    }
}

/// Вид ухода. Никогда не удаляется физически (история ссылается на него) — только отключается.
@Model
final class CareType {
    @Attribute(.unique) var id: UUID
    /// Ключ предустановленного вида (water, mist, …) или nil для собственного.
    var builtinKey: String?
    var name: String
    var colorHex: String
    var iconName: String
    var isEnabled: Bool
    var sortOrder: Int
    var notificationsEnabled: Bool

    init(id: UUID = UUID(), builtinKey: String? = nil, name: String, colorHex: String, iconName: String,
         isEnabled: Bool = true, sortOrder: Int = 0) {
        self.id = id
        self.builtinKey = builtinKey
        self.name = name
        self.colorHex = colorHex
        self.iconName = iconName
        self.isEnabled = isEnabled
        self.sortOrder = sortOrder
        self.notificationsEnabled = true
    }
}

/// Правило повторения конкретного вида ухода у конкретного растения. Нет правила — только ручной учёт.
@Model
final class CareRule {
    @Attribute(.unique) var id: UUID
    var plant: Plant?
    var careTypeID: UUID
    var intervalValue: Int
    var intervalUnitRaw: String
    /// Используется только пока нет выполнений.
    var anchorDate: Date?
    var anchorKindRaw: String
    var notificationsEnabled: Bool
    /// «Отложить напоминание»: влияет только на уведомления, не на срок и не на историю.
    var snoozedUntil: Date?
    var createdAt: Date

    init(id: UUID = UUID(), plant: Plant?, careTypeID: UUID, recurrence: Recurrence,
         anchorDate: Date?, anchorKind: AnchorKind, createdAt: Date = Date()) {
        self.id = id
        self.plant = plant
        self.careTypeID = careTypeID
        self.intervalValue = recurrence.value
        self.intervalUnitRaw = recurrence.unit.rawValue
        self.anchorDate = anchorDate
        self.anchorKindRaw = anchorKind.rawValue
        self.notificationsEnabled = true
        self.snoozedUntil = nil
        self.createdAt = createdAt
    }

    var recurrence: Recurrence {
        get { Recurrence(value: intervalValue, unit: IntervalUnit(rawValue: intervalUnitRaw) ?? .day) }
        set { intervalValue = newValue.value; intervalUnitRaw = newValue.unit.rawValue }
    }
    var anchorKind: AnchorKind {
        get { AnchorKind(rawValue: anchorKindRaw) ?? .firstDue }
        set { anchorKindRaw = newValue.rawValue }
    }
}

/// Факт ухода в конкретный момент.
@Model
final class CareEvent {
    @Attribute(.unique) var id: UUID
    var plant: Plant?
    var careTypeID: UUID
    var date: Date
    var comment: String
    var createdAt: Date
    var updatedAt: Date
    /// Ключ идемпотентности (например, действие «Выполнено» из уведомления).
    var sourceKey: String?

    init(id: UUID = UUID(), plant: Plant?, careTypeID: UUID, date: Date, comment: String = "",
         createdAt: Date = Date(), sourceKey: String? = nil) {
        self.id = id
        self.plant = plant
        self.careTypeID = careTypeID
        self.date = date
        self.comment = comment
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.sourceKey = sourceKey
    }
}

@Model
final class PlantPhoto {
    @Attribute(.unique) var id: UUID
    var plant: Plant?
    /// Неизменяемая дата добавления в приложение.
    var addedAt: Date
    /// Редактируемая дата снимка.
    var takenAt: Date
    var caption: String

    init(id: UUID = UUID(), plant: Plant?, addedAt: Date = Date(), takenAt: Date, caption: String = "") {
        self.id = id
        self.plant = plant
        self.addedAt = addedAt
        self.takenAt = takenAt
        self.caption = caption
    }
}

@Model
final class PlantNote {
    @Attribute(.unique) var id: UUID
    var plant: Plant?
    var text: String
    var createdAt: Date
    var updatedAt: Date
    var showsDate: Bool

    init(id: UUID = UUID(), plant: Plant?, text: String, showsDate: Bool = true, createdAt: Date = Date()) {
        self.id = id
        self.plant = plant
        self.text = text
        self.showsDate = showsDate
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}

// MARK: - Schema

enum LeaflogSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Plant.self, CareType.self, CareRule.self, CareEvent.self, PlantPhoto.self, PlantNote.self]
    }
}

enum LeaflogMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [LeaflogSchemaV1.self] }
    /// Версия 1 — первая; будущие версии добавляют этапы здесь, а не пересоздают хранилище.
    static var stages: [MigrationStage] { [] }
}

enum PersistenceFactory {
    static func makeContainer(inMemory: Bool = false, url: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: LeaflogSchemaV1.self)
        let config: ModelConfiguration
        if let url {
            config = ModelConfiguration(schema: schema, url: url)
        } else {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        }
        return try ModelContainer(for: schema, migrationPlan: LeaflogMigrationPlan.self, configurations: [config])
    }
}

// MARK: - Предустановленные виды ухода

enum BuiltinCare {
    struct Def { let key: String; let name: String; let colorHex: String; let icon: String }
    static let all: [Def] = [
        Def(key: "water", name: "Полив", colorHex: "8E6CEF", icon: "drop.fill"),
        Def(key: "mist", name: "Опрыскивание", colorHex: "26A69A", icon: "humidity.fill"),
        Def(key: "fertilize", name: "Удобрение", colorHex: "E0A100", icon: "sparkle"),
        Def(key: "repot", name: "Пересадка", colorHex: "B5651D", icon: "arrow.triangle.2.circlepath"),
        Def(key: "shower", name: "Душ", colorHex: "2F80ED", icon: "shower.fill"),
    ]
}
