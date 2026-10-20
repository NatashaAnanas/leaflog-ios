import Foundation
import CryptoKit
import SwiftData

// MARK: - Формат

/// Файл `.leaflogbackup`:
///   "LEAFLOGBK1\n" | UInt64 BE длина манифеста | манифест JSON | блобы фото (в порядке manifest.photos) | SHA-256 всего перед ним (32 байта).
enum BackupFormat {
    static let magic = Data("LEAFLOGBK1\n".utf8)
    static let currentVersion = 1
    static let fileExtension = "leaflogbackup"
}

struct BackupManifest: Codable {
    var formatVersion: Int
    var appVersion: String
    var exportedAt: Date
    var settings: AppSettings.Snapshot
    var careTypes: [CareTypeDTO]
    var plants: [PlantDTO]
    var photos: [PhotoDTO]

    struct CareTypeDTO: Codable {
        var id: UUID; var builtinKey: String?; var name: String; var colorHex: String; var iconName: String
        var isEnabled: Bool; var sortOrder: Int; var notificationsEnabled: Bool
    }
    struct RuleDTO: Codable {
        var id: UUID; var careTypeID: UUID; var intervalValue: Int; var intervalUnit: String
        var anchorDate: Date?; var anchorKind: String; var notificationsEnabled: Bool; var snoozedUntil: Date?; var createdAt: Date
    }
    struct EventDTO: Codable {
        var id: UUID; var careTypeID: UUID; var date: Date; var comment: String
        var createdAt: Date; var updatedAt: Date; var sourceKey: String?
    }
    struct NoteDTO: Codable {
        var id: UUID; var text: String; var createdAt: Date; var updatedAt: Date; var showsDate: Bool
    }
    struct PlantDTO: Codable {
        var id: UUID; var name: String; var species: String; var createdAt: Date; var isArchived: Bool
        var archivedAt: Date?; var coverPhotoID: UUID?; var referenceProfileID: String?; var ownTips: String
        var notificationsEnabled: Bool
        var rules: [RuleDTO]; var events: [EventDTO]; var notes: [NoteDTO]
    }
    struct PhotoDTO: Codable {
        var id: UUID; var plantID: UUID; var addedAt: Date; var takenAt: Date; var caption: String
        var size: Int; var sha256: String
    }
}

struct BackupPreview {
    var manifest: BackupManifest
    var stagingDir: URL
    var plantCount: Int { manifest.plants.count }
    var photoCount: Int { manifest.photos.count }
    var eventCount: Int { manifest.plants.reduce(0) { $0 + $1.events.count } }
    var noteCount: Int { manifest.plants.reduce(0) { $0 + $1.notes.count } }
}

enum BackupError: LocalizedError {
    case notABackup, unsupportedVersion(Int), corrupted(String), invalidReferences(String)
    var errorDescription: String? {
        switch self {
        case .notABackup: String(localized: "Это не файл резервной копии Leaflog.")
        case .unsupportedVersion(let v): String(localized: "Версия формата \(v) не поддерживается этой версией приложения.")
        case .corrupted(let m): String(localized: "Файл повреждён: \(m)")
        case .invalidReferences(let m): String(localized: "Нарушена целостность данных: \(m)")
        }
    }
}

// MARK: - Сервис

@MainActor
final class BackupService {
    private let context: ModelContext
    private let photos: PhotoStore
    private let settings: AppSettings
    private let notifier: NotificationSyncing?

    init(context: ModelContext, photos: PhotoStore, settings: AppSettings, notifier: NotificationSyncing?) {
        self.context = context
        self.photos = photos
        self.settings = settings
        self.notifier = notifier
    }

    // MARK: Экспорт

