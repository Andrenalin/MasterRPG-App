// @copyright André Trettin

import SwiftUI

struct FakeExportController: ExportControllable {
    var itemControllable: any ItemControllable
    
    var exportModel: ItemDataExportModel
    
    @MainActor
    static let fake = FakeExportController(itemControllable: FakeItemController.fake, exportModel: ItemDataExportModel())
}
