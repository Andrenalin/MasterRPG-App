// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData
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

public struct GameController: Sendable {
    @MainActor
    init(itemController: ItemController, fileUrlDataController: FileUrlDataController) {
        self.itemController = itemController
        self.fileUrlDataController = fileUrlDataController
        self.exportController = ExportController(module: itemController.module, itemController: itemController, fileUrlDataController: fileUrlDataController, gameExporter: false)
        self.gameModel = ItemGameModel()
        self.photoGameModel = PhotoGameModel()
    }

    let itemController: ItemController
    let fileUrlDataController: FileUrlDataController
    let exportController: ExportController
    
    public let gameModel: ItemGameModel
    let photoGameModel: PhotoGameModel
}

extension GameController: GameControllable {
    public var itemControllable: any ItemControllable {
        itemController as (any ItemControllable)
    }
    public var exportControllable: any ExportControllable {
        exportController as ExportControllable
    }
    @MainActor public var importControllable: any ImportControllable {
        ImportController(itemController: self, fileUrlDataController: fileUrlDataController, module: itemController.module)
    }
    
    public func resetGameState() {
        photoGameModel.reset()
    }
}

extension GameController: ImportDataControllable {
    public var container: ModelContainer {
        itemController.container
    }
    
    public func item(for id: UUID) -> ItemDataModel? {
        guard let codableModel = gameItem(for: id) else { return nil }
        return ItemDataModel(codableModel: codableModel)
    }
}

extension GameController: PhotoGameControllable {
    @MainActor
    public func resetPhotoSpace() {
        photoGameModel.openPhotoSpace <=> false
    }

    public func updateGame(data: NetworkCodableDataType, subtype: RPGMessageActionType) async throws {
        guard subtype == .photoSpace else { return }
#if os(visionOS)
        Task { @MainActor in
            photoGameModel.currentSelection = PhotoWorldSelection(id: data.id, rotationDegrees: 67)
            photoGameModel.openPhotoSpace <=> true
        }
#endif
    }
}
