// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

struct ItemController: Sendable {
    @MainActor init(container: ModelContainer, module: NetworkModules) {
        self.itemCacheModel = ItemCacheModel()
        self.container = container
        self.module = module
    }
    let itemCacheModel: ItemCacheModel
    let container: ModelContainer
    let collectionCategory: ItemListCategory = .collection
    let module: NetworkModules
}


extension ItemController: ItemControllable {
    @MainActor func decodedItem(data: Data, version: Int) throws -> ItemDataCodableModel {
        let decoder = JSONDecoder()
        return try decoder.decode(ItemDataCodableModel.self, from: data)
    }
}
