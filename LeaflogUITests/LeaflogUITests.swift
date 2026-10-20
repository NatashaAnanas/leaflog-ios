import XCTest

/// Сценарные проверки на симуляторе и генерация скриншотов (только демо-данные: `-LEAFLOG_DEMO`).
final class LeaflogUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-LEAFLOG_DEMO", "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
    }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    /// Прокручивает до элемента, чья подпись содержит текст, и открывает его.
    private func open(containing text: String) {
        let el = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        var tries = 0
        while !(el.exists && el.isHittable) && tries < 6 { app.swipeUp(); tries += 1 }
        XCTAssertTrue(el.exists, "нет элемента \(text)")
        el.tap()
    }

    private func tab(_ name: String) { app.tabBars.buttons[name].tap() }

    func testScreenshotsLightAndDark() throws {
        for (scheme, label) in [(XCUIDevice.Appearance.light, "light"), (.dark, "dark")] {
            XCUIDevice.shared.appearance = scheme
            app.launch()
            XCTAssertTrue(app.staticTexts["Привет, Алиса!"].waitForExistence(timeout: 10))
            shot("\(label)-1-plants")
            app.swipeUp(); shot("\(label)-1b-plants-scrolled")
            app.swipeDown()
            open(containing: "Орхидея")
            XCTAssertTrue(app.staticTexts["Быстрые действия"].waitForExistence(timeout: 5))
            shot("\(label)-2-plant-overview")
            app.swipeUp(); shot("\(label)-2b-plant-overview-scrolled")
            app.swipeDown()
            app.buttons["Календарь"].tap(); shot("\(label)-3-plant-calendar")
            app.buttons["Фото"].tap(); shot("\(label)-4-plant-photos")
            app.buttons["Заметки"].tap(); shot("\(label)-5-plant-notes")
            app.scrollViews.buttons["Советы"].firstMatch.tap(); shot("\(label)-6-plant-tips")
            app.navigationBars.buttons.firstMatch.tap()
            app.buttons["Общий календарь"].tap()
            XCTAssertTrue(app.staticTexts["Выполнено"].waitForExistence(timeout: 5))
            shot("\(label)-7-calendar")
            app.navigationBars.buttons.firstMatch.tap()
            tab("Задачи"); shot("\(label)-8-tasks")
            tab("Советы"); shot("\(label)-9-tips")
            tab("Профиль"); shot("\(label)-10-profile")
            app.terminate()
        }
        XCUIDevice.shared.appearance = .light
    }
}
