// @copyright André Trettin

import CoreRPG
import Foundation

struct ImportController: Sendable {
    @MainActor
    init(itemController: ItemController, fileUrlDataController: FileUrlDataController, module: NetworkModules) {
        self.itemController = itemController
        self.fileUrlDataController = fileUrlDataController
        self.module = module
        self.importModel = ItemDataImportModel()
    }
    
    let itemController: ItemController
    let fileUrlDataController: FileUrlDataController?
    let module: NetworkModules
    let importModel: ItemDataImportModel
}

extension ImportController: ImportControllable {
    var itemControllable: any ImportDataControllable {
        itemController
    }
}
