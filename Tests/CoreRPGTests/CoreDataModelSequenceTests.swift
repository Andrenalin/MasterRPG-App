// @copyright André Trettin

#if canImport(Testing)
import CoreData
import Foundation
import Testing

@testable import CoreRPG

/// CODE_AUDIT_19 §3.4: a rollback that re-queues an older flushed edit must not let it win over
/// a newer edit for the same id that a flush already drained.
struct CoreDataModelSequenceTests {
    private func operation(_ id: UUID, _ name: String) -> PendingOperation {
        PendingOperation(id: id, model: name, updater: { _, _ in })
    }

    private func names(_ operations: [PendingOperation]) -> [String] {
        operations.compactMap { $0.model as? String }
    }

    @Test func rollbackDropsAnOperationSupersededByADrainedOne() {
        let sut = CoreDataModel()
        let id = UUID()

        sut.addPendingOperation(operation(id, "E1"))
        sut.markInFlight(sut.clearPendingOperations())
        // A second flush drains E2 and is still waiting for the context when another module's
        // failed save rolls the context back.
        sut.addPendingOperation(operation(id, "E2"))
        _ = sut.clearPendingOperations()
        sut.restoreInFlight()

        #expect(sut.clearPendingOperations().isEmpty)
    }

    @Test func rollbackRequeuesFlushedOperationsInFrontOfNewerEdits() throws {
        let sut = CoreDataModel()
        let id = UUID()
        let otherId = UUID()

        sut.addPendingOperation(operation(id, "E1"))
        sut.addPendingOperation(operation(otherId, "Other"))
        sut.markInFlight(sut.clearPendingOperations())
        sut.addPendingOperation(operation(id, "E2"))
        sut.restoreInFlight()

        // The restored operations go in front of the newer queued edit; E2 keeps the higher
        // sequence, so the flush's per-id merge still picks it.
        let pending = sut.clearPendingOperations()
        #expect(names(pending) == ["E1", "Other", "E2"])
        let e1 = try #require(pending.first { $0.model as? String == "E1" })
        let e2 = try #require(pending.first { $0.model as? String == "E2" })
        #expect(e2.sequence > e1.sequence)
    }

    @Test func failedFlushRestoreKeepsTheNewestOperationPerId() {
        let sut = CoreDataModel()
        let id = UUID()

        sut.addPendingOperation(operation(id, "E1"))
        sut.addPendingOperation(operation(id, "E2"))
        let drained = sut.clearPendingOperations()
        sut.restorePendingOperations(drained)

        #expect(names(sut.clearPendingOperations()) == ["E2"])
    }
}
#endif
