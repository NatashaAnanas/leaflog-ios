import Foundation
import SwiftData

enum LeaflogError: LocalizedError {
    case saveFailed(String)
    case invalidInput(String)
    var errorDescription: String? {
        switch self {
        case .saveFailed(let m): String(localized: "Не удалось сохранить данные: \(m)")
        case .invalidInput(let m): m
        }
    }
}

@MainActor
protocol NotificationSyncing: AnyObject {
    func requestSync()
}

struct LogResult {
    let event: CareEvent
    /// true — запись не создана: сработала защита от двойного нажатия или повторная обработка того же действия.
    let wasDuplicate: Bool
}

/// Единственная точка изменения данных: каждая операция сохраняет контекст, откатывается при ошибке
/// и запрашивает пересчёт уведомлений.
@MainActor
final class CareRepository {
    let context: ModelContext
    let provider: DateProvider
    let photos: PhotoStore
    weak var notifier: NotificationSyncing?
    /// Окно защиты от случайного двойного сохранения.
    static let doubleTapWindow: TimeInterval = 2

    init(context: ModelContext, provider: DateProvider = .system, photos: PhotoStore, notifier: NotificationSyncing? = nil) {
        self.context = context
        self.provider = provider
        self.photos = photos
        self.notifier = notifier
    }

    func commit(sync: Bool = true) throws {
        do { try context.save() }
        catch {
            context.rollback()
            throw LeaflogError.saveFailed(error.localizedDescription)
        }
        if sync { notifier?.requestSync() }
    }

    // MARK: Виды ухода

    func ensureBuiltInCareTypes() throws {
        let existing = try context.fetch(FetchDescriptor<CareType>())
        var changed = false
        for (i, def) in BuiltinCare.all.enumerated() where !existing.contains(where: { $0.builtinKey == def.key }) {
            context.insert(CareType(builtinKey: def.key, name: def.name, colorHex: def.colorHex, iconName: def.icon, sortOrder: i))
            changed = true
        }
        if changed { try commit(sync: false) }
    }

    @discardableResult
    func addCareType(name: String, colorHex: String, icon: String) throws -> CareType {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { throw LeaflogError.invalidInput(String(localized: "Введите название вида ухода.")) }
        let all = try context.fetch(FetchDescriptor<CareType>())
        let t = CareType(name: n, colorHex: colorHex, iconName: icon, sortOrder: (all.map(\.sortOrder).max() ?? 0) + 1)
        context.insert(t)
        try commit()
        return t
    }

    /// Вид ухода физически не удаляется: история продолжает показывать его название, цвет и иконку.
    func setCareType(_ type: CareType, enabled: Bool) throws {
        type.isEnabled = enabled
        try commit()
    }

    // MARK: Растения

    @discardableResult
    func addPlant(name: String, species: String = "", photo: ProcessedImage? = nil, photoTakenAt: Date? = nil,
                  referenceProfileID: String? = nil) throws -> Plant {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { throw LeaflogError.invalidInput(String(localized: "Введите название растения.")) }
        let plant = Plant(name: n, species: species.trimmingCharacters(in: .whitespacesAndNewlines), createdAt: provider.now())
        plant.referenceProfileID = referenceProfileID
        context.insert(plant)
        var storedID: UUID?
        if let photo {
            let id = UUID()
            do { try photos.write(photo, id: id) } catch {
                context.delete(plant)
                throw LeaflogError.saveFailed(error.localizedDescription)
            }
            storedID = id
            let rec = PlantPhoto(id: id, plant: plant, addedAt: provider.now(), takenAt: photoTakenAt ?? photo.takenAt ?? provider.now())
            context.insert(rec)
            plant.coverPhotoID = id
        }
        do { try commit() } catch {
            if let storedID { photos.delete(storedID) }
            throw error
        }
        return plant
    }

    func deletePlant(_ plant: Plant) throws {
        let ids = plant.photos.map(\.id)
        context.delete(plant)
        try commit()
        ids.forEach(photos.delete)
    }

    func setArchived(_ plant: Plant, _ archived: Bool) throws {
        plant.isArchived = archived
        plant.archivedAt = archived ? provider.now() : nil
        try commit()
    }

    // MARK: Расписание

    @discardableResult
    func setRule(plant: Plant, typeID: UUID, recurrence: Recurrence, anchorDate: Date?, anchorKind: AnchorKind,
                 notifications: Bool = true) throws -> CareRule {
        let rule: CareRule
        if let existing = plant.rules.first(where: { $0.careTypeID == typeID }) {
            rule = existing
            rule.recurrence = recurrence
            rule.anchorDate = anchorDate
            rule.anchorKind = anchorKind
        } else {
            rule = CareRule(plant: plant, careTypeID: typeID, recurrence: recurrence, anchorDate: anchorDate,
                            anchorKind: anchorKind, createdAt: provider.now())
            context.insert(rule)
        }
        rule.notificationsEnabled = notifications
        rule.snoozedUntil = nil
        try commit()
        return rule
    }

