// @copyright André Trettin

import CoreRPG
import Foundation
import Observation
import TableRPG
import SwiftUI
import MapRPG
import AudioRPG
import DiceRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import CharacterRPG
import WeatherRPG

public protocol AdventureStoreGameable: Sendable {
    @MainActor func startGame(with id: UUID) async
    @MainActor func focusDice(for itemId: UUID) -> UUID?
    @MainActor func resetGame() async
    @MainActor func saveGame() -> ItemModuleIds
}

struct GameController: Sendable {
    @MainActor
    init(root: AdventureRootModel, itemController: ItemController, exportController: ExportController) {
        self.root = root
        self.itemController = itemController
        self.exportController = exportController
        self.gameModel = ItemGameModel(itemDataModel: itemController.itemDataModel)
    }
    
    let root: AdventureRootModel
    let itemController: ItemController
    let exportController: ExportController
    
    let gameModel: ItemGameModel
}

// gameItem(for:)/setGame(item:itemId:)/currentItem() come from
// ModuleGameControllable's default implementations. See CODE_AUDIT_Game §9.1.
extension GameController: ModuleGameControllable {}

extension GameController: GameControllable {
    var itemControllable: any ItemControllable {
        itemController as (any ItemControllable)
    }
    var exportControllable: any ExportControllable {
        exportController as ExportControllable
    }

    /// Clears the live game view's persistent sheet slot when the game ends,
    /// so a later, unrelated presentation never reuses a stale instance.
    /// See `AdventureSheet.gameSheetRootModel` for construction.
    @MainActor func resetGameState() {
        root.editController.editorModel.gameSheetRootModel = nil
    }
}

extension GameController: AdventureStoreGameable {
    @MainActor
    func startGame(with id: UUID) async {
        await focus(on: id)
        root.mapRoot.mapGameControllable.startGameAsMaster()
    }
    
    @MainActor public func focusDice(for itemId: UUID) -> UUID? {
        if let diceId = itemController.itemOrEmpty(for: itemId).diceId {
            let newDiceId = root.diceRoot.diceGameControllable.createGameDice(for: diceId, gameDiceId: nil)
            return newDiceId
        }
        return nil
    }

    @MainActor
    func resetGame() async {
        await reset()
        // See CODE_AUDIT §9.5 — loops over the shared sibling list instead of
        // hand-listing each of the 9 modules.
        for sibling in root.siblingModuleRootsExcludingRule {
            await sibling.gameControllable.reset()
        }
    }

    @MainActor
    func saveGame() -> ItemModuleIds {
        // save only the map state, later we could save more states
        root.mapRoot.mapGameControllable.saveAll()
    }
}