    func makeManifest(now: Date = Date()) throws -> BackupManifest {
        let types = try context.fetch(FetchDescriptor<CareType>(sortBy: [SortDescriptor(\.sortOrder)]))
        let plants = try context.fetch(FetchDescriptor<Plant>(sortBy: [SortDescriptor(\.createdAt)]))
        let photoRecs = try context.fetch(FetchDescriptor<PlantPhoto>(sortBy: [SortDescriptor(\.addedAt)]))
        let photoDTOs: [BackupManifest.PhotoDTO] = try photoRecs.compactMap { p in
            guard let pid = p.plant?.id else { return nil }
            let data = try photos.readFull(p.id)
            return .init(id: p.id, plantID: pid, addedAt: p.addedAt, takenAt: p.takenAt, caption: p.caption,
                         size: data.count, sha256: Self.hex(SHA256.hash(data: data)))
        }
        return BackupManifest(
            formatVersion: BackupFormat.currentVersion,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
            exportedAt: now,
            settings: settings.snapshot,
            careTypes: types.map { .init(id: $0.id, builtinKey: $0.builtinKey, name: $0.name, colorHex: $0.colorHex,
                                         iconName: $0.iconName, isEnabled: $0.isEnabled, sortOrder: $0.sortOrder,
                                         notificationsEnabled: $0.notificationsEnabled) },
            plants: plants.map { p in
                .init(id: p.id, name: p.name, species: p.species, createdAt: p.createdAt, isArchived: p.isArchived,
                      archivedAt: p.archivedAt, coverPhotoID: p.coverPhotoID, referenceProfileID: p.referenceProfileID,
                      ownTips: p.ownTips, notificationsEnabled: p.notificationsEnabled,
                      rules: p.rules.map { .init(id: $0.id, careTypeID: $0.careTypeID, intervalValue: $0.intervalValue,
                                                 intervalUnit: $0.intervalUnitRaw, anchorDate: $0.anchorDate,
                                                 anchorKind: $0.anchorKindRaw, notificationsEnabled: $0.notificationsEnabled,
                                                 snoozedUntil: $0.snoozedUntil, createdAt: $0.createdAt) },
                      events: p.events.map { .init(id: $0.id, careTypeID: $0.careTypeID, date: $0.date, comment: $0.comment,
                                                   createdAt: $0.createdAt, updatedAt: $0.updatedAt, sourceKey: $0.sourceKey) },
                      notes: p.notes.map { .init(id: $0.id, text: $0.text, createdAt: $0.createdAt,
                                                 updatedAt: $0.updatedAt, showsDate: $0.showsDate) })
            },
            photos: photoDTOs)
    }

