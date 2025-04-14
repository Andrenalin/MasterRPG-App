// @copyright André Trettin

import Foundation
import Observation

public typealias ModelType = Observable & Sendable

@MainActor @Observable
public final class ItemDataModel: Sendable {
    public init(categoryTags: [ItemListCategory], networkModule: NetworkModules, version: Int = 2024) {
        self.categoryTags = categoryTags
        self.networkModule = networkModule
        self.version = version
    }

    public var items: [UUID] = []
    public var itemData: [UUID: ModelType] = [:]

    public var allTags: [String] = []

    public let categoryTags: [ItemListCategory]
    public let networkModule: NetworkModules
    public let version: Int
    public internal(set) var updateHiddenCounter: Int = 0
    
    public func copyWithoutItems() -> ItemDataModel {
        ItemDataModel(categoryTags: categoryTags, networkModule: networkModule, version: version)
    }
    
    func updateTags(with newTags: [String]) {
        let tags = newTags.map { $0.localizedUppercase }.filter { !allTags.contains($0) }
        guard !tags.isEmpty else { return }
        allTags.append(contentsOf: tags)
        allTags.sort { $0.localizedCompare($1) == .orderedAscending }
    }
    
    func item(for itemId: UUID) -> ModelType? {
        itemData[itemId]
    }
    
    func increaseHiddenCounter() {
        updateHiddenCounter += 1
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

public enum ListFilterOptions: Equatable, Hashable, Sendable {
    case notMatch
    case match
    case childrenMatch
    case onlyChildrenMatch
}
