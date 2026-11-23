// @copyright André Trettin

import CoreRPG
import Foundation
import Testing

@testable import AdventureRPG

/// CODE_AUDIT_28 §8.1: the game sheet's model was resolved (and written) inside `body`.
@MainActor
struct GameSheetRootModelTests {
    @Test func resolvingStoresTheModelAndReusesIt() async throws {
        let root = try await MockRoot.importTestData()
        let first = UUID()
        let second = UUID()
        #expect(root.editController.editorModel.gameSheetRootModel == nil)

        let created = try #require(root.resolveGameSheetRootModel(for: first))
        #expect(root.editController.editorModel.gameSheetRootModel === created)
        #expect(created.sheetModel.source.itemId == first)

        let reused = try #require(root.resolveGameSheetRootModel(for: second))
        #expect(reused === created)
        #expect(reused.sheetModel.source.itemId == second)
    }

    @Test func readingTheSlotDoesNotCreateIt() async throws {
        let root = try await MockRoot.importTestData()

        // What `body` reads: no side effect.
        _ = root.editController.editorModel.gameSheetRootModel

        #expect(root.editController.editorModel.gameSheetRootModel == nil)
    }
}
