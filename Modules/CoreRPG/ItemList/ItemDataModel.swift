// @copyright André Trettin

import Foundation
import Observation

public typealias ModelType = Observable & Sendable

@MainActor @Observable
public final class ItemDataModel: Sendable {
    public init(categoryTags: [ItemListCategory], version: Int = 2024) {
        self.categoryTags = categoryTags
        self.version = version
    }

    public var items: [UUID] = []
    public var itemData: [UUID: ModelType] = [:]

    public let categoryTags: [ItemListCategory]
    public let version: Int
            
    func item(for itemId: UUID) -> ModelType? {
        itemData[itemId]
    }
    
    func insert(itemId: UUID, at index: Int?) {
        if let index {
            items.insert(itemId, at: index)
        } else {
            items.append(itemId)
        }
    }
    
    func setItem(id: UUID, item: ModelType) {
        itemData[id] = item
    }
    
    func removeItem(itemId: UUID) -> Bool {
        guard let index = items.firstIndex(where: { $0 == itemId }) else { return false }
        items.remove(at: index)
        return true
    }
    
    func resetItems(_ items: [UUID]) {
        self.items = items
    }
    
    func resetModel(id: UUID) {
        itemData[id] = nil
        if let index = items.firstIndex(of: id) {
            items.remove(at: index)
        }
    }
}
