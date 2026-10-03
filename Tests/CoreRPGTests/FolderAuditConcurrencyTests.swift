// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

/// CODE_AUDIT_Folder §3: concurrency fixes that can be checked without a module root.
@Suite("Folder audit concurrency fixes")
@MainActor
struct FolderAuditConcurrencyTests {
    @Test("waitUntilIdle returns at once when no mutation holds the lock (§3.5)")
    func waitUntilIdleWhenIdle() async {
        let coordinator = DataMutationCoordinator()
        await coordinator.waitUntilIdle()
        #expect(coordinator.isActive == false)
    }

    @Test("waitUntilIdle resumes once the active mutation ends (§3.5)")
    func waitUntilIdleResumesAfterEnd() async throws {
        let coordinator = DataMutationCoordinator()
        let token = try #require(coordinator.begin())
        let waiter = Task { @MainActor in
            await coordinator.waitUntilIdle()
            return coordinator.isActive
        }
        await Task.yield()
        coordinator.end(token)
        #expect(await waiter.value == false)
    }

    @Test("A ledger scan keeps entries that changed while it ran (§3.11)")
    func ledgerScanKeepsConcurrentChanges() {
        let ledger = PlayerVersionLedger()
        let master = UUID()
        let changedDuringScan = UUID()
        let unchanged = UUID()
        let noLongerLocal = UUID()
        let addedDuringScan = UUID()
        ledger.playerVersions = [
            changedDuringScan: [master: 1],
            unchanged: [master: 1],
            noLongerLocal: [master: 1]
        ]
        let snapshot = ledger.versions(for: master)

        // `setMasterVersion` calls that land while the scan awaits.
        ledger.playerVersions[changedDuringScan]?[master] = 5
        ledger.playerVersions[addedDuringScan] = [master: 7]

        ledger.apply(
            scanned: [changedDuringScan: 2, unchanged: 3],
            for: master,
            startedFrom: snapshot
        )

        #expect(ledger.versions(for: master) == [
            changedDuringScan: 5,
            unchanged: 3,
            addedDuringScan: 7
        ])
    }

    @Test("A ledger scan leaves other participants' entries alone (§3.11)")
    func ledgerScanKeepsOtherPlayers() {
        let ledger = PlayerVersionLedger()
        let master = UUID()
        let player = UUID()
        let item = UUID()
        ledger.playerVersions = [item: [master: 1, player: 1]]
        let snapshot = ledger.versions(for: master)

        ledger.apply(scanned: [:], for: master, startedFrom: snapshot)

        #expect(ledger.versions(for: master).isEmpty)
        #expect(ledger.version(for: item, playerId: player) == 1)
    }

    @Test("Sync batches queued before a data reset are skipped (§3.19)")
    func syncBatchesQueuedBeforeResetAreDiscarded() async throws {
        let model = ItemDataModel()
        let beforeReset = UUID()
        let afterReset = UUID()
        model.enqueueSyncBatch(deletedIds: [], insertedIds: [beforeReset], updatedIds: [])
        model.discardQueuedSyncBatches()
        model.enqueueSyncBatch(deletedIds: [], insertedIds: [afterReset], updatedIds: [])

        var iterator = model.syncBatches.makeAsyncIterator()
        let first = try #require(await iterator.next())
        let second = try #require(await iterator.next())

        #expect(first.insertedIds == [beforeReset])
        #expect(first.sequence <= model.discardedSyncBatchSequence)
        #expect(second.insertedIds == [afterReset])
        #expect(second.sequence > model.discardedSyncBatchSequence)
    }
}