    /// Удаляет только правило (переход к ручному учёту). История выполнений сохраняется.
    func removeRule(_ rule: CareRule) throws {
        context.delete(rule)
        try commit()
    }

    /// Отложить напоминание — не выполнение: срок и история не меняются.
    func snooze(_ rule: CareRule, until day: Date) throws {
        rule.snoozedUntil = provider.calendar.startOfDay(for: day)
        try commit()
    }

    // MARK: Выполнения

    @discardableResult
    func logCare(plant: Plant, typeID: UUID, date: Date? = nil, comment: String = "", sourceKey: String? = nil,
                 debounce: Bool = true) throws -> LogResult {
        let now = provider.now()
        if let sourceKey, let dup = plant.events.first(where: { $0.sourceKey == sourceKey }) {
            return LogResult(event: dup, wasDuplicate: true)
        }
        // Защита от двойного нажатия: та же пара растение+вид, созданная только что.
        if debounce, let recent = plant.events.first(where: {
            $0.careTypeID == typeID && abs($0.createdAt.timeIntervalSince(now)) < Self.doubleTapWindow
        }) {
            return LogResult(event: recent, wasDuplicate: true)
        }
        let when = min(date ?? now, now)
        let event = CareEvent(plant: plant, careTypeID: typeID, date: when,
                              comment: comment.trimmingCharacters(in: .whitespacesAndNewlines),
                              createdAt: now, sourceKey: sourceKey)
        context.insert(event)
        try commit()
        return LogResult(event: event, wasDuplicate: false)
    }

    func updateEvent(_ event: CareEvent, date: Date, comment: String) throws {
        event.date = min(date, provider.now())
        event.comment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        event.updatedAt = provider.now()
        try commit()
    }

    func deleteEvent(_ event: CareEvent) throws {
        context.delete(event)
        try commit()
    }

    // MARK: Фото

    @discardableResult
    func addPhoto(to plant: Plant, image: ProcessedImage, takenAt: Date? = nil) throws -> PlantPhoto {
        let id = UUID()
        do { try photos.write(image, id: id) } catch { throw LeaflogError.saveFailed(error.localizedDescription) }
        let rec = PlantPhoto(id: id, plant: plant, addedAt: provider.now(), takenAt: takenAt ?? image.takenAt ?? provider.now())
        context.insert(rec)
        if plant.coverPhotoID == nil { plant.coverPhotoID = id }
        do { try commit(sync: false) } catch { photos.delete(id); throw error }
        return rec
    }

    func updatePhoto(_ photo: PlantPhoto, takenAt: Date, caption: String) throws {
        photo.takenAt = takenAt   // addedAt неизменяем
        photo.caption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        try commit(sync: false)
    }

    func setCover(_ photo: PlantPhoto) throws {
        photo.plant?.coverPhotoID = photo.id
        try commit(sync: false)
    }

    func deletePhoto(_ photo: PlantPhoto) throws {
        let id = photo.id
        let plant = photo.plant
        context.delete(photo)
        if plant?.coverPhotoID == id {
            plant?.coverPhotoID = plant?.photos.filter { $0.id != id }.sorted { $0.takenAt > $1.takenAt }.first?.id
        }
        try commit(sync: false)
        photos.delete(id)
    }

    // MARK: Заметки

    @discardableResult
    func addNote(to plant: Plant, text: String, showsDate: Bool) throws -> PlantNote {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw LeaflogError.invalidInput(String(localized: "Заметка пуста.")) }
        let note = PlantNote(plant: plant, text: t, showsDate: showsDate, createdAt: provider.now())
        context.insert(note)
        try commit(sync: false)
        return note
    }

    func updateNote(_ note: PlantNote, text: String, showsDate: Bool) throws {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw LeaflogError.invalidInput(String(localized: "Заметка пуста.")) }
        note.text = t
        note.showsDate = showsDate
        note.updatedAt = provider.now()
        try commit(sync: false)
    }

    func deleteNote(_ note: PlantNote) throws {
        context.delete(note)
        try commit(sync: false)
    }

    // MARK: Служебное

    func allTypes() -> [CareType] { (try? context.fetch(FetchDescriptor<CareType>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? [] }
    func allPlants() -> [Plant] { (try? context.fetch(FetchDescriptor<Plant>())) ?? [] }
}
