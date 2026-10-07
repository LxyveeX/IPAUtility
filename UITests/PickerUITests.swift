import XCTest

final class PickerUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestSeed", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }

    func testNativeCopyPickerOpenButtonReturnsToLibrary() {
        app.buttons["importIPA"].tap()
        let file = app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@", "Picker Sample")).firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 30), "The native picker should show the seeded file")
        file.tap()
        let open = app.buttons["Open"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        XCTAssertTrue(open.isEnabled)
        open.tap()
        XCTAssertTrue(app.staticTexts["ipaCount"].waitForExistence(timeout: 30),
                      "Tapping the real Open button must return to the app")
        let sample = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Picker Sample")).firstMatch
        XCTAssertTrue(sample.waitForExistence(timeout: 15))
        attach("Native copy selection completed")
    }

    func testNativeFolderPickerOpenButtonReturnsToLibrary() {
        app.buttons["chooseFolder"].tap()
        let open = app.buttons["Open"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 30))
        XCTAssertTrue(open.isEnabled)
        open.tap()
        XCTAssertTrue(app.staticTexts["ipaCount"].waitForExistence(timeout: 30),
                      "Folder selection must complete through the real system UI")
        attach("Native folder selection completed")
    }

    func testLocalLibraryDoesNotRequireDocumentPicker() {
        app.buttons["localLibrary"].tap()
        XCTAssertTrue(app.staticTexts["ipaCount"].waitForExistence(timeout: 15))
        let sample = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Picker Sample.ipa")).firstMatch
        XCTAssertTrue(sample.waitForExistence(timeout: 15))
        attach("Local IPA library")
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
