// @copyright André Trettin

import CoreRPG
import Foundation

struct ImportController: Sendable {
    @MainActor
    init(itemController: ImportDataControllable, fileUrlDataController: FileUrlDataController, module: NetworkModules) {
        self.itemController = itemController
        self.fileUrlDataController = fileUrlDataController
        self.module = module
        self.importModel = ItemDataImportModel()
    }
    
    let itemController: ImportDataControllable
    let fileUrlDataController: FileUrlDataController?
    let module: NetworkModules
    let importModel: ItemDataImportModel
}

extension ImportController: ImportControllable {
    var itemControllable: any ImportDataControllable {
        itemController
    }
}
