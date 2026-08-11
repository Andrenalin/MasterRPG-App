// @copyright André Trettin

#if canImport(Testing) && !os(tvOS)

import AppIntents
import CoreRPG
import Foundation
import Testing

@testable import AdventureRPG

struct AdventureAppIntentTests {
    @Test
    @MainActor
    func shortcutCatalogKeepsPublishedBudget() {
        #expect(AdventureShortcutCatalog.all.count == 6)
    }

    // Disabled: `AdventureEntityQuery.suggestedEntities()`/`entities(matching:)`/`allEntities()`
    // read `@Dependency var root: AdventureRootModel`. Personally confirmed this is not a stale
    // API mismatch (every symbol below still exists with a compatible signature — checked before
    // restoring), but a genuine runtime crash: registering the dependency via
    // `AppDependencyManager.shared.add(dependency:)` and then calling the query directly, outside
    // the real intent-perform flow, traps with "Dependency values can only be accessed inside of
    // the intent perform flow ... unless the value of the dependency is manually set prior to
    // access." Because it's a Fatal error (not a thrown error), it kills the whole shared xctest
    // process rather than just failing this one test — the entire suite (`ItemControllerTests`,
    // `SheetControllerTests`, `ExportControllerTests`, and more) reported spurious failures the
    // one time this ran, because their results were lost when the process crashed mid-run. Per
    // the `app-intent` skill's own testing guidance, entity-query coverage like this belongs in
    // the out-of-process `AppIntentsTesting` framework (iOS 27+, a separate XCUITest bundle that
    // exercises the real App Intents stack), not a direct struct test — that's the fix, not
    // restoring this as written. See CODE_AUDIT §9.12.
//    @Test
//    @MainActor
//    func entityQueryLimitsPickerResultsWithoutLimitingFullIndex() async throws {
//        let root = try await MockRoot.importTestData(itemCounter: 3)
//        await root.itemController.resetData()
//
//        for index in 0..<30 {
//            let model = AdventureModel(
//                id: UUID(),
//                name: "Campaign \(index)",
//                description: "Shared query target"
//            )
//            root.itemController.replace(model: model, isInsert: true)
//        }
//        AppDependencyManager.shared.add(dependency: root)
//
//        let query = AdventureEntityQuery()
//        let suggested = try await query.suggestedEntities()
//        let matching = try await query.entities(matching: "Campaign")
//        let all = try await query.allEntities()
//
//        #expect(suggested.count == 20)
//        #expect(matching.count == 25)
//        #expect(all.count == 30)
//    }
}

#endif
