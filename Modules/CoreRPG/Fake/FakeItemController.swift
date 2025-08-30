// @copyright André Trettin


import Foundation
import SwiftData

struct FakeItemController: ItemControllable, Sendable {

    let container: ModelContainer
    let collectionCategory: ItemListCategory = .album
    
    func encodedItemData(for: UUID) async -> Data? { nil }
}
