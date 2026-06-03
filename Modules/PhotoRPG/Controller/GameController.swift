// @copyright André Trettin

import CoreRPG
import Foundation

@MainActor @Observable
final class PhotoGameModel: Sendable {
    init() {}

    var openPhotoSpace: Bool = false
#if os(visionOS)
    var currentSelection: PhotoWorldSelection?
#endif
    
    func reset() {
        openPhotoSpace = false
#if os(visionOS)
        currentSelection = nil
#endif
    }
}

public protocol PhotoGameControllable {
    @MainActor func resetPhotoSpace()
}

struct GameController: Sendable {
    @MainActor init(rootManager: RootManager, itemController: ItemController, exportController: ExportController) {
        self.itemController = itemController
        self.exportController = exportController
        
        self.gameModel = ItemGameModel(itemDataModel: itemController.itemDataModel)
        self.photoGameModel = PhotoGameModel()
    }

    let itemController: ItemController
    let exportController: ExportController

    let gameModel: ItemGameModel
    let photoGameModel: PhotoGameModel

    @MainActor func gameItem(for itemId: UUID) -> PhotoModel {
        (gameModel.itemData[itemId] as? PhotoModel) ?? itemController.itemOrEmpty(for: itemId)
    }
    
    @MainActor func setGame(item: ItemGameModel.ModelType, itemId: UUID) {
        if gameModel.items.firstIndex(where: { $0 == itemId }) != nil {
            gameModel.itemData[itemId] = item
        } else {
            gameModel.items.insert(itemId, at: 0)
            gameModel.itemData[itemId] = item
        }
    }
    
    @MainActor func currentItem() -> PhotoModel {
        gameItem(for: gameModel.currentItemId ?? UUID())
    }
}

extension GameController: GameControllable {
    var itemControllable: any ItemControllable { itemController as (any ItemControllable) }
    var exportControllable: any ExportControllable { exportController as ExportControllable }

    @MainActor func resetGameState() {
        photoGameModel.reset()
    }
}

extension GameController {
    func updateGame(data: NetworkCodableDataType, subtype: RPGMessageActionType) async throws {
        guard subtype == .photoSpace else { return }
#if os(visionOS)
        Task { @MainActor in
            photoGameModel.currentSelection = PhotoWorldSelection(id: data.id, rotationDegrees: 67)
            photoGameModel.openPhotoSpace <=> true
        }
#endif
    }
}

extension GameController: PhotoGameControllable {
    @MainActor func resetPhotoSpace() {
        photoGameModel.openPhotoSpace <=> false
    }
}
