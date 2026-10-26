// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

/// CODE_AUDIT_AppIntents §7.1: the App Entity reindex works on the ids that changed.
@Suite("Index dirty tracking")
@MainActor
struct IndexDirtyTrackingTests {
    @Test("Adding, replacing and removing an item mark its id; taking clears them")
    func itemChangesAreMarkedUntilTaken() {
        let model = ItemDataModel()
        let added = UUID()
        let removed = UUID()
        #expect(model.hasIndexChanges == false)

        model.setItem(id: added, item: FakeItemModel(id: added, name: "Added"))
        model.resetModel(id: removed)

        #expect(model.hasIndexChanges)
        #expect(model.takeIndexDirtyIds() == [added, removed])
        #expect(model.hasIndexChanges == false)
        #expect(model.takeIndexDirtyIds().isEmpty)
    }

    @Test("Marking the same id twice keeps one entry")
    func repeatedMarksCoalesce() {
        let model = ItemDataModel()
        let itemId = UUID()
        model.markIndexDirty(itemId)
        model.markIndexDirty(itemId)
        #expect(model.takeIndexDirtyIds() == [itemId])
    }
}

/// CODE_AUDIT_AppIntents §7.1: a reindex that is running is never cancelled or run twice at once.
@Suite("App intent content invalidator", .serialized)
@MainActor
struct AppIntentContentInvalidatorTests {
    @MainActor
    final class Counter {
        var runs = 0
        var running = 0
        var overlapped = false
    }

    @Test("A burst of invalidations is one reindex; one during a reindex runs it again, never overlapping")
    func burstsCoalesceAndNeverOverlap() async throws {
        let counter = Counter()
        AppIntentContentInvalidator.configure {
            counter.runs += 1
            counter.running += 1
            if counter.running > 1 { counter.overlapped = true }
            try? await Task.sleep(for: .seconds(2))
            counter.running -= 1
        }
        defer { AppIntentContentInvalidator.configure { } }

        for _ in 0..<5 { AppIntentContentInvalidator.invalidate() }
        try await Task.sleep(for: .seconds(1.5))
        #expect(counter.runs == 1, "the burst ran once, after the debounce")
        #expect(counter.running == 1, "still inside the first reindex")

        // Arrives while the first reindex (1 s to 3 s) is running; its debounce ends at 2.5 s.
        AppIntentContentInvalidator.invalidate()
        try await Task.sleep(for: .seconds(4.5))

        #expect(counter.runs == 2, "the change made during the reindex is indexed afterwards")
        #expect(counter.overlapped == false)
        #expect(counter.running == 0)
    }
}
