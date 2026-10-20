import XCTest
import SwiftData
@testable import Leaflog

@MainActor
final class BackupTests: XCTestCase {

    private func jpeg() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 900, height: 600)).jpegData(withCompressionQuality: 0.9) { ctx in
            UIColor.orange.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 900, height: 600))
        }
    }

    private func populate(_ e: Env) throws -> Plant {
        let p = try e.repo.addPlant(name: "Демо", species: "Demo species", photo: try ImageProcessing.process(jpeg()), photoTakenAt: day(2025, 3, 3))
        p.ownTips = "Свои советы"
        p.referenceProfileID = "monstera"
        try e.repo.setRule(plant: p, typeID: e.type("water").id, recurrence: Recurrence(value: 2, unit: .week), anchorDate: day(2026, 10, 1), anchorKind: .lastCare)
        try e.repo.logCare(plant: p, typeID: e.type("water").id, date: day(2026, 10, 10), comment: "комментарий")
        _ = try e.repo.addNote(to: p, text: "Заметка", showsDate: false)
        try e.repo.commit()
        e.settings.userName = "Тест"
        e.settings.hemisphere = .south
        return p
    }

    private func backupService(_ e: Env) -> BackupService {
        BackupService(context: e.context, photos: e.photos, settings: e.settings, notifier: nil)
    }

    func testExportImportRoundTripKeepsRecordsPhotosAndSettings() async throws {
        let src = try Env()
        let p = try populate(src)
        let url = try await backupService(src).export()
        defer { try? FileManager.default.removeItem(at: url) }

        let dst = try Env()
        let preview = try await backupService(dst).inspect(url: url)
        XCTAssertEqual(preview.plantCount, 1); XCTAssertEqual(preview.photoCount, 1)
        XCTAssertEqual(preview.eventCount, 1); XCTAssertEqual(preview.noteCount, 1)
        XCTAssertEqual(preview.manifest.formatVersion, BackupFormat.currentVersion)
        try await backupService(dst).apply(preview)

        let plants = dst.repo.allPlants()
        XCTAssertEqual(plants.count, 1)
        let q = plants[0]
        XCTAssertEqual(q.id, p.id); XCTAssertEqual(q.name, "Демо"); XCTAssertEqual(q.species, "Demo species")
        XCTAssertEqual(q.ownTips, "Свои советы"); XCTAssertEqual(q.referenceProfileID, "monstera")
        XCTAssertEqual(q.events.first?.comment, "комментарий")
        XCTAssertEqual(q.events.first?.date, p.events.first?.date)
        XCTAssertEqual(q.rules.first?.intervalValue, 2)
        XCTAssertEqual(q.rules.first?.anchorKind, .lastCare)
        XCTAssertEqual(q.notes.first?.showsDate, false)
        XCTAssertEqual(q.photos.first?.takenAt, day(2025, 3, 3))
        XCTAssertEqual(q.photos.first?.addedAt, p.photos.first?.addedAt)
        XCTAssertEqual(q.coverPhotoID, p.coverPhotoID)
        XCTAssertTrue(dst.photos.exists(q.photos[0].id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dst.photos.thumbURL(q.photos[0].id).path))
        XCTAssertEqual(dst.settings.userName, "Тест"); XCTAssertEqual(dst.settings.hemisphere, .south)
        XCTAssertEqual(dst.types.count, 5)
        // Связи записей и файлов целы: нет записей без файлов и файлов без записей.
        XCTAssertEqual(dst.photos.allStoredIDs(), Set(q.photos.map(\.id)))
    }

    func testImportReplacesExistingCollectionInPlace() async throws {
        let e = try Env()
        _ = try populate(e)
        let url = try await backupService(e).export()
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try e.plant("Лишнее растение после копии")
        XCTAssertEqual(e.repo.allPlants().count, 2)
        let preview = try await backupService(e).inspect(url: url)
        try await backupService(e).apply(preview)
        XCTAssertEqual(e.repo.allPlants().count, 1)
        XCTAssertEqual(e.repo.allPlants()[0].name, "Демо")
        XCTAssertEqual(e.photos.allStoredIDs().count, 1)
    }

    func testCorruptedAndForeignFilesAreRejectedWithoutTouchingData() async throws {
        let e = try Env()
        _ = try populate(e)
        let url = try await backupService(e).export()
        defer { try? FileManager.default.removeItem(at: url) }

        // 1. Не резервная копия.
        let junk = FileManager.default.temporaryDirectory.appendingPathComponent("junk-\(UUID()).leaflogbackup")
        try Data(repeating: 7, count: 500).write(to: junk)
        do { _ = try await backupService(e).inspect(url: junk); XCTFail("должна быть ошибка") } catch {}

        // 2. Повреждённый байт внутри.
        var bytes = try Data(contentsOf: url)
        bytes[bytes.count / 2] ^= 0xFF
        let broken = FileManager.default.temporaryDirectory.appendingPathComponent("broken-\(UUID()).leaflogbackup")
        try bytes.write(to: broken)
        do { _ = try await backupService(e).inspect(url: broken); XCTFail("должна быть ошибка") }
        catch let err as BackupError { if case .corrupted = err {} else { XCTFail("\(err)") } }

        // 3. Обрезанный файл.
        let cut = FileManager.default.temporaryDirectory.appendingPathComponent("cut-\(UUID()).leaflogbackup")
        try (try Data(contentsOf: url)).prefix(120).write(to: cut)
        do { _ = try await backupService(e).inspect(url: cut); XCTFail("должна быть ошибка") } catch {}

        XCTAssertEqual(e.repo.allPlants().count, 1, "текущая коллекция не тронута")
        XCTAssertEqual(e.photos.allStoredIDs().count, 1)
    }

    func testValidationRejectsBrokenReferences() throws {
        var m = BackupManifest(formatVersion: 1, appVersion: "1", exportedAt: Date(), settings: AppSettings(defaults: UserDefaults(suiteName: "x-\(UUID())")!).snapshot,
                               careTypes: [], plants: [], photos: [])
        let plantID = UUID()
        m.plants = [.init(id: plantID, name: "P", species: "", createdAt: Date(), isArchived: false, archivedAt: nil, coverPhotoID: nil,
                          referenceProfileID: nil, ownTips: "", notificationsEnabled: true, rules: [],
                          events: [.init(id: UUID(), careTypeID: UUID(), date: Date(), comment: "", createdAt: Date(), updatedAt: Date(), sourceKey: nil)], notes: [])]
        XCTAssertThrowsError(try BackupService.validate(m), "событие ссылается на неизвестный вид ухода")
        m.plants[0].events = []
        m.photos = [.init(id: UUID(), plantID: UUID(), addedAt: Date(), takenAt: Date(), caption: "", size: 0, sha256: "")]
        XCTAssertThrowsError(try BackupService.validate(m), "фото без растения")
        m.photos = []
        XCTAssertNoThrow(try BackupService.validate(m))
    }

    func testUnsupportedFutureVersionIsRejected() async throws {
        let e = try Env()
        var manifest = try backupService(e).makeManifest()
        manifest.formatVersion = 99
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("future-\(UUID()).leaflogbackup")
        try BackupService.write(manifest: manifest, store: e.photos, to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        do { _ = try await backupService(e).inspect(url: url); XCTFail() }
        catch let err as BackupError { if case .unsupportedVersion(99) = err {} else { XCTFail("\(err)") } }
    }

    func testImportRecalculatesNotifications() async throws {
        let e = try Env()
        e.settings.notificationsEnabled = true
        _ = try populate(e)
        e.settings.notificationsEnabled = true
        let url = try await backupService(e).export()
        defer { try? FileManager.default.removeItem(at: url) }
        let preview = try await backupService(e).inspect(url: url)
        try await backupService(e).apply(preview)
        // Настройки применены, а сверка после импорта строит план из восстановленных правил.
        e.settings.notificationsEnabled = true
        await e.service.sync()
        XCTAssertFalse(e.center.pending.isEmpty)
    }
}
