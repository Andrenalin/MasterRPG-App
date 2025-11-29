// @copyright André Trettin

import SwiftUI

struct FakeImportController: ImportControllable {
    var itemControllable: any ItemControllable
    
    var importModel: ItemDataImportModel
    
    @MainActor
    static let fake = FakeImportController(itemControllable: FakeItemController.fake, importModel: ItemDataImportModel())
}
