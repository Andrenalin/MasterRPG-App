// @copyright André Trettin

import Foundation
import SwiftData

struct FakeLinkController: LinkControllable {
    let module: NetworkModules = .audio
    let itemController: FakeItemController
    
    var itemControllable: any ItemControllable {
        itemController
    }
    
    func generateLink(linkNumber: Int, itemId: UUID, entryId: UUID?) -> String {
        "Not set"
    }
    
    static let fake: FakeLinkController = FakeLinkController(itemController: FakeItemController(container: try! ModelContainer(for: ItemDataModel.self, TagDataModel.self, configurations: .init(isStoredInMemoryOnly: true))))
}
