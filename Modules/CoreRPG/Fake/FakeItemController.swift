// @copyright André Trettin


import Foundation
import SwiftData

@MainActor
struct FakeItemController: ItemControllable, Sendable {
    let itemCacheModel: ItemCacheModel = ItemCacheModel()
    let container: ModelContainer
    let collectionCategory: ItemListCategory = .album
    let module: NetworkModules
    
    @MainActor func decodedItem(data: Data, version: Int) throws -> ItemDataCodableModel { itemDataCodableModel(for: UUID())! }
    @MainActor func encodedItemData(for: UUID) -> Data? { nil }
}
