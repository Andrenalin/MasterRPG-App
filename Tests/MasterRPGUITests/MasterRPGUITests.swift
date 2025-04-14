// @copyright André Trettin

import XCTest

final class MasterRPGUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
    }

    @MainActor
    func testAutomatedAccessibility() {
        let myApp = XCUIApplication()
        myApp.launch()

        do {
            try myApp.performAccessibilityAudit()
        } catch {
            XCTFail("The automated accessibility audit fail because [\(error.localizedDescription)]")
        }
    }

    @MainActor
    func disabled_testScrollPerformance() throws {
        let app = XCUIApplication()
        app.launch()
            
        #if os(macOS)
        app.tabs["Editors"].click()
        #else
        app.tabBars.buttons["Editors"].click()
        app.scrollViews.otherElements/*@START_MENU_TOKEN@*/.images["photo.on.rectangle.angled"]/*[[".buttons[\"Foto\"].images[\"photo.on.rectangle.angled\"]",".images[\"photo.on.rectangle.angled\"]"],[[[-1,1],[-1,0]]],[0]]@END_MENU_TOKEN@*/.click()
        #endif
        

        let scrollView = app.scrollViews.firstMatch
        scrollView.swipeUp(velocity: .fast)
        scrollView.swipeUp(velocity: .fast)
        scrollView.swipeUp(velocity: .fast)
        scrollView.swipeUp(velocity: .fast)
        scrollView.swipeUp(velocity: .fast)
        scrollView.swipeUp(velocity: .fast)

        scrollView.swipeDown(velocity: .fast)
        scrollView.swipeDown(velocity: .fast)
        scrollView.swipeDown(velocity: .fast)
        scrollView.swipeDown(velocity: .fast)
        scrollView.swipeDown(velocity: .fast)
        scrollView.swipeDown(velocity: .fast)

        let options = XCTMeasureOptions()
        options.iterationCount = 5
        options.invocationOptions = [.manuallyStart, .manuallyStop]

        measure(metrics: [
            XCTOSSignpostMetric.scrollingAndDecelerationMetric
        ], options: options) {
            startMeasuring()
            scrollView.swipeUp(velocity: .fast)
            scrollView.swipeUp(velocity: .fast)

            scrollView.swipeDown(velocity: .fast)
            scrollView.swipeDown(velocity: .fast)
            stopMeasuring()
        }
    }

}
