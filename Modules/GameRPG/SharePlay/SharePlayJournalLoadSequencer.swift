// @copyright André Trettin

import Foundation

/// Decides which Journal loads wait for which.
///
/// - Loads of different items run side by side, and a newer publication of an item waits only for
///   the older load of that same item.
/// - The first batch that has something to load (what a late joiner finds in the Journal) also
///   keeps the message order, so the last presentation the game master showed is applied last.
///   Each load of that batch waits for the one before it, and for nothing after it: a later
///   publication of an item in the batch waits for that item's load and the loads in front of
///   it, not for the whole batch.
///
/// A load whose session ended, or that is cancelled, ends without running its job.
/// See CODE_AUDIT_Game_Shareplay §7.1.
@MainActor
final class SharePlayJournalLoadSequencer {
    typealias Job = @MainActor @Sendable () async -> Void

    struct Load: Sendable {
        let itemId: UUID
        let job: Job

        init(_ itemId: UUID, job: @escaping Job) {
            self.itemId = itemId
            self.job = job
        }
    }

    private var tasks: [UUID: (token: UUID, task: Task<Void, Never>)] = [:]
    private var joinBatchHandled = false

    /// Items with a load that has not ended.
    var activeItemCount: Int { tasks.count }

    func start(
        _ loads: [Load],
        isCurrent: @escaping @MainActor () -> Bool
    ) {
        guard !loads.isEmpty else { return }
        let keepsOrder = !joinBatchHandled
        joinBatchHandled = true
        var previousInBatch: Task<Void, Never>?
        for load in loads {
            let itemId = load.itemId
            let token = UUID()
            let previousOfItem = tasks[itemId]?.task
            let predecessor = keepsOrder ? previousInBatch : nil
            let job = load.job
            let task = Task { @MainActor [weak self] in
                await previousOfItem?.value
                await predecessor?.value
                if !Task.isCancelled, isCurrent() {
                    await job()
                }
                self?.finish(token: token, itemId: itemId)
            }
            tasks[itemId] = (token, task)
            previousInBatch = task
        }
    }

    /// Cancels every load and forgets the batch, for the next session.
    func cancelAll() {
        tasks.values.forEach { $0.task.cancel() }
        tasks = [:]
        joinBatchHandled = false
    }

    /// Forgets the load of `itemId`, unless a newer load of the item replaced it.
    private func finish(token: UUID, itemId: UUID) {
        guard tasks[itemId]?.token == token else { return }
        tasks[itemId] = nil
    }
}
