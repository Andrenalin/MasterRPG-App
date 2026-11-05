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
    /// The Characters the game master put at the table for this adventure, from the library.
    @MainActor func tablePlayers(for adventureId: UUID) -> [TablePlayerModel]
    /// Saves the table players to the library, also while a game runs.
    @MainActor func saveTablePlayers(_ tablePlayers: [TablePlayerModel], for adventureId: UUID)
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
        // The same roots `AdventureRootModel.startGame()` puts into game mode, Rule included:
        // skipping Rule left it in game mode after every game, so its edits went to game memory
        // only and were lost at relaunch. See CODE_AUDIT §9.5, CODE_AUDIT_Folder §5.3.
        for sibling in root.siblingModuleRoots {
            await sibling.gameControllable.reset()
        }
    }

    @MainActor
    func saveGame() -> ItemModuleIds {
        // save only the map state, later we could save more states
        root.mapRoot.mapGameControllable.saveAll()
    }

    @MainActor
    func tablePlayers(for adventureId: UUID) -> [TablePlayerModel] {
        itemController.itemSync(for: adventureId, noGame: true)?.tablePlayers ?? []
    }

    /// Writes only the table players to the library and mirrors them into a loaded game copy:
    /// a full save during the game would copy the library over the game copy's session changes.
    @MainActor
    func saveTablePlayers(_ tablePlayers: [TablePlayerModel], for adventureId: UUID) {
        guard let library = itemController.itemSync(for: adventureId, noGame: true),
              library.tablePlayers != tablePlayers else { return }
        let updated = library.copy()
        updated.tablePlayers = tablePlayers
        let (added, removed) = updated.changedLinkRegisterModels(oldValue: library)
        itemController.linkRegisterController.deregister(links: removed)
        itemController.linkRegisterController.register(links: added)
        itemController.replace(model: updated, isInsert: false, forceSave: true, syncGameMemory: false)
        if let gameItem = itemController.itemDataModel.gameItemData[adventureId] as? AdventureModel,
           gameItem.tablePlayers != tablePlayers {
            gameItem.tablePlayers_ = updated.tablePlayers_
        }
    }
}
