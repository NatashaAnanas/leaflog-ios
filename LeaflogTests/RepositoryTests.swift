import XCTest
import SwiftData
@testable import Leaflog

@MainActor
final class RepositoryTests: XCTestCase {

    private func tasks(_ e: Env) -> [CareTask] {
        TaskBuilder.tasks(plants: e.repo.allPlants(), types: e.types, provider: e.provider)
    }

    /// Каждое действие делаем «в другую секунду», чтобы не срабатывала защита от двойного нажатия.
    private func log(_ e: Env, _ p: Plant, _ typeKey: String, _ date: Date) throws {
        e.clock.date = e.clock.date.addingTimeInterval(5)
        try e.repo.logCare(plant: p, typeID: e.type(typeKey).id, date: date)
    }

    func testOverdueTaskIsOneItemWithGrowingOverdueDays() throws {
        let e = try Env(now: day(2026, 10, 15, 10))
        let p = try e.plant()
        let water = e.type("water")
        try e.repo.setRule(plant: p, typeID: water.id, recurrence: Recurrence(value: 7, unit: .day),
                           anchorDate: day(2026, 10, 10), anchorKind: .firstDue)
        XCTAssertEqual(tasks(e).count, 1)
        XCTAssertEqual(tasks(e)[0].status, .overdue(days: 5))
        let originalDue = tasks(e)[0].dueDay
        // Прошло ещё 3 дня: та же задача, тот же исходный срок, просрочка выросла, копий нет.
        e.clock.date = day(2026, 10, 18, 10)
        XCTAssertEqual(tasks(e).count, 1)
        XCTAssertEqual(tasks(e)[0].dueDay, originalDue)
        XCTAssertEqual(tasks(e)[0].status, .overdue(days: 8))
        XCTAssertEqual(p.events.count, 0, "просрочка не создаёт фиктивных событий")
    }

    func testCompletionAfterOverdueRebasesOnActualDate() throws {
        let e = try Env(now: day(2026, 10, 13, 9))
        let p = try e.plant()
        let water = e.type("water")
        try e.repo.setRule(plant: p, typeID: water.id, recurrence: Recurrence(value: 7, unit: .day),
                           anchorDate: day(2026, 10, 10), anchorKind: .firstDue)
        try log(e, p, "water", e.clock.date)
        XCTAssertEqual(tasks(e)[0].dueDay, day(2026, 10, 20, 0))
    }

    func testBackdatedEntryDoesNotMoveScheduleBack() throws {
        let e = try Env(now: day(2026, 10, 14, 9))
        let p = try e.plant()
        try e.repo.setRule(plant: p, typeID: e.type("water").id, recurrence: Recurrence(value: 7, unit: .day),
                           anchorDate: nil, anchorKind: .firstDue)
        try log(e, p, "water", day(2026, 10, 13, 9))
        XCTAssertEqual(tasks(e)[0].dueDay, day(2026, 10, 20, 0))
        try log(e, p, "water", day(2026, 10, 5, 9))
        XCTAssertEqual(tasks(e)[0].dueDay, day(2026, 10, 20, 0))
    }

    func testEditingAndDeletingLastEventRecalculates() throws {
        let e = try Env(now: day(2026, 10, 14, 9))
        let p = try e.plant()
        let water = e.type("water")
        try e.repo.setRule(plant: p, typeID: water.id, recurrence: Recurrence(value: 7, unit: .day),
                           anchorDate: day(2026, 10, 1), anchorKind: .lastCare)
        XCTAssertEqual(tasks(e)[0].dueDay, day(2026, 10, 8, 0), "без истории: от даты последнего ухода")
        try log(e, p, "water", day(2026, 10, 5, 9))
        try log(e, p, "water", day(2026, 10, 13, 9))
        XCTAssertEqual(tasks(e)[0].dueDay, day(2026, 10, 20, 0))
        let last = p.events.max { $0.date < $1.date }!
        try e.repo.updateEvent(last, date: day(2026, 10, 10, 9), comment: "исправлено")
        XCTAssertEqual(tasks(e)[0].dueDay, day(2026, 10, 17, 0))
        try e.repo.deleteEvent(last)
        XCTAssertEqual(tasks(e)[0].dueDay, day(2026, 10, 12, 0), "по оставшейся истории (5 октября + 7)")
        try e.repo.deleteEvent(p.events[0])
        XCTAssertEqual(tasks(e)[0].dueDay, day(2026, 10, 8, 0), "история пуста — снова от исходной настройки")
    }

