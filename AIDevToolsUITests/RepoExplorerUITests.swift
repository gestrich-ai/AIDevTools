import XCTest

final class RepoExplorerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testRepoExplorerTabRespondsToDiskChangesAndQuickOpen() throws {
        let app = launchApp()
        selectFirstRepository(in: app)
        tapTab(in: app, label: "Repo Explorer")

        let root = app.otherElements["repoExplorerRoot"]
        XCTAssertTrue(root.waitForExistence(timeout: 15), "Repo Explorer tab should load")

        let repoPathText = app.staticTexts["repoExplorerPath"]
        XCTAssertTrue(repoPathText.waitForExistence(timeout: 10), "Repo path should be visible")

        let repoPath = try XCTUnwrap(repoPathText.label.isEmpty ? repoPathText.value as? String : repoPathText.label)
        let repoURL = URL(fileURLWithPath: repoPath, isDirectory: true)
        let fixture = makeFixture(in: repoURL)
        defer {
            try? FileManager.default.removeItem(at: fixture.renamedFolderURL)
            try? FileManager.default.removeItem(at: fixture.folderURL)
        }

        try FileManager.default.createDirectory(at: fixture.folderURL, withIntermediateDirectories: false)
        try fixture.fileContents.write(to: fixture.fileURL, atomically: true, encoding: .utf8)

        XCTAssertTrue(
            app.staticTexts[fixture.folderName].waitForExistence(timeout: 15),
            "Folder created on disk should appear in the tree"
        )

        app.staticTexts[fixture.folderName].tap()

        XCTAssertTrue(
            app.staticTexts[fixture.fileName].waitForExistence(timeout: 10),
            "Expanding the folder should reveal its child file"
        )

        openQuickOpen(in: app)

        let quickOpenSheet = app.otherElements["repoExplorerQuickOpenSheet"]
        XCTAssertTrue(quickOpenSheet.waitForExistence(timeout: 10), "Quick Open should open")

        let searchField = app.textFields["repoExplorerQuickOpenSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10), "Quick Open search field should appear")
        searchField.click()
        searchField.typeText(fixture.fileName)

        XCTAssertTrue(
            app.staticTexts[fixture.fileName].waitForExistence(timeout: 10),
            "Quick Open should return the created file"
        )

        let resultButton = app.buttons[fixture.fileName].firstMatch
        if resultButton.waitForExistence(timeout: 2) {
            resultButton.tap()
        } else {
            app.staticTexts[fixture.fileName].firstMatch.tap()
        }

        XCTAssertFalse(quickOpenSheet.waitForExistence(timeout: 1), "Quick Open should dismiss after selection")
        XCTAssertTrue(
            app.staticTexts[fixture.fileName].waitForExistence(timeout: 10),
            "Selecting a Quick Open result should keep the file visible"
        )

        try FileManager.default.moveItem(at: fixture.folderURL, to: fixture.renamedFolderURL)

        XCTAssertTrue(
            app.staticTexts[fixture.renamedFolderName].waitForExistence(timeout: 15),
            "Renaming a folder on disk should update the tree"
        )

        try FileManager.default.removeItem(at: fixture.renamedFolderURL)

        XCTAssertTrue(
            waitForNonexistence(of: app.staticTexts[fixture.renamedFolderName], timeout: 15),
            "Deleting a folder on disk should remove it from the tree"
        )
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 15), "Main window should appear")
        sleep(3)

        return app
    }

    @MainActor
    private func selectFirstRepository(in app: XCUIApplication) {
        let sidebar = app.outlines.firstMatch
        XCTAssertTrue(sidebar.waitForExistence(timeout: 10), "Repository sidebar should appear")

        let firstCell = sidebar.cells.firstMatch
        XCTAssertTrue(firstCell.waitForExistence(timeout: 5), "At least one repository should exist")
        firstCell.tap()
        sleep(2)
    }

    @MainActor
    private func tapTab(in app: XCUIApplication, label: String) {
        let button = app.buttons[label]
        if button.waitForExistence(timeout: 2) {
            button.tap()
            sleep(2)
            return
        }

        let radio = app.radioButtons[label]
        if radio.waitForExistence(timeout: 2) {
            radio.tap()
            sleep(2)
            return
        }

        XCTFail("Tab '\(label)' should exist")
    }

    @MainActor
    private func openQuickOpen(in app: XCUIApplication) {
        let button = app.buttons["repoExplorerQuickOpenButton"]
        if button.waitForExistence(timeout: 5) {
            button.tap()
            return
        }

        app.typeKey("o", modifierFlags: [.command, .shift])
    }

    private func makeFixture(in repoURL: URL) -> RepoExplorerFixture {
        let token = UUID().uuidString.lowercased()
        let folderName = "repo-explorer-ui-\(token)"
        let renamedFolderName = "\(folderName)-renamed"
        let fileName = "repo-explorer-\(token).txt"
        let fileContents = "Repo Explorer UI test fixture \(token)\n"
        let folderURL = repoURL.appendingPathComponent(folderName, isDirectory: true)
        let renamedFolderURL = repoURL.appendingPathComponent(renamedFolderName, isDirectory: true)
        let fileURL = folderURL.appendingPathComponent(fileName, isDirectory: false)

        return RepoExplorerFixture(
            fileContents: fileContents,
            fileName: fileName,
            fileURL: fileURL,
            folderName: folderName,
            folderURL: folderURL,
            renamedFolderName: renamedFolderName,
            renamedFolderURL: renamedFolderURL
        )
    }

    private func waitForNonexistence(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}

private struct RepoExplorerFixture {
    let fileContents: String
    let fileName: String
    let fileURL: URL
    let folderName: String
    let folderURL: URL
    let renamedFolderName: String
    let renamedFolderURL: URL
}
