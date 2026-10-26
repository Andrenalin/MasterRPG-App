// @copyright André Trettin

#if !os(tvOS)

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

    // Entity-query coverage (`suggestedEntities()`, `entities(matching:)`, `allEntities()`) is
    // not tested here: the query reads `@Dependency var root`, and reading a dependency outside
    // the intent perform flow is a fatal error that takes the whole test process with it. It
    // belongs in an out-of-process `AppIntentsTesting` bundle. The commented-out test that
    // stood here was removed. See CODE_AUDIT §9.12, CODE_AUDIT_21 §9.15.
}

#endif
