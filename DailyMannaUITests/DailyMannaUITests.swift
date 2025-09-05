//
//  DailyMannaUITests.swift
//  DailyMannaUITests
//
//  Created by Ruben Maldonado Tena on 8/24/25.
//

import XCTest

final class DailyMannaUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func test_filterBar_applyAndClear() {
        // Ensure Filter field exists
        let filterField = app.textFields["Add label…"]
        XCTAssertTrue(filterField.waitForExistence(timeout: 5))

        // Open Options and toggle "Available"
        app.buttons["Options"].tap()
        let availableToggle = app.buttons["Available"]
        if availableToggle.waitForExistence(timeout: 2) { availableToggle.tap() }

        // Clear filters button if visible
        let clear = app.buttons["Clear filters"]
        if clear.waitForExistence(timeout: 2) { clear.tap() }

        // Saved menu interaction
        app.buttons["Saved"].tap()
        let unlabeled = app.buttons["Unlabeled"]
        if unlabeled.waitForExistence(timeout: 2) { unlabeled.tap() }
        if clear.waitForExistence(timeout: 2) { clear.tap() }
    }
}
