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
        if !file.waitForExistence(timeout: 10) {
            // directoryURL is a starting-location hint. If Files chooses Recents,
            // navigate through the real browser instead of assuming the hint won.
            for label in ["Browse", "On My iPad", "IPA 图标", "IPA"] {
                if file.exists { break }
                let button = app.buttons[label].firstMatch
                let text = app.staticTexts[label].firstMatch
                if button.waitForExistence(timeout: 2), button.isHittable { button.tap() }
                else if text.waitForExistence(timeout: 2), text.isHittable { text.tap() }
            }
        }
        XCTAssertTrue(file.waitForExistence(timeout: 30), "The native picker should show the seeded file")
        file.tap()
        let open = app.buttons["Open"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        XCTAssertTrue(open.isEnabled)
        open.tap()
        XCTAssertTrue(app.staticTexts["ipaCount"].waitForExistence(timeout: 30),
                      "Tapping the real Open button must return to the app")
        let sample = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Picker Sample (2).ipa")).firstMatch
        XCTAssertTrue(sample.waitForExistence(timeout: 15), "The selected file must actually be copied into the library")
        attach("Native copy selection completed")
    }

    func testCaptureSystemAppSwitcherIcon() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.999))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 1)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertTrue(springboard.wait(for: .runningForeground, timeout: 10))
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "App switcher — visual icon review required"
        attachment.lifetime = .keepAlways
        add(attachment)
        // Foreground state alone does not prove the icon is correct; review the attachment.
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
