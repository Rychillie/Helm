//
//  HelmUITests.swift
//  HelmUITests
//
//  Created by Rychillie Umpierre de Oliveira on 02/04/26.
//

import XCTest

final class HelmUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testConfigureConnectSendAndDisconnectFlow() throws {
        let app = XCUIApplication()
        app.launchEnvironment["HELM_USE_MOCK_CLIENT"] = "1"
        app.launch()

        XCTAssertTrue(app.buttons["root.configure"].waitForExistence(timeout: 2))
        app.buttons["root.configure"].tap()

        XCTAssertTrue(app.buttons["settings.save"].waitForExistence(timeout: 2))
        app.buttons["settings.save"].tap()

        XCTAssertTrue(app.buttons["connection.disconnect"].waitForExistence(timeout: 4))

        let composer = app.descendants(matching: .any)["chat.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 2))
        composer.tap()
        composer.typeText("Ping the gateway")

        app.buttons["chat.send"].tap()

        let replyText = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "Helm is connected to the mock gateway"))
            .firstMatch
        XCTAssertTrue(replyText.waitForExistence(timeout: 8))

        app.buttons["connection.disconnect"].tap()
        XCTAssertTrue(app.buttons["connection.primary"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Ping the gateway"].exists)
    }

    @MainActor
    func testFailedSendShowsRetryInContext() throws {
        let app = XCUIApplication()
        app.launchEnvironment["HELM_USE_MOCK_CLIENT"] = "1"
        app.launchEnvironment["HELM_MOCK_FAIL_SEND"] = "1"
        app.launch()

        XCTAssertTrue(app.buttons["root.configure"].waitForExistence(timeout: 2))
        app.buttons["root.configure"].tap()
        app.buttons["settings.save"].tap()

        XCTAssertTrue(app.buttons["connection.disconnect"].waitForExistence(timeout: 4))

        let composer = app.descendants(matching: .any)["chat.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 2))
        composer.tap()
        composer.typeText("This will fail")
        app.buttons["chat.send"].tap()

        XCTAssertTrue(app.buttons["message.retry"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