    /// Пишет файл копии во временную папку и возвращает его URL. Пользователь сам выбирает место сохранения.
    func export(now: Date = Date()) async throws -> URL {
        let manifest = try makeManifest(now: now)
        let store = photos
        let name = "Leaflog-\(Self.fileStamp(now)).\(BackupFormat.fileExtension)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try await Task.detached(priority: .userInitiated) {
            try Self.write(manifest: manifest, store: store, to: url)
        }.value
        return url
    }

    nonisolated static func write(manifest: BackupManifest, store: PhotoStore, to url: URL) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let json = try enc.encode(manifest)
        let fm = FileManager.default
        try? fm.removeItem(at: url)
        guard fm.createFile(atPath: url.path, contents: nil) else { throw BackupError.corrupted("create") }
        let h = try FileHandle(forWritingTo: url)
        defer { try? h.close() }
        var hasher = SHA256()
        func put(_ d: Data) throws { hasher.update(data: d); try h.write(contentsOf: d) }
        try put(BackupFormat.magic)
        var len = UInt64(json.count).bigEndian
        try put(Data(bytes: &len, count: 8))
        try put(json)
        for p in manifest.photos { try put(try store.readFull(p.id)) }
        try h.write(contentsOf: Data(hasher.finalize()))
    }

    // MARK: Проверка (ничего не меняет в текущих данных)

    func inspect(url: URL) async throws -> BackupPreview {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        // Копия во временный файл, чтобы чтение не зависело от внешнего доступа.
        let local = FileManager.default.temporaryDirectory.appendingPathComponent("import-\(UUID().uuidString).bin")
        try FileManager.default.copyItem(at: url, to: local)
        defer { try? FileManager.default.removeItem(at: local) }
        return try await Task.detached(priority: .userInitiated) { try Self.parse(file: local) }.value
    }

    nonisolated static func parse(file: URL) throws -> BackupPreview {
        let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
        let total = (attrs[.size] as? NSNumber)?.intValue ?? 0
        guard total > BackupFormat.magic.count + 8 + 32 else { throw BackupError.notABackup }
        let h = try FileHandle(forReadingFrom: file)
        defer { try? h.close() }

        // 1. Контрольная сумма всего файла.
        var hasher = SHA256()
        var remaining = total - 32
        try h.seek(toOffset: 0)
        while remaining > 0 {
            let chunk = try h.read(upToCount: min(1 << 20, remaining)) ?? Data()
            if chunk.isEmpty { throw BackupError.corrupted("обрыв файла") }
            hasher.update(data: chunk)
            remaining -= chunk.count
        }
        let trailer = try h.read(upToCount: 32) ?? Data()
        guard trailer == Data(hasher.finalize()) else { throw BackupError.corrupted("не совпала контрольная сумма") }

        // 2. Заголовок и манифест.
        try h.seek(toOffset: 0)
        guard try h.read(upToCount: BackupFormat.magic.count) == BackupFormat.magic else { throw BackupError.notABackup }
        let lenData = try h.read(upToCount: 8) ?? Data()
        guard lenData.count == 8 else { throw BackupError.corrupted("заголовок") }
        let jsonLen = Int(lenData.withUnsafeBytes { UInt64(bigEndian: $0.loadUnaligned(as: UInt64.self)) })
        guard jsonLen > 0, jsonLen <= total - BackupFormat.magic.count - 8 - 32 else { throw BackupError.corrupted("длина манифеста") }
        let json = try h.read(upToCount: jsonLen) ?? Data()
        let manifest: BackupManifest
        do { manifest = try JSONDecoder().decode(BackupManifest.self, from: json) }
        catch { throw BackupError.corrupted("манифест: \(error.localizedDescription)") }
        guard manifest.formatVersion >= 1 else { throw BackupError.notABackup }
        guard manifest.formatVersion <= BackupFormat.currentVersion else { throw BackupError.unsupportedVersion(manifest.formatVersion) }
        try validate(manifest)

        // 3. Фото во временную папку с проверкой размера, хэша и читаемости.
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("leaflog-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            var consumed = BackupFormat.magic.count + 8 + jsonLen
            for p in manifest.photos {
                guard p.size >= 0, consumed + p.size <= total - 32 else { throw BackupError.corrupted("размер фото") }
                let data = try h.read(upToCount: p.size) ?? Data()
                guard data.count == p.size, hex(SHA256.hash(data: data)) == p.sha256 else {
                    throw BackupError.corrupted("фото \(p.id.uuidString.prefix(8))")
                }
                guard ImageProcessing.isDecodable(data) else { throw BackupError.corrupted("изображение не читается") }
                try data.write(to: staging.appendingPathComponent("\(p.id.uuidString).jpg"))
                consumed += p.size
            }
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
        return BackupPreview(manifest: manifest, stagingDir: staging)
    }

    nonisolated static func validate(_ m: BackupManifest) throws {
        func unique<T: Hashable>(_ ids: [T], _ what: String) throws {
            if Set(ids).count != ids.count { throw BackupError.invalidReferences("повторяющиеся идентификаторы: \(what)") }
        }
        try unique(m.careTypes.map(\.id), "виды ухода")
        try unique(m.plants.map(\.id), "растения")
        try unique(m.photos.map(\.id), "фото")
        try unique(m.plants.flatMap { $0.events.map(\.id) }, "записи ухода")
        try unique(m.plants.flatMap { $0.rules.map(\.id) }, "правила")
        try unique(m.plants.flatMap { $0.notes.map(\.id) }, "заметки")
        let typeIDs = Set(m.careTypes.map(\.id))
        let plantIDs = Set(m.plants.map(\.id))
        let photoIDs = Set(m.photos.map(\.id))
        for p in m.plants {
            if p.rules.contains(where: { !typeIDs.contains($0.careTypeID) }) || p.events.contains(where: { !typeIDs.contains($0.careTypeID) }) {
                throw BackupError.invalidReferences("неизвестный вид ухода у «\(p.name)»")
            }
            if p.rules.contains(where: { $0.intervalValue < 1 || IntervalUnit(rawValue: $0.intervalUnit) == nil || AnchorKind(rawValue: $0.anchorKind) == nil }) {
                throw BackupError.invalidReferences("неверное правило у «\(p.name)»")
            }
            if let c = p.coverPhotoID, !photoIDs.contains(c) { throw BackupError.invalidReferences("обложка «\(p.name)»") }
        }
        if m.photos.contains(where: { !plantIDs.contains($0.plantID) }) { throw BackupError.invalidReferences("фото без растения") }
    }

    func discard(_ preview: BackupPreview) { try? FileManager.default.removeItem(at: preview.stagingDir) }

    // MARK: Применение

    /// Заменяет текущие данные. При любой ошибке база откатывается, а новые файлы удаляются.
    func apply(_ preview: BackupPreview) async throws {
        let m = preview.manifest
        let store = photos
        let staging = preview.stagingDir
        let before = store.allStoredIDs()
        let incoming = Set(m.photos.map(\.id))
        let toAdd = incoming.subtracting(before)

        // Файлы и миниатюры — вне главного потока; существующие файлы с теми же id не трогаем.
        do {
            try await Task.detached(priority: .userInitiated) {
                for id in toAdd {
                    let data = try Data(contentsOf: staging.appendingPathComponent("\(id.uuidString).jpg"))
                    try store.writeFull(data, id: id)
                }
            }.value
        } catch {
            toAdd.forEach(store.delete)
            throw BackupError.corrupted(error.localizedDescription)
        }

        // Удаление старых и вставка новых данных — одно сохранение: при ошибке откат вернёт прежнюю коллекцию.
        do {
            for p in try context.fetch(FetchDescriptor<Plant>()) { context.delete(p) }
            for t in try context.fetch(FetchDescriptor<CareType>()) { context.delete(t) }
            try insert(m)
            try context.save()
        } catch {
            context.rollback()
            toAdd.forEach(store.delete)
            throw LeaflogError.saveFailed(error.localizedDescription)
        }
        before.subtracting(incoming).forEach(store.delete)
        settings.apply(m.settings)
        try? FileManager.default.removeItem(at: staging)
        notifier?.requestSync()
    }

    private func insert(_ m: BackupManifest) throws {
        for t in m.careTypes {
            let o = CareType(id: t.id, builtinKey: t.builtinKey, name: t.name, colorHex: t.colorHex,
                             iconName: t.iconName, isEnabled: t.isEnabled, sortOrder: t.sortOrder)
            o.notificationsEnabled = t.notificationsEnabled
            context.insert(o)
        }
        var plantByID: [UUID: Plant] = [:]
        for p in m.plants {
            let o = Plant(id: p.id, name: p.name, species: p.species, createdAt: p.createdAt)
            o.isArchived = p.isArchived; o.archivedAt = p.archivedAt; o.coverPhotoID = p.coverPhotoID
            o.referenceProfileID = p.referenceProfileID; o.ownTips = p.ownTips; o.notificationsEnabled = p.notificationsEnabled
            context.insert(o)
            plantByID[p.id] = o
            for r in p.rules {
                let rule = CareRule(id: r.id, plant: o, careTypeID: r.careTypeID,
                                    recurrence: Recurrence(value: r.intervalValue, unit: IntervalUnit(rawValue: r.intervalUnit) ?? .day),
                                    anchorDate: r.anchorDate, anchorKind: AnchorKind(rawValue: r.anchorKind) ?? .firstDue, createdAt: r.createdAt)
                rule.notificationsEnabled = r.notificationsEnabled
                rule.snoozedUntil = r.snoozedUntil
                context.insert(rule)
            }
            for e in p.events {
                let ev = CareEvent(id: e.id, plant: o, careTypeID: e.careTypeID, date: e.date, comment: e.comment,
                                   createdAt: e.createdAt, sourceKey: e.sourceKey)
                ev.updatedAt = e.updatedAt
                context.insert(ev)
            }
            for n in p.notes {
                let note = PlantNote(id: n.id, plant: o, text: n.text, showsDate: n.showsDate, createdAt: n.createdAt)
                note.updatedAt = n.updatedAt
                context.insert(note)
            }
        }
        for ph in m.photos {
            context.insert(PlantPhoto(id: ph.id, plant: plantByID[ph.plantID], addedAt: ph.addedAt, takenAt: ph.takenAt, caption: ph.caption))
        }
    }

    // MARK: Утилиты

    nonisolated static func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }
    static func fileStamp(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyyMMdd-HHmm"
        return f.string(from: d)
    }
}
