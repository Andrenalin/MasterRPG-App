// @copyright André Trettin


import Foundation
import SwiftData

struct FakeItemController: ItemControllable, Sendable {

    let container: ModelContainer
    let collectionCategory: ItemListCategory = .album

    @MainActor func decodedItem(data: Data, version: Int) throws -> ItemDataCodableModel { itemDataCodableModel(for: UUID())! }
    @MainActor func encodedItemData(for: UUID) -> Data? { nil }
}
