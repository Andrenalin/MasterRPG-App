// @copyright André Trettin

import CoreRPG
import Foundation
import Testing

@testable import CharacterRPG
@testable import GameRPG
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
        let factory = BattleCharacterSheetFactory(characterRoot: root.characterRoot)

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
        let factory = BattleCharacterSheetFactory(characterRoot: root.characterRoot)

        let presentation = try #require(
            factory.presentation(for: combatant)
        )

        #expect(presentation.sheet.sheetModel.source.itemId == runtimeId)
    }

    @Test("Nil and stale Character ids cannot create an empty inline sheet")
    func rejectsMissingAndStaleCharacters() async throws {
        let root = try await emptyRoot()
        let factory = BattleCharacterSheetFactory(characterRoot: root.characterRoot)
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

    @Test("The inline sheet and the Character selection keep the combatant's identity")
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
            BattleCharacterSheetFactory(characterRoot: root.characterRoot).presentation(for: combatant)
        )
        let selectionPresentation = BattleRoundSelectionPresentation(id: combatant.id)

        #expect(sheet.id == combatant.id)
        #expect(selectionPresentation.id == combatant.id)
    }

    @Test("A combatant asks for Ini/HP configuration only once a Character is assigned and a value is missing")
    func valueConfigurationNeeds() {
        let pin = MapPinModel(id: UUID(), name: "Goblin")
        let characterId = UUID()

        let noCharacter = BattleCombatant(pin: pin, sourceCharacterId: nil, gameCharacterId: nil)
        #expect(!(noCharacter.needsInitiativeConfiguration || noCharacter.needsHitPointsConfiguration))

        let nothingFound = BattleCombatant(pin: pin, sourceCharacterId: characterId, gameCharacterId: characterId)
        #expect(nothingFound.needsInitiativeConfiguration)
        #expect(nothingFound.needsHitPointsConfiguration)

        // The entry was found, but its value is not a usable number.
        let iniWithoutValue = BattleCombatant(
            pin: pin,
            sourceCharacterId: characterId,
            gameCharacterId: characterId,
            initiativeEntryId: UUID(),
            hitPointsEntryId: UUID()
        )
        #expect(iniWithoutValue.needsInitiativeConfiguration)
        #expect(!iniWithoutValue.needsHitPointsConfiguration)

        // Typed by the game master: the entry is still missing, so the row stays.
        let typedInitiative = BattleCombatant(
            pin: pin,
            sourceCharacterId: characterId,
            gameCharacterId: characterId,
            initiative: 12,
            hitPointsEntryId: UUID()
        )
        #expect(typedInitiative.needsInitiativeConfiguration)

        let resolved = BattleCombatant(
            pin: pin,
            sourceCharacterId: characterId,
            gameCharacterId: characterId,
            initiative: 12,
            initiativeEntryId: UUID(),
            hitPointsEntryId: UUID()
        )
        #expect(!(resolved.needsInitiativeConfiguration || resolved.needsHitPointsConfiguration))
    }

    @Test("A config row follows the missing value until the game master hides or reopens it")
    func valueRowVisibility() {
        let pin = MapPinModel(id: UUID(), name: "Goblin")
        let characterId = UUID()
        let missing = BattleCombatant(pin: pin, sourceCharacterId: characterId, gameCharacterId: characterId)
        let resolved = BattleCombatant(
            pin: pin,
            sourceCharacterId: characterId,
            gameCharacterId: characterId,
            initiative: 12,
            initiativeEntryId: UUID(),
            hitPointsEntryId: UUID()
        )
        let noCharacter = BattleCombatant(pin: pin, sourceCharacterId: nil, gameCharacterId: nil)

        let state = BattleRoundCardState()
        #expect(state.showsValueRow(.initiative, for: missing))
        #expect(state.showsValueRow(.hitPoints, for: missing))
        #expect(!state.showsValueRow(.initiative, for: resolved))
        #expect(!state.showsValueRow(.initiative, for: noCharacter))

        // The row pins itself open when it appears, so it survives its value getting set.
        state.setValueRow(.initiative, isShown: true)
        #expect(state.showsValueRow(.initiative, for: resolved))
        #expect(!state.showsValueRow(.hitPoints, for: resolved))

        // Checkmark: hidden, even while the entry itself is still missing.
        state.setValueRow(.initiative, isShown: false)
        #expect(!state.showsValueRow(.initiative, for: resolved))
        #expect(!state.showsValueRow(.initiative, for: missing))

        // Reopened from the participant column.
        state.setValueRow(.hitPoints, isShown: true)
        #expect(state.showsValueRow(.hitPoints, for: resolved))

        // Never without a Character, whatever was chosen before.
        #expect(!state.showsValueRow(.hitPoints, for: noCharacter))
    }

    private func emptyRoot() async throws -> GameRoot {
        try await MockRoot.createGameRoot()
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
