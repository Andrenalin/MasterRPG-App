// @copyright André Trettin

import CoreRPG
import Foundation
import os.log

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

public protocol PhotoGameControllable: GameControllable {
    @MainActor func resetPhotoSpace()
}

struct GameController: Sendable {
    @MainActor
    init(itemController: ItemController, fileUrlDataController: FileUrlDataController) {
        self.itemController = itemController
        self.exportController = ExportController(module: itemController.module, itemController: itemController, fileUrlDataController: fileUrlDataController, gameExporter: false)
        let internItemController = ItemController(container: itemController.container, module: itemController.module)
        self.importController = ImportController(itemController: internItemController, fileUrlDataController: fileUrlDataController, module: itemController.module)
        self.gameModel = ItemGameModel()
        self.photoGameModel = PhotoGameModel()
    }

    let itemController: ItemController
    let importController: ImportController
    let exportController: ExportController
    
    let gameModel: ItemGameModel
    let photoGameModel: PhotoGameModel
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
