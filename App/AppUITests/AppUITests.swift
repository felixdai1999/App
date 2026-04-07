import XCTest

final class AppUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testNewTabPageAppearsOnLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["FAVORITES"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