    func testSameCareTypeHasDifferentIntervalsPerPlant() throws {
        let e = try Env()
        let a = try e.plant("А"), b = try e.plant("Б")
        let water = e.type("water")
        try e.repo.setRule(plant: a, typeID: water.id, recurrence: Recurrence(value: 3, unit: .day), anchorDate: day(2026, 10, 15), anchorKind: .lastCare)
        try e.repo.setRule(plant: b, typeID: water.id, recurrence: Recurrence(value: 2, unit: .week), anchorDate: day(2026, 10, 15), anchorKind: .lastCare)
        let t = tasks(e)
        XCTAssertEqual(t.first { $0.plant.name == "А" }?.dueDay, day(2026, 10, 18, 0))
        XCTAssertEqual(t.first { $0.plant.name == "Б" }?.dueDay, day(2026, 10, 29, 0))
    }

    func testMonthlyFertilizerEndOfMonth() throws {
        let e = try Env(now: day(2026, 1, 31, 12))
        let p = try e.plant()
        try e.repo.setRule(plant: p, typeID: e.type("fertilize").id, recurrence: Recurrence(value: 1, unit: .month), anchorDate: nil, anchorKind: .firstDue)
        try log(e, p, "fertilize", day(2026, 1, 31, 12))
        XCTAssertEqual(tasks(e)[0].dueDay, day(2026, 2, 28, 0))
    }

    func testSnoozeDoesNotChangeDueOrHistory() throws {
        let e = try Env(now: day(2026, 10, 15, 10))
        let p = try e.plant()
        let rule = try e.repo.setRule(plant: p, typeID: e.type("water").id, recurrence: Recurrence(value: 7, unit: .day),
                                      anchorDate: day(2026, 10, 10), anchorKind: .firstDue)
        let due = tasks(e)[0].dueDay
        try e.repo.snooze(rule, until: day(2026, 10, 16))
        XCTAssertEqual(tasks(e)[0].dueDay, due)
        XCTAssertEqual(tasks(e)[0].status, .overdue(days: 5))
        XCTAssertEqual(p.events.count, 0)
    }

    func testRemovingRuleKeepsHistory() throws {
        let e = try Env()
        let p = try e.plant()
        let rule = try e.repo.setRule(plant: p, typeID: e.type("water").id, recurrence: Recurrence(value: 7, unit: .day), anchorDate: day(2026, 10, 10), anchorKind: .firstDue)
        try log(e, p, "water", day(2026, 10, 14))
        try e.repo.removeRule(rule)
        XCTAssertTrue(tasks(e).isEmpty)
        XCTAssertEqual(p.events.count, 1)
    }

    func testDisabledCareTypeKeepsHistoryAndHidesTasks() throws {
        let e = try Env()
        let p = try e.plant()
        let custom = try e.repo.addCareType(name: "Обрезка", colorHex: "D6456B", icon: "scissors")
        try e.repo.setRule(plant: p, typeID: custom.id, recurrence: Recurrence(value: 1, unit: .month), anchorDate: day(2026, 10, 15), anchorKind: .firstDue)
        try e.repo.logCare(plant: p, typeID: custom.id)
        try e.repo.setCareType(custom, enabled: false)
        XCTAssertTrue(tasks(e).isEmpty)
        XCTAssertEqual(p.events.count, 1)
        XCTAssertEqual(e.types.first { $0.id == custom.id }?.name, "Обрезка", "тип не удалён — история отображается")
    }

