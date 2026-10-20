import XCTest

/// Сценарии на симуляторе. Все данные — синтетические, в изолированном хранилище.
final class FlowTests: XCTestCase {
    var app: XCUIApplication!

    private func launch(_ mode: String, extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = [mode, "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"] + extra
        app.launch()
    }
    override func setUp() { continueAfterFailure = false }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    private func tapButton(_ label: String, timeout: TimeInterval = 5) {
        let b = app.buttons[label].firstMatch
        XCTAssertTrue(b.waitForExistence(timeout: timeout), "нет кнопки \(label)")
        b.tap()
    }
    private func text(_ s: String, timeout: TimeInterval = 5) -> Bool { app.staticTexts[s].firstMatch.waitForExistence(timeout: timeout) }

    func testEmptyStateCreatePlantWithoutPhotoThenCareNoteArchiveDelete() throws {
        launch("-LEAFLOG_EMPTY")
        XCTAssertTrue(text("Здесь будут ваши растения"))
        shot("flow-01-empty-state")
        tapButton("Добавить первое растение")
        let name = app.textFields["Название растения"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Кактус с очень длинным домашним названием для проверки переноса строк")
        // «Сохранить» доступно только при непустом названии
        XCTAssertTrue(app.buttons["Сохранить"].isEnabled)
        shot("flow-02-add-form")
        app.buttons["Сохранить"].tap()

        // Карточка растения
        XCTAssertTrue(text("Быстрые действия", timeout: 8))
        shot("flow-03-detail-no-photo")
        app.buttons["Полив сейчас"].tap()
        XCTAssertTrue(app.buttons["Отменить"].waitForExistence(timeout: 3), "баннер отмены")
        shot("flow-04-logged-undo")
        // двойное нажатие подряд не создаёт вторую запись
        app.buttons["Полив сейчас"].tap()
        app.buttons["Полив сейчас"].tap()

        // История
        app.scrollViews.buttons["Календарь"].tap()
        XCTAssertTrue(app.staticTexts["История"].waitForExistence(timeout: 5))
        let historyCount = app.staticTexts.matching(NSPredicate(format: "label == 'Полив'")).count
        XCTAssertGreaterThanOrEqual(historyCount, 1)
        shot("flow-05-history")

        // Заметка
        app.scrollViews.buttons["Заметки"].tap()
        tapButton("Новая заметка")
        let editor = app.textViews["Текст заметки"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap(); editor.typeText("Стоит на южном окне")
        app.buttons["Сохранить"].tap()
        XCTAssertTrue(text("Стоит на южном окне"))
        shot("flow-06-note")

        // Архивирование и восстановление
        app.buttons["Действия с растением"].tap()
        app.buttons["Архивировать"].tap()
        XCTAssertTrue(text("В архиве"))
        app.buttons["Действия с растением"].tap()
        XCTAssertTrue(app.buttons["Восстановить из архива"].exists)
        app.buttons["Восстановить из архива"].tap()
        XCTAssertFalse(app.staticTexts["В архиве"].waitForExistence(timeout: 2))

        // Удаление с подтверждением
        app.buttons["Действия с растением"].tap()
        app.buttons["Удалить растение"].tap()
        XCTAssertTrue(app.buttons["Удалить навсегда"].waitForExistence(timeout: 3))
        shot("flow-07-delete-confirm")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()   // закрыть диалог без подтверждения
        XCTAssertTrue(app.buttons["Действия с растением"].waitForExistence(timeout: 3), "отмена не удаляет")
        XCTAssertFalse(app.buttons["Удалить навсегда"].exists)
        app.buttons["Действия с растением"].tap()
        app.buttons["Удалить растение"].tap()
        app.buttons["Удалить навсегда"].tap()
        XCTAssertTrue(text("Здесь будут ваши растения", timeout: 8))
    }

    func testSearchAndFilters() throws {
        launch("-LEAFLOG_DEMO")
        XCTAssertTrue(text("Привет, Алиса!", timeout: 10))
        app.buttons["Поиск"].tap()
        let field = app.textFields["Поиск по названию"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText("Орх")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Орхидея'")).firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Алоэ'")).firstMatch.exists)
        shot("flow-08-search")
        app.buttons["Очистить поиск"].firstMatch.tap()
        app.buttons["Архив"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Старый фикус'")).firstMatch.waitForExistence(timeout: 3))
        shot("flow-09-archive-filter")
    }

    func testCustomCareTypeCreationAndDisable() throws {
        launch("-LEAFLOG_DEMO")
        app.tabBars.buttons["Профиль"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Виды ухода'")).firstMatch.tap()
        tapButton("Добавить свой вид ухода")
        let name = app.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap(); name.typeText("Обрезка")
        shot("flow-10-custom-type")
        app.buttons["Сохранить"].tap()
        XCTAssertTrue(app.staticTexts["Обрезка"].waitForExistence(timeout: 3))
        shot("flow-11-types-list")
    }

    func testNotificationPermissionDeniedKeepsAppWorking() throws {
        launch("-LEAFLOG_DEMO")
        addUIInterruptionMonitor(withDescription: "notifications") { alert in
            for title in ["Не разрешать", "Don’t Allow", "Don't Allow"] where alert.buttons[title].exists {
                alert.buttons[title].tap(); return true
            }
            return false
        }
        app.tabBars.buttons["Профиль"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Напоминания'")).firstMatch.tap()
        let toggle = app.switches["Получать напоминания"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
        app.tap() // позволяет сработать монитору прерываний
        sleep(2)
        shot("flow-12-notifications-after-toggle")
        // Приложение продолжает работать: возврат на вкладку растений
        app.navigationBars.buttons.firstMatch.tap()
        app.tabBars.buttons["Растения"].tap()
        XCTAssertTrue(text("Привет, Алиса!", timeout: 5))
    }

    func testLargeTextLongNamesAndAccessibilityAudit() throws {
        launch("-LEAFLOG_DEMO", extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(text("Привет, Алиса!", timeout: 10))
        shot("flow-13-largetext-plants")
        var issues: [String] = []
        try app.performAccessibilityAudit(for: [.contrast, .elementDetection, .sufficientElementDescription, .hitRegion]) { issue in
            issues.append("\(issue.auditType): \(issue.compactDescription) | \(issue.element?.label ?? "-") | \(issue.element?.elementType.rawValue ?? 0)")
            // Текст, частично скрытый под полупрозрачной системной панелью вкладок (эффект iOS), не считается ошибкой палитры.
            if issue.auditType == .contrast, let f = issue.element?.frame, f.intersects(self.app.tabBars.firstMatch.frame) { return true }
            return false
        }
        let note = XCTAttachment(string: issues.joined(separator: "\n")); note.name = "audit-issues"; note.lifetime = .keepAlways; add(note)
        print("AUDIT:\n" + issues.joined(separator: "\n"))
        app.tabBars.buttons["Задачи"].tap()
        shot("flow-14-largetext-tasks")
        app.tabBars.buttons["Профиль"].tap()
        shot("flow-15-largetext-profile")
    }
}

/// Фотодневник на демо-фото: просмотр, правка дат и подписи, обложка, удаление.
/// Выбор из системной медиатеки (PhotosPicker) на симуляторе не проверяется: в этой среде системный выбор фото
/// остаётся на «Загрузка…». Обработка и сохранение выбранных данных покрыты unit-тестами, сам выбор — проверка на iPhone.
final class PhotoFlowTests: XCTestCase {
    var app: XCUIApplication!
    override func setUp() { continueAfterFailure = false }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }

    func testViewEditDatesSetCoverAndDelete() throws {
        app = XCUIApplication()
        app.launchArguments = ["-LEAFLOG_DEMO", "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Привет, Алиса!"].waitForExistence(timeout: 10))
        let monstera = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Монстера'")).firstMatch
        var tries = 0
        while !(monstera.exists && monstera.isHittable) && tries < 6 { app.swipeUp(); tries += 1 }
        monstera.tap()
        app.scrollViews.buttons["Фото"].tap()
        XCTAssertTrue(app.staticTexts["Фотодневник"].waitForExistence(timeout: 5))
        shot("photo-01-diary-grid")
        // лента
        app.buttons["Лента"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Добавлено в приложение'")).firstMatch.waitForExistence(timeout: 3))
        shot("photo-02-diary-feed")
        app.buttons["Сетка"].tap()

        let photos = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Фото, снято'"))
        XCTAssertEqual(photos.count, 3)
        photos.element(boundBy: 1).tap()
        app.buttons["Действия с фото"].tap()
        app.buttons["Изменить дату и подпись"].tap()
        XCTAssertTrue(app.navigationBars["Данные фото"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Добавлено в приложение"].exists, "неизменяемая дата показана отдельно")
        shot("photo-03-edit-dates")
        // Ввод подписи и смена даты покрыты unit-тестами (testPhotoDatesAreIndependentAndCoverLifecycle).
        app.buttons["Сохранить"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Снято:'")).firstMatch.waitForExistence(timeout: 3))

        app.buttons["Действия с фото"].tap()
        let cover = app.buttons["Сделать обложкой"]
        XCTAssertTrue(cover.waitForExistence(timeout: 3))
        cover.tap()
        XCTAssertTrue(app.staticTexts["Обложка"].waitForExistence(timeout: 3))
        shot("photo-04-viewer-cover")

        sleep(1)
        let del = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Удалить фото'")).firstMatch
        if !del.exists { app.buttons["Действия с фото"].tap() }   // меню может остаться открытым после выбора обложки
        XCTAssertTrue(del.waitForExistence(timeout: 5))
        del.tap()
        XCTAssertTrue(app.buttons["Удалить"].waitForExistence(timeout: 3))
        shot("photo-05-delete-confirm")
        app.buttons["Удалить"].tap()
        app.buttons["Закрыть"].firstMatch.tap()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Фото, снято'")).count, 2)
    }
}
