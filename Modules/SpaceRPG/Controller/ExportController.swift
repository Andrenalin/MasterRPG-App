// @copyright André Trettin

import CoreRPG
import Foundation

struct ExportController: Sendable {
    @MainActor
    init(itemController: any OldItemControllable, fileController: FileController, gameExporter: Bool) {
        itemControllable = itemController
        fileControllable = fileController
        self.exportModel = ItemDataExportModel(gameExporter: gameExporter)
    }
    
    public let exportModel: ItemDataExportModel
    var fileControllable: (any FileControllable)?
    var itemControllable: any OldItemControllable

    var module: NetworkModules { SpaceDataModel.typeId }
    var version: Int { 2024 }
}
