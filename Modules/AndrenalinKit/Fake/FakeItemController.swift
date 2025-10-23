// @copyright André Trettin

import SwiftUI

struct FakeItemController: ItemControllable {
    typealias Model = FakeItemModel
    
    var dataControllable: (any DataPersistenceControllable)?
    var fileUrlDataController: FileUrlDataController? 
    var linkRegisterControllable: any LinkRegisterControllable
    
    var itemDataModel: ItemDataModel
    
    func children(for model: ItemRowModel) -> [ItemRowModel] {
        []
    }
    
    func didDelete(model: any ModelType) async {}
    
    func didUpdate(model: any ModelType) async {}
    
    @MainActor
    static let fake = FakeItemController(linkRegisterControllable: FakeLinkRegisterController.fake, itemDataModel: ItemDataModel(categoryTags: [.all], networkModule: .photo))
}
