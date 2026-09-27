// @copyright André Trettin

import CharacterRPG
import CoreRPG
import Foundation
import MapRPG

@MainActor
struct BattleCharacterSheetFactory {
    let characterRoot: CharacterRootModel

    func presentation(for combatant: BattleCombatant) -> BattleCharacterSheetPresentation? {
        guard let baseRootManager = characterRoot.rootManager else { return nil }

        let itemId: UUID
        let sheetRootManager: RootManager
        if let gameCharacterId = combatant.gameCharacterId,
           let clone = characterRoot.valueGameControllable.battleCharacterCopy(for: gameCharacterId) {
            let items: [UUID: any ItemDataAccessible] = [clone.id: clone]
            itemId = clone.id
            sheetRootManager = baseRootManager.with(
                reviewSheetMemory: ReviewSheetMemory(items: [.value: items])
            )
        } else if let sourceCharacterId = combatant.sourceCharacterId,
                  characterRoot.itemControllable.itemSync(for: sourceCharacterId, noGame: true) != nil {
            itemId = sourceCharacterId
            sheetRootManager = baseRootManager
        } else {
            return nil
        }

        let controller = characterRoot.rootController
        let sheet = SheetRootModel(
            rootManager: sheetRootManager,
            linkControllable: controller.linkControllable,
            sheetControllable: controller.sheetControllable,
            itemId: itemId,
            isEditor: false
        )
        return BattleCharacterSheetPresentation(
            id: combatant.id,
            name: combatant.name,
            root: controller,
            sheet: sheet
        )
    }
}
