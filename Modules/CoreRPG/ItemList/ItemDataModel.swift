// @copyright André Trettin

import Foundation
import Observation
import Synchronization

public typealias ModelType = Observable & Sendable

/// One CloudKit change notification for a module, numbered in the order it arrived.
struct SyncBatch: Sendable {
    let sequence: UInt64
    let deletedIds: [UUID]
    let insertedIds: [UUID]
    let updatedIds: [UUID]
}

@MainActor @Observable
public final class ItemDataModel: Sendable {
    public init(categoryTags: [ItemListCategory], version: Int = 2024) {
        self.categoryTags = categoryTags
        self.version = version
        (syncBatches, syncBatchContinuation) = AsyncStream<SyncBatch>.makeStream()
    }

    // Injected after construction, once the async Core Data context becomes available —
    // lets ItemController be built eagerly without waiting on it.
    @ObservationIgnored public var dataController: (any DataPersistenceControllable)?
    @ObservationIgnored public var linkRegisterController: LinkRegisterController?
    @ObservationIgnored public var contentWidgetPublisher: (@MainActor @Sendable () -> Void)?

    /// Set whenever `ItemControllable.save()`/`flushPendingOperations()`/`resetData()`'s batch
    /// delete fails. `nil` once a following save succeeds (a flush alone doesn't clear it).
    /// The UI shows the app-wide `PersistenceIssueCenter` instead. See CODE_AUDIT §5.1,
    /// CODE_AUDIT_19 §5.13.
    public internal(set) var lastPersistenceError: (any Error)?

    public var items: [UUID] = []
    public var itemData: [UUID: ModelType] = [:]
    
    public var gameItems: [UUID] = []
    public var gameItemData: [UUID: ModelType] = [:]

    /// CloudKit change batches for this module, applied one at a time by a single consumer
    /// task in the order they were enqueued. A stream instead of a chain of tasks: the chain
    /// only kept arrival order if the tasks that built it happened to run first-in, first-out.
    /// See CODE_AUDIT_EditItem §3.2, CODE_AUDIT_Folder §3.19.
    nonisolated let syncBatches: AsyncStream<SyncBatch>
    nonisolated let syncBatchContinuation: AsyncStream<SyncBatch>.Continuation
    nonisolated private let syncBatchSequence = Mutex<UInt64>(0)
    @ObservationIgnored var syncBatchConsumer: Task<Void, Never>?
    /// Batches numbered up to this value were queued before a data reset and are skipped.
    @ObservationIgnored private(set) var discardedSyncBatchSequence: UInt64 = 0

    /// Queues one change notification. Safe to call from the Core Data observer's thread.
    nonisolated func enqueueSyncBatch(deletedIds: [UUID], insertedIds: [UUID], updatedIds: [UUID]) {
        let sequence = syncBatchSequence.withLock { value -> UInt64 in
            value += 1
            return value
        }
        syncBatchContinuation.yield(SyncBatch(sequence: sequence, deletedIds: deletedIds, insertedIds: insertedIds, updatedIds: updatedIds))
    }

    /// Skips every batch queued so far; called when the module's data is reset, so a batch from
    /// before the reset no longer applies after it.
    func discardQueuedSyncBatches() {
        discardedSyncBatchSequence = syncBatchSequence.withLock { $0 }
    }

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
        // Previously left untouched: a deleted item stayed fully resolvable via
        // `item(for:noGame:false)` (the default every read path uses) for as long as it
        // remained loaded into a live game session, since that path prefers
        // `gameItemData` over `itemData`. See CODE_AUDIT_EditItem §5.5.
        gameItemData[id] = nil
        if let index = gameItems.firstIndex(of: id) {
            gameItems.remove(at: index)
        }
    }

    /// Coalesces bursts of item changes (an import, a CloudKit sync) into one snapshot rebuild:
    /// every mutation used to walk all items, encode, write and ask WidgetKit to reload, which is
    /// quadratic over a bulk change and quickly exhausts WidgetKit's reload budget.
    /// See CODE_AUDIT_15 §7.4.
    public func publishContentWidgetSnapshot() {
        guard contentWidgetPublisher != nil else { return }
        contentWidgetPublishTask?.cancel()
        contentWidgetPublishTask = Task { [weak self] in
            try? await Task.sleep(for: Self.contentWidgetPublishDelay)
            guard !Task.isCancelled else { return }
            self?.contentWidgetPublisher?()
        }
    }

    private static let contentWidgetPublishDelay: Duration = .milliseconds(750)

    @ObservationIgnored private var contentWidgetPublishTask: Task<Void, Never>?
}