    func testDoubleTapGuardAndSameDayEntries() throws {
        let e = try Env()
        let p = try e.plant()
        let water = e.type("water")
        let r1 = try e.repo.logCare(plant: p, typeID: water.id)
        let r2 = try e.repo.logCare(plant: p, typeID: water.id)
        XCTAssertFalse(r1.wasDuplicate)
        XCTAssertTrue(r2.wasDuplicate)
        XCTAssertEqual(p.events.count, 1)
        // Позже в тот же день — осознанная вторая запись, обе остаются и различимы по времени.
        e.clock.date = e.clock.date.addingTimeInterval(3 * 3600)
        let r3 = try e.repo.logCare(plant: p, typeID: water.id)
        XCTAssertFalse(r3.wasDuplicate)
        XCTAssertEqual(p.events.count, 2)
        XCTAssertNotEqual(p.events[0].date, p.events[1].date)
    }

    func testFutureDateIsClampedToNow() throws {
        let e = try Env()
        let p = try e.plant()
        let r = try e.repo.logCare(plant: p, typeID: e.type("water").id, date: day(2027, 1, 1))
        XCTAssertEqual(r.event.date, e.clock.date)
    }

    func testPlantNameValidationAndArchive() throws {
        let e = try Env()
        XCTAssertThrowsError(try e.repo.addPlant(name: "   "))
        let p = try e.plant()
        try e.repo.setArchived(p, true)
        XCTAssertTrue(p.isArchived)
        XCTAssertTrue(tasks(e).isEmpty)
        try e.repo.setArchived(p, false)
        XCTAssertFalse(p.isArchived)
        XCTAssertNil(p.archivedAt)
    }

    func testPlantsWithSameNameAreIndependentCards() throws {
        let e = try Env()
        let a = try e.plant("Фикус"), b = try e.plant("Фикус")
        XCTAssertNotEqual(a.id, b.id)
        try e.repo.logCare(plant: a, typeID: e.type("water").id)
        XCTAssertEqual(a.events.count, 1)
        XCTAssertEqual(b.events.count, 0)
    }

    func testNotesCrudKeepsCreatedAtAndUpdatesUpdatedAt() throws {
        let e = try Env()
        let p = try e.plant()
        let n = try e.repo.addNote(to: p, text: "Стоит у окна", showsDate: false)
        XCTAssertFalse(n.showsDate)
        let created = n.createdAt
        e.clock.date = e.clock.date.addingTimeInterval(3600)
        try e.repo.updateNote(n, text: "Стоит у южного окна", showsDate: true)
        XCTAssertEqual(n.createdAt, created)
        XCTAssertGreaterThan(n.updatedAt, created)
        XCTAssertThrowsError(try e.repo.updateNote(n, text: " ", showsDate: true))
        try e.repo.deleteNote(n)
        XCTAssertTrue(p.notes.isEmpty)
    }

    // MARK: Фото и файлы

