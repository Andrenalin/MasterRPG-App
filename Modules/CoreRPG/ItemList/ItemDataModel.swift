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

    // Injected after construction, once the async Core Data context becomes available —
    // lets ItemController be built eagerly without waiting on it.
    @ObservationIgnored public var dataController: (any DataPersistenceControllable)?
    @ObservationIgnored public var linkRegisterController: LinkRegisterController?
    @ObservationIgnored public var contentWidgetPublisher: (@MainActor @Sendable () -> Void)?

    /// Set whenever `ItemControllable.save()`/`flushPendingOperations()`/`resetData()`'s batch
    /// delete fails. `nil` once a following persistence call succeeds. UI can observe this to
    /// surface a recoverable-error alert instead of silently discarding an edit that never
    /// reached disk. See CODE_AUDIT §5.1.
    public internal(set) var lastPersistenceError: (any Error)?

    public var items: [UUID] = []
    public var itemData: [UUID: ModelType] = [:]
    
    public var gameItems: [UUID] = []
    public var gameItemData: [UUID: ModelType] = [:]

    public let categoryTags: [ItemListCategory]
    public let version: Int
           
    public var isGameMode: Bool = false
    
    public func resetGame(start: Bool = false) {
        isGameMode = start
    }
    
    func item(for itemId: UUID, noGame: Bool = false) -> ModelType? {
        guard noGame == false, let gameItem = gameItemData[itemId] else { return itemData[itemId] }
        return gameItem
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

    public func publishContentWidgetSnapshot() {
        contentWidgetPublisher?()
    }
}
