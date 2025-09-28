// @copyright André Trettin

import Foundation

struct FakeImportController: ImportControllable {
    @MainActor init(itemControllable: any ItemControllable) {
        self.itemControllable = itemControllable
        self.importModel = ItemDataImportModel()
        self.module = itemControllable.module
    }
    
    let itemControllable: any ItemControllable
    let fileUrlDataController: FileUrlDataController? = nil
    let importModel: ItemDataImportModel
    let module: NetworkModules
    
}
