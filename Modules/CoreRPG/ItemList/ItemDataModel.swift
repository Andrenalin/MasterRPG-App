// @copyright André Trettin

import Foundation
import Observation

public typealias ModelType = Observable & Sendable

/// Holds a `SheetRootModel` weakly so a live registration never keeps an
/// otherwise-deallocated sheet instance (e.g. a dismissed Battle Round card)
/// alive. See `ItemDataModel.registerItemChangeObserver(_:itemId:)`.
@MainActor
private final class WeakSheetRootModelBox {
    weak var value: SheetRootModel?
    init(_ value: SheetRootModel) { self.value = value }
}

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

    /// Live `SheetRootModel` instances currently showing a given item, keyed by
    /// itemId. A single item can be materialized by several independent
    /// instances at once — the standalone editor's singleton, a live game view,
    /// a Battle Round card — each with its own cached `SheetModel` tree that
    /// only reconciles itself in response to its own local edits (see
    /// `Docu/SHEETS.md`). This registry is the missing link: it lets an edit
    /// made through any one instance tell every other live instance showing the
    /// same item to reconcile too.
    @ObservationIgnored private var itemChangeObservers: [UUID: [WeakSheetRootModelBox]] = [:]

    /// Registers `observer` to have `updateFromRoot()` called whenever this
    /// item changes through a different code path. Safe to call repeatedly for
    /// the same observer/itemId. Not `public`: `SheetRootModel` is the only
    /// intended caller, and both types live in this module.
    func registerItemChangeObserver(_ observer: SheetRootModel, itemId: UUID) {
        itemChangeObservers[itemId, default: []].append(WeakSheetRootModelBox(observer))
    }

    /// Tells every other live `SheetRootModel` currently showing `itemId` to
    /// reconcile its materialized tree with the domain data that just changed.
    /// Calling this on the instance that made the edit itself is harmless —
    /// `updateFromRoot()` is a no-op idempotent resync.
    func publishItemChanged(itemId: UUID) {
        guard let boxes = itemChangeObservers[itemId] else { return }
        let live = boxes.compactMap(\.value)
        itemChangeObservers[itemId] = live.isEmpty ? nil : live.map(WeakSheetRootModelBox.init)
        for observer in live {
            observer.updateFromRoot()
        }
    }

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
