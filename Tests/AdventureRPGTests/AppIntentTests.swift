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

    @Test
    @MainActor
    func entityQueryLimitsPickerResultsWithoutLimitingFullIndex() async throws {
        let root = try await MockRoot.importTestData(itemCounter: 3)
        await root.itemController.resetData()

        for index in 0..<30 {
            let model = AdventureModel(
                id: UUID(),
                name: "Campaign \(index)",
                description: "Shared query target"
            )
            root.itemController.replace(model: model, isInsert: true)
        }
        AppDependencyManager.shared.add(dependency: root)

        let query = AdventureEntityQuery()
        let suggested = try await query.suggestedEntities()
        let matching = try await query.entities(matching: "Campaign")
        let all = try await query.allEntities()

        #expect(suggested.count == 20)
        #expect(matching.count == 25)
        #expect(all.count == 30)
    }
}

#endif
