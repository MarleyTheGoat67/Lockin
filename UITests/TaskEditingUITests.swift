import XCTest

/// Taps through every way to change or delete a task, on the simulator, with sample data.
final class TaskEditingUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(tab: Int) {
        app = XCUIApplication()
        app.launchArguments = [
            "-demoData", "YES",
            "-resetData", "YES",
            "-demoAllDay", "YES",
            "-startTab", "\(tab)",
        ]
        app.launch()
    }

    // MARK: - Tests

    func testRenameTaskAndMoveDeadline() {
        launch(tab: 2)
        tap(anything(containing: "History essay"))
        tap(button("Edit task"))

        let field = wait(app.textFields["taskNameField"])
        XCTAssertEqual(field.value as? String, "History essay")
        replaceText(in: field, with: "Biology essay")
        tap(button("+1 week"))
        screenshot("edit-1-editor")
        tap(app.buttons["Save"])

        // Detail screen shows the new name and the deadline one week later (was in 5 days at 18:00).
        wait(anything(containing: "Biology essay"))
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: 12, to: Date())!
        let dayText = day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        wait(anything(containing: dayText))
        screenshot("edit-2-detail")

        // Back on the list the old name is gone.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        wait(app.navigationBars["Tasks"])
        wait(anything(containing: "Biology essay"))
        XCTAssertTrue(anything(containing: "History essay").waitForNonExistence(timeout: 5))
        screenshot("edit-3-list")
    }

    func testDeleteFromTaskScreen() {
        launch(tab: 2)
        tap(anything(containing: "Clean my room"))
        tap(button("Delete task"))
        screenshot("delete-1-confirm")
        tapDialogButton("Delete task")

        wait(app.navigationBars["Tasks"])
        XCTAssertTrue(anything(containing: "Clean my room").waitForNonExistence(timeout: 5))
        wait(anything(containing: "History essay"))
        screenshot("delete-2-list")
    }

    func testDeleteFromEditor() {
        launch(tab: 2)
        tap(anything(containing: "Learn vocabulary"))
        tap(button("Edit task"))
        wait(app.textFields["taskNameField"])
        app.swipeUp()
        tap(button("Delete task"))
        tapDialogButton("Delete task")

        wait(app.navigationBars["Tasks"])
        XCTAssertTrue(anything(containing: "Learn vocabulary").waitForNonExistence(timeout: 5))
    }

    func testSwipeToEditAndDelete() {
        launch(tab: 2)
        let row = anything(containing: "Clean my room")
        wait(row).swipeLeft()
        screenshot("swipe-1-actions")
        tap(app.buttons["Edit"])
        let field = wait(app.textFields["taskNameField"])
        XCTAssertEqual(field.value as? String, "Clean my room")
        tap(app.buttons["Cancel"])

        wait(row).swipeLeft()
        tap(app.buttons["Delete"])
        tapDialogButton("Delete task")
        XCTAssertTrue(anything(containing: "Clean my room").waitForNonExistence(timeout: 5))
    }

    func testEditAndDeleteFromCalendar() {
        launch(tab: 1)
        tap(anything(containing: "Maths homework"))
        screenshot("calendar-1-block")
        tap(button("Edit task"))
        let field = wait(app.textFields["taskNameField"])
        replaceText(in: field, with: "Maths test")
        tap(app.buttons["Save"])

        wait(anything(containing: "Maths test"))
        tap(button("Delete task"))
        tapDialogButton("Delete task")

        XCTAssertTrue(anything(containing: "Maths").waitForNonExistence(timeout: 5))
        wait(anything(containing: "History essay"))
        screenshot("calendar-2-after-delete")
    }

    // MARK: - Helpers

    private func anything(containing text: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", text))
            .firstMatch
    }

    private func button(_ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    }

    @discardableResult
    private func wait(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        if !element.waitForExistence(timeout: 10) {
            dumpHierarchy()
            screenshot("FAILED-\(name)")
            XCTFail("Not found: \(element)", file: file, line: line)
        }
        return element
    }

    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        wait(element, file: file, line: line).tap()
    }

    private func replaceText(in field: XCUIElement, with text: String) {
        // Put the cursor at the end, then delete everything.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 40))
        field.typeText(text)
        XCTAssertEqual(field.value as? String, text)
    }

    /// Confirmation dialogs are action sheets on iPhone.
    private func tapDialogButton(_ title: String) {
        let inSheet = app.sheets.buttons[title]
        if inSheet.waitForExistence(timeout: 4) {
            inSheet.tap()
            return
        }
        let inAlert = app.alerts.buttons[title]
        if inAlert.waitForExistence(timeout: 1) {
            inAlert.tap()
            return
        }
        let all = app.buttons.matching(NSPredicate(format: "label == %@", title))
        XCTAssertGreaterThan(all.count, 0, "No dialog button \(title)")
        all.element(boundBy: all.count - 1).tap()
    }

    private func dumpHierarchy() {
        print("=== HIERARCHY START \(name)")
        print(app.debugDescription)
        print("=== HIERARCHY END")
    }

    private func screenshot(_ fileName: String) {
        let image = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: image)
        attachment.name = fileName
        attachment.lifetime = .keepAlways
        add(attachment)
        // Also write it to the Mac running the simulator, so CI can publish it.
        if let home = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] {
            let folder = URL(fileURLWithPath: home).appendingPathComponent("lockin-uitest-shots")
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let safe = fileName.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "-", options: .regularExpression)
            try? image.pngRepresentation.write(to: folder.appendingPathComponent("uitest-\(safe).png"))
        }
    }
}
