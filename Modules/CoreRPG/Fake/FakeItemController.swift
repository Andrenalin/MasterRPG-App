// @copyright André Trettin

import SwiftUI

struct FakeItemController: ItemControllable {
    typealias Model = FakeItemModel
    
    var config: any ModuleConfigurable
    var dataControllable: (any DataPersistenceControllable)?
    var fileUrlDataController: FileUrlDataController? 
    var linkRegisterController: LinkRegisterController
    
    var itemDataModel: ItemDataModel
        
    @MainActor
    static let fake = FakeItemController(config: FakeModuleConfiguration(), linkRegisterController: LinkRegisterController.fake, itemDataModel: ItemDataModel(categoryTags: [.all]))
}
