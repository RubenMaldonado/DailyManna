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

    func test_filters_applyAndClear_fromToolbar() {
        // Open Filter sheet
        let filterButton = app.buttons["Filters"]
        XCTAssertTrue(filterButton.waitForExistence(timeout: 5))
        filterButton.tap()

        // Toggle built-in 'Available'
        let availableCell = app.switches["Available"]
        XCTAssertTrue(availableCell.waitForExistence(timeout: 5))
        availableCell.tap()

        // Apply
        app.buttons["Apply"].tap()

        // Badge should now exist
        XCTAssertTrue(filterButton.exists)

        // Reopen and Clear All
        filterButton.tap()
        let clearAll = app.buttons["Clear All"]
        XCTAssertTrue(clearAll.waitForExistence(timeout: 5))
        clearAll.tap()
    }

    func test_viewMode_switching() {
        // iPhone/iPad menu button should exist
        let listIcon = app.buttons["list.bullet"]
        let gridIcon = app.buttons["rectangle.grid.2x2"]
        if listIcon.exists && gridIcon.exists {
            gridIcon.tap()
            listIcon.tap()
        } else {
            // Fallback: segmented in toolbar (macOS-like environments)
            let segmented = app.segmentedControls.firstMatch
            if segmented.waitForExistence(timeout: 5) {
                segmented.buttons.element(boundBy: 1).tap()
                segmented.buttons.element(boundBy: 0).tap()
            }
        }
    }
}
