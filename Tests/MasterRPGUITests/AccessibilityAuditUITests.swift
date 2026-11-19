// @copyright André Trettin

import XCTest

/// CODE_AUDIT_TestGaps §8.6: the system's accessibility audit on the root screen of each module.
/// `performAccessibilityAudit` finds missing labels, tiny hit regions, wrong traits and, at the
/// default text size, clipped text. `Scripts/verify_accessibility.rb` only checks the source.
final class AccessibilityAuditUITests: MasterRPGUITestCase {
    /// What the audit checks. Contrast and Dynamic Type are not audited here: the reviewed
    /// snapshots cover the text sizes, and contrast of the fixture photos is not the app's.
    private let auditedTypes: XCUIAccessibilityAuditType = [
        .sufficientElementDescription, .hitRegion, .trait
    ]

    @MainActor
    private func audit(token: String, title: String) throws {
        let app = launchPreparedApp()
        openModule(token: token, title: title, app: app)
        let list = app.descendants(matching: .any)
            .matching(identifier: "module.list.\(token)")
            .firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 15), "The \(title) module did not display its list.")
        try app.performAccessibilityAudit(for: auditedTypes)
    }

    @MainActor func testAdventureRootAudit() throws { try audit(token: "ADVENTURES", title: "Adventure") }
    @MainActor func testCharacterRootAudit() throws { try audit(token: "VALUES", title: "Character") }
    @MainActor func testMapRootAudit() throws { try audit(token: "MAPS", title: "Map") }
    @MainActor func testWeatherRootAudit() throws { try audit(token: "WEATHERS", title: "Weather") }
    @MainActor func testPdfRootAudit() throws { try audit(token: "PDFS", title: "Pdf") }
    @MainActor func testTableRootAudit() throws { try audit(token: "TABLES", title: "Table") }
    @MainActor func testAudioRootAudit() throws { try audit(token: "AUDIOS", title: "Audio") }
    @MainActor func testDiceRootAudit() throws { try audit(token: "DICE", title: "Dice") }
    @MainActor func testPhotoRootAudit() throws { try audit(token: "PHOTOS", title: "Photo") }
    @MainActor func testSpaceRootAudit() throws { try audit(token: "SPACES", title: "Space") }
}
