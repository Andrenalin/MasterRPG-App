// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import CharacterRPG
@testable import MapRPG

@MainActor
@Suite("Battle round inline character details", .serialized)
struct BattleRoundInlineCharacterTests {
//    @Test("A stored source Character resolves when the runtime id is absent or stale")
//    func resolvesStoredSourceCharacter() async throws {
//        let root = try await emptyRoot()
//        let sourceId = UUID()
//        root.characterRoot.itemController.replace(
//            model: ValueModel(id: sourceId, name: "Goblin Scout"),
//            isInsert: true
//        )
//        let combatant = makeCombatant(
//            name: "Scout token",
//            sourceCharacterId: sourceId,
//            gameCharacterId: UUID()
//        )
//        let entryId = UUID()
//        let resolver = BattleRoundCharacterDetailResolver(root: root)
//
//        let presentation = try #require(
//            resolver.presentation(entryId: entryId, for: combatant)
//        )
//
//        #expect(resolver.canPresent(combatant))
//        #expect(presentation.entryId == entryId)
//        #expect(presentation.combatantId == combatant.id)
//        #expect(presentation.characterId == sourceId)
//        #expect(presentation.sheetRootModel.sheetModel.source.itemId == sourceId)
//    }
//
//    @Test("A runtime battle copy takes precedence over its stored Character template")
//    func resolvesRuntimeCharacterCopyFirst() async throws {
//        let root = try await emptyRoot()
//        let sourceId = UUID()
//        root.characterRoot.itemController.replace(
//            model: ValueModel(id: sourceId, name: "Goblin Template"),
//            isInsert: true
//        )
//        let runtimeId = try #require(
//            root.characterRoot.valueGameControllable.createBattleCharacterCopy(
//                for: sourceId
//            )
//        )
//        let combatant = makeCombatant(
//            name: "Goblin instance",
//            sourceCharacterId: sourceId,
//            gameCharacterId: runtimeId
//        )
//        let resolver = BattleRoundCharacterDetailResolver(root: root)
//
//        let presentation = try #require(
//            resolver.presentation(entryId: UUID(), for: combatant)
//        )
//
//        #expect(presentation.characterId == runtimeId)
//        #expect(presentation.sheetRootModel.sheetModel.source.itemId == runtimeId)
//    }
//
//    @Test("Nil and stale Character ids cannot create an empty inline sheet")
//    func rejectsMissingAndStaleCharacters() async throws {
//        let root = try await emptyRoot()
//        let resolver = BattleRoundCharacterDetailResolver(root: root)
//        let missing = makeCombatant(
//            name: "Unassigned token",
//            sourceCharacterId: nil,
//            gameCharacterId: nil
//        )
//        let stale = makeCombatant(
//            name: "Deleted Character",
//            sourceCharacterId: UUID(),
//            gameCharacterId: UUID()
//        )
//
//        #expect(!resolver.canPresent(missing))
//        #expect(resolver.presentation(entryId: UUID(), for: missing) == nil)
//        #expect(!resolver.canPresent(stale))
//        #expect(resolver.presentation(entryId: UUID(), for: stale) == nil)
//    }
//
//    @Test("Inline detail toggles by battle entry and combatant and clears stale selection")
//    func inlineSelectionLifecycle() async throws {
//        let root = try await emptyRoot()
//        let firstCharacterId = UUID()
//        let secondCharacterId = UUID()
//        root.characterRoot.itemController.replace(
//            model: ValueModel(id: firstCharacterId, name: "First"),
//            isInsert: true
//        )
//        root.characterRoot.itemController.replace(
//            model: ValueModel(id: secondCharacterId, name: "Second"),
//            isInsert: true
//        )
//        let firstCombatant = makeCombatant(
//            name: "First token",
//            sourceCharacterId: firstCharacterId,
//            gameCharacterId: nil
//        )
//        let secondCombatant = makeCombatant(
//            name: "Second token",
//            sourceCharacterId: secondCharacterId,
//            gameCharacterId: nil
//        )
//        let resolver = BattleRoundCharacterDetailResolver(root: root)
//        let entryId = UUID()
//        let first = try #require(
//            resolver.presentation(entryId: entryId, for: firstCombatant)
//        )
//        let second = try #require(
//            resolver.presentation(entryId: entryId, for: secondCombatant)
//        )
//        let selection = BattleRoundInlineCharacterSelection()
//        let entry = BattleRoundEntry(
//            id: entryId,
//            attackerId: firstCombatant.id,
//            defenderIds: [secondCombatant.id]
//        )
//
//        selection.toggle(first)
//        #expect(selection.presentation?.combatantId == firstCombatant.id)
//
//        selection.toggle(first)
//        #expect(selection.presentation == nil)
//
//        selection.toggle(first)
//        selection.toggle(second)
//        #expect(selection.presentation?.combatantId == secondCombatant.id)
//
//        selection.retainSelection(
//            in: [firstCombatant, secondCombatant],
//            entries: [entry]
//        )
//        #expect(selection.presentation?.combatantId == secondCombatant.id)
//
//        let entryWithoutDefender = BattleRoundEntry(
//            id: entryId,
//            attackerId: firstCombatant.id
//        )
//        selection.retainSelection(
//            in: [firstCombatant, secondCombatant],
//            entries: [entryWithoutDefender]
//        )
//        #expect(selection.presentation == nil)
//    }

    private func emptyRoot() async throws -> MapRootModel {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        return root
    }

    private func makeCombatant(
        name: String,
        sourceCharacterId: UUID?,
        gameCharacterId: UUID?
    ) -> BattleCombatant {
        BattleCombatant(
            pin: MapPinModel(
                id: UUID(),
                name: name,
                characterId: gameCharacterId ?? sourceCharacterId
            ),
            sourceCharacterId: sourceCharacterId,
            gameCharacterId: gameCharacterId
        )
    }
}
#endif
