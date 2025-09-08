// @copyright André Trettin

import Foundation

struct FakeExportController: ExportControllable {
    @MainActor init(itemControllable: any ItemControllable) {
        self.itemControllable = itemControllable
        self.exportModel = ItemDataExportModel()
    }
    
    let itemControllable: any ItemControllable
    let fileUrlDataController: FileUrlDataController? = nil
    let module: NetworkModules = .none
    let version: Int = 2024

    let exportModel: ItemDataExportModel
}
