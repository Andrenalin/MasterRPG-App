// @copyright André Trettin

import SwiftUI

struct FakeImportController: ImportControllable {
    var itemControllable: any ItemControllable
    var editControllable: any EditControllable
    
    var importModel: ItemDataImportModel
    
    @MainActor
    static let fake = FakeImportController(itemControllable: FakeItemController.fake, editControllable: FakeEditController.fake, importModel: ItemDataImportModel())
}
