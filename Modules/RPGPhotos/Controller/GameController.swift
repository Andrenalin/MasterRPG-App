// @copyright André Trettin

import AndrenalinKit
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
    @MainActor
    init(root: PhotoRoot, itemController: ItemController) {
        self.root = root
        self.itemController = itemController
        self.exportController = ExportController(root: root, gameExporter: false)
        let internItemController = ItemController(root: root, dataController: nil)
        self.importController = ImportController(root: root, itemController: internItemController)
        self.gameModel = ItemGameModel(itemDataModel: internItemController.itemDataModel)
        self.photoGameModel = PhotoGameModel()
    }

    weak var root: PhotoRoot!
    let itemController: ItemController
    let importController: ImportController
    let exportController: ExportController

    let gameModel: ItemGameModel
    let photoGameModel: PhotoGameModel

    @MainActor
    func gameItem(for itemId: UUID) -> PhotoModel {
        (gameModel.itemData[itemId] as? PhotoModel) ?? itemController.itemOrEmpty(for: itemId)
    }
    
    @MainActor
    func setGame(item: ItemGameModel.ModelType, itemId: UUID) {
        if gameModel.items.firstIndex(where: { $0 == itemId }) != nil {
            gameModel.itemData[itemId] = item
        } else {
            gameModel.items.insert(itemId, at: 0)
            gameModel.itemData[itemId] = item
        }
    }
    
    @MainActor
    func currentItem() -> PhotoModel {
        gameItem(for: gameModel.currentItemId ?? UUID())
    }
}

extension GameController: GameControllable {
    var itemControllable: any ItemControllable {
        itemController as (any ItemControllable)
    }
    var exportControllable: any ExportControllable {
        exportController as ExportControllable
    }
    var importControllable: any ImportControllable {
        importController as ImportControllable
    }
    var rootExportControllable: any ExportControllable {
        root.rootControllable.gameExportControllable
    }
    var rootImportControllable: any ImportControllable {
        root.rootControllable.gameImportControllable
    }
    
    func resetGameState() {
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
    @MainActor
    func resetPhotoSpace() {
        photoGameModel.openPhotoSpace <=> false
    }
}
