// @copyright André Trettin

import CoreRPG
import Foundation
import Testing

@testable import CharacterRPG
@testable import MapRPG

@MainActor
@Suite("Battle round character sheets", .serialized)
struct BattleRoundInlineCharacterTests {
    @Test("A stored source Character resolves when the runtime id is absent or stale")
    func resolvesStoredSourceCharacter() async throws {
        let root = try await emptyRoot()
        let sourceId = UUID()
        root.characterRoot.itemController.replace(
            model: ValueModel(id: sourceId, name: "Goblin Scout"),
            isInsert: true
        )
        let combatant = makeCombatant(
            name: "Scout token",
            sourceCharacterId: sourceId,
            gameCharacterId: UUID()
        )
        let factory = BattleCharacterSheetFactory(root: root)

        let presentation = try #require(
            factory.presentation(for: combatant)
        )

        #expect(presentation.id == combatant.id)
        #expect(presentation.name == combatant.name)
        #expect(presentation.sheet.sheetModel.source.itemId == sourceId)
    }

    @Test("A runtime battle copy takes precedence over its stored Character template")
    func resolvesRuntimeCharacterCopyFirst() async throws {
        let root = try await emptyRoot()
        let sourceId = UUID()
        root.characterRoot.itemController.replace(
            model: ValueModel(id: sourceId, name: "Goblin Template"),
            isInsert: true
        )
        let runtimeId = try #require(
            root.characterRoot.valueGameControllable.createBattleCharacterCopy(
                for: sourceId
            )
        )
        let combatant = makeCombatant(
            name: "Goblin instance",
            sourceCharacterId: sourceId,
            gameCharacterId: runtimeId
        )
        let factory = BattleCharacterSheetFactory(root: root)

        let presentation = try #require(
            factory.presentation(for: combatant)
        )

        #expect(presentation.sheet.sheetModel.source.itemId == runtimeId)
    }

    @Test("Nil and stale Character ids cannot create an empty inline sheet")
    func rejectsMissingAndStaleCharacters() async throws {
        let root = try await emptyRoot()
        let factory = BattleCharacterSheetFactory(root: root)
        let missing = makeCombatant(
            name: "Unassigned token",
            sourceCharacterId: nil,
            gameCharacterId: nil
        )
        let stale = makeCombatant(
            name: "Deleted Character",
            sourceCharacterId: UUID(),
            gameCharacterId: UUID()
        )

        #expect(factory.presentation(for: missing) == nil)
        #expect(factory.presentation(for: stale) == nil)
    }

    @Test("Sheet and character-selection presentations retain combatant identity")
    func presentationIdentity() async throws {
        let root = try await emptyRoot()
        let characterId = UUID()
        root.characterRoot.itemController.replace(
            model: ValueModel(id: characterId, name: "Assigned hero"),
            isInsert: true
        )
        let combatant = makeCombatant(
            name: "Hero token",
            sourceCharacterId: characterId,
            gameCharacterId: nil
        )
        let sheet = try #require(
            BattleCharacterSheetFactory(root: root).presentation(for: combatant)
        )
        let sheetPresentation = BattleRoundPresentation.sheet(sheet)
        let selectionPresentation = BattleRoundPresentation.selection(combatant.id)

        #expect(sheetPresentation.id == combatant.id)
        #expect(selectionPresentation.id == combatant.id)
    }

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