    private func jpeg(_ size: CGSize = CGSize(width: 3000, height: 2000)) -> Data {
        UIGraphicsImageRenderer(size: size).jpegData(withCompressionQuality: 0.9) { ctx in
            UIColor.green.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    func testPhotoProcessingProducesSmallThumbAndLimitsSize() throws {
        let processed = try ImageProcessing.process(jpeg())
        let full = UIImage(data: processed.full)!
        let thumb = UIImage(data: processed.thumb)!
        XCTAssertLessThanOrEqual(max(full.size.width, full.size.height) * full.scale, 2048)
        XCTAssertLessThanOrEqual(max(thumb.size.width, thumb.size.height) * thumb.scale, 480)
        XCTAssertLessThan(processed.thumb.count, processed.full.count)
        XCTAssertNil(processed.takenAt)
        XCTAssertThrowsError(try ImageProcessing.process(Data([1, 2, 3])))
    }

    func testPhotoDatesAreIndependentAndCoverLifecycle() throws {
        let e = try Env()
        let p = try e.plant()
        let img = try ImageProcessing.process(jpeg(CGSize(width: 800, height: 600)))
        let old = day(2025, 5, 1)
        let a = try e.repo.addPhoto(to: p, image: img, takenAt: old)
        XCTAssertEqual(a.takenAt, old)
        XCTAssertEqual(a.addedAt, e.clock.date)
        XCTAssertEqual(p.coverPhotoID, a.id, "первое фото становится обложкой")
        let added = a.addedAt
        try e.repo.updatePhoto(a, takenAt: day(2025, 6, 1), caption: "  Новый лист ")
        XCTAssertEqual(a.addedAt, added, "дата добавления неизменяема")
        XCTAssertEqual(a.caption, "Новый лист")
        e.clock.date = e.clock.date.addingTimeInterval(10)
        let b = try e.repo.addPhoto(to: p, image: img)
        XCTAssertEqual(b.takenAt, e.clock.date, "без метаданных — текущая дата")
        try e.repo.setCover(b)
        XCTAssertEqual(p.coverPhotoID, b.id)
        XCTAssertTrue(e.photos.exists(a.id) && e.photos.exists(b.id))
        try e.repo.deletePhoto(b)
        XCTAssertEqual(p.coverPhotoID, a.id, "обложка переходит к оставшемуся фото")
        XCTAssertFalse(e.photos.exists(b.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: e.photos.thumbURL(b.id).path))
    }

    func testDeletingPlantRemovesItsFilesAndChildren() throws {
        let e = try Env()
        let p = try e.repo.addPlant(name: "С фото", photo: try ImageProcessing.process(jpeg(CGSize(width: 600, height: 600))))
        let photoID = p.photos[0].id
        try e.repo.logCare(plant: p, typeID: e.type("water").id)
        _ = try e.repo.addNote(to: p, text: "заметка", showsDate: true)
        XCTAssertTrue(e.photos.exists(photoID))
        try e.repo.deletePlant(p)
        XCTAssertFalse(e.photos.exists(photoID))
        XCTAssertEqual(try e.context.fetch(FetchDescriptor<CareEvent>()).count, 0)
        XCTAssertEqual(try e.context.fetch(FetchDescriptor<PlantNote>()).count, 0)
        XCTAssertEqual(try e.context.fetch(FetchDescriptor<PlantPhoto>()).count, 0)
    }

    func testOrphanCleanupOnlyRemovesUnreferencedFiles() throws {
        let e = try Env()
        let p = try e.repo.addPlant(name: "P", photo: try ImageProcessing.process(jpeg(CGSize(width: 600, height: 600))))
        let keep = p.photos[0].id
        let orphan = UUID()
        try e.photos.write(try ImageProcessing.process(jpeg(CGSize(width: 300, height: 300))), id: orphan)
        XCTAssertEqual(e.photos.removeOrphans(keeping: [keep]), 1)
        XCTAssertTrue(e.photos.exists(keep))
        XCTAssertFalse(e.photos.exists(orphan))
    }

    // MARK: Хранение после перезапуска

    func testDataSurvivesContainerRecreation() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("leaflog-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("test.store")
        var plantID: UUID!
        do {
            let e = try Env(container: PersistenceFactory.makeContainer(url: url))
            let p = try e.plant("Переживёт перезапуск")
            plantID = p.id
            try e.repo.setRule(plant: p, typeID: e.type("water").id, recurrence: Recurrence(value: 5, unit: .day), anchorDate: day(2026, 10, 15), anchorKind: .firstDue)
            try e.repo.logCare(plant: p, typeID: e.type("water").id, comment: "тест")
            _ = try e.repo.addNote(to: p, text: "память", showsDate: false)
        }
        // «Перезапуск»: новый контейнер на том же файле.
        let e2 = try Env(container: PersistenceFactory.makeContainer(url: url))
        let plants = e2.repo.allPlants()
        XCTAssertEqual(plants.count, 1)
        XCTAssertEqual(plants[0].id, plantID)
        XCTAssertEqual(plants[0].events.first?.comment, "тест")
        XCTAssertEqual(plants[0].rules.first?.intervalValue, 5)
        XCTAssertEqual(plants[0].notes.first?.showsDate, false)
        XCTAssertEqual(e2.types.filter { $0.builtinKey != nil }.count, 5, "встроенные виды не дублируются")
    }

    func testBuiltInCareTypesSeededOnceWithDistinctColorsAndIcons() throws {
        let e = try Env()
        try e.repo.ensureBuiltInCareTypes()
        XCTAssertEqual(e.types.count, 5)
        XCTAssertEqual(Set(e.types.map(\.colorHex)).count, 5)
        XCTAssertEqual(Set(e.types.map(\.iconName)).count, 5)
        XCTAssertEqual(e.type("water").colorHex, "8E6CEF", "полив — фиолетовый")
    }
}
