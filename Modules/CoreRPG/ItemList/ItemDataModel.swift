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
    public init(version: Int = 2024) {
        self.version = version
        (syncBatches, syncBatchContinuation) = AsyncStream<SyncBatch>.makeStream()
    }

    // Injected after construction, once the async Core Data context becomes available —
    // lets ItemController be built eagerly without waiting on it.
    @ObservationIgnored public var dataController: (any DataPersistenceControllable)?
    @ObservationIgnored public var linkRegisterController: LinkRegisterController?
    @ObservationIgnored public var contentWidgetPublisher: (@MainActor @Sendable () -> Void)?
    /// Set by a module whose game copy carries session-only content (the Map module's player and
    /// companion pins, and battle clones' Character ids). Returns a cleaned copy of the model
    /// about to be written to the library, or `nil` when nothing in it is session-only. The
    /// game copy itself is never touched. A whole-model write from the item editor during a game
    /// otherwise stores that content in the library, where it outlives the game.
    @ObservationIgnored public var libraryWriteFilter: (@MainActor (ModelType) -> ModelType?)?

    /// Set whenever `ItemControllable.save()`/`flushPendingOperations()`/`resetData()`'s batch
    /// delete fails. `nil` once a following save succeeds (a flush alone doesn't clear it).
    /// The UI shows the app-wide `PersistenceIssueCenter` instead. See CODE_AUDIT §5.1,
    /// CODE_AUDIT_19 §5.13.
    public internal(set) var lastPersistenceError: (any Error)?

    public var items: [UUID] = []
    public var itemData: [UUID: ModelType] = [:]
    
    /// The items of the running game, the current one first. Another first item (an insert, a
    /// removal) ends `isGameCurrentCleared`.
    public var gameItems: [UUID] = [] {
        didSet {
            if gameItems.first != oldValue.first {
                isGameCurrentCleared = false
            }
        }
    }
    /// Set by `ItemGameModel.clearCurrent()`: the game has no current item although `gameItems`
    /// still holds its items (and their session state), so a later show finds them again.
    public var isGameCurrentCleared = false
    public var gameItemData: [UUID: ModelType] = [:]

    /// The ids `ItemControllable.delete` is working on. The item leaves memory before the
    /// delete's suspensions, so a sync batch that names the id in between would add it again.
    /// See CODE_AUDIT_21 §5.31.
    @ObservationIgnored var deletingIds: Set<UUID> = []

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

    /// Ends the sync consumer for good: a model whose module root is discarded (a rebuilt root,
    /// a test, a preview). The consumer holds the module's item controller, a struct that holds
    /// this model, so the pair is a cycle that only this breaks; a weak capture cannot.
    /// Batches enqueued afterwards are dropped. See CODE_AUDIT_Edit_Save §3.5.
    public func stopSyncConsumer() {
        syncBatchContinuation.finish()
        syncBatchConsumer?.cancel()
        syncBatchConsumer = nil
    }

    public let version: Int
           
    public var isGameMode: Bool = false {
        didSet {
            if oldValue != isGameMode { gameGeneration &+= 1 }
        }
    }

    /// A saved game is loaded into game memory but the game has not started. Until it starts,
    /// reads keep showing the library: preferring the staged game copies made every view and
    /// export show the saved versions, and the first edit wrote the saved state into the
    /// permanent item. See CODE_AUDIT_Folder §5.25.
    public internal(set) var isSavedGameStaged = false {
        didSet {
            if oldValue != isSavedGameStaged { gameGeneration &+= 1 }
        }
    }

    /// Changes whenever reads and writes switch between the library and game memory (a game
    /// starts or ends, a saved game is staged). An undo step made in one generation would write
    /// into the wrong place in another, so it is dropped. See CODE_AUDIT_Edit_Save §5.1.
    public private(set) var gameGeneration = 0

    public func resetGame(start: Bool = false) {
        isGameMode = start
        if !start {
            isSavedGameStaged = false
        }
    }

    func item(for itemId: UUID, noGame: Bool = false) -> ModelType? {
        guard noGame == false,
              isGameMode || !isSavedGameStaged,
              let gameItem = gameItemData[itemId] else { return itemData[itemId] }
        return gameItem
    }
    
    func insert(itemId: UUID, at index: Int?) {
        if let index {
            items.insert(itemId, at: index)
        } else {
            items.append(itemId)
        }
    }
    
    /// Not marked for the App Entity index: the initial load sets every item, and a new id is
    /// found by `reindexIntentEntities` through the ledger. See CODE_AUDIT_Since_3.0.1 §3.1.
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
        markIndexDirty(id)
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

    /// The ids edited, trashed or removed since the App Entity index last took them, so the
    /// Spotlight reindex touches only those instead of every item of every module. Marked by the
    /// item controller wherever it changes a library item; taken by `reindexIntentEntities`, which
    /// finds added ids through `AppEntityIndexLedger`. See CODE_AUDIT_AppIntents §7.1,
    /// CODE_AUDIT_Since_3.0.1 §3.1.
    @ObservationIgnored private var indexDirtyIds: Set<UUID> = []

    public var hasIndexChanges: Bool { !indexDirtyIds.isEmpty }

    public func markIndexDirty(_ id: UUID) {
        indexDirtyIds.insert(id)
    }

    public func takeIndexDirtyIds() -> Set<UUID> {
        defer { indexDirtyIds = [] }
        return indexDirtyIds
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
