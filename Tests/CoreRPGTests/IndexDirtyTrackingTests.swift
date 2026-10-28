// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

/// CODE_AUDIT_AppIntents §7.1: the App Entity reindex works on the ids that changed.
@Suite("Index dirty tracking")
@MainActor
struct IndexDirtyTrackingTests {
    @Test("Removing an item marks its id; taking clears them")
    func itemChangesAreMarkedUntilTaken() {
        let model = ItemDataModel()
        let removed = UUID()
        #expect(model.hasIndexChanges == false)

        model.resetModel(id: removed)

        #expect(model.hasIndexChanges)
        #expect(model.takeIndexDirtyIds() == [removed])
        #expect(model.hasIndexChanges == false)
        #expect(model.takeIndexDirtyIds().isEmpty)
    }

    /// CODE_AUDIT_Since_3.0.1 §3.1: the initial load sets every item, and marking them made every
    /// launch index every item of every module. New ids are found through the ledger instead.
    @Test("Setting an item, as the initial load does, marks nothing")
    func loadingAnItemMarksNothing() {
        let model = ItemDataModel()
        let loaded = UUID()
        model.setItem(id: loaded, item: FakeItemModel(id: loaded, name: "Loaded"))
        #expect(model.hasIndexChanges == false)
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

/// CODE_AUDIT_Since_3.0.1 §3.1: which ids a reindex pass looks at, and what the index covers after it.
@Suite("App Entity index pass")
struct AppEntityIndexPassTests {
    private let kept = UUID()
    private let added = UUID()
    private let gone = UUID()
    private let edited = UUID()

    @Test("The first run looks at every item and the marked ids")
    func firstRunCoversEverything() {
        let ids = AppEntityIndexPass.ids(current: [kept, added], changed: [gone], indexed: nil)
        #expect(ids == [kept, added, gone])
    }

    @Test("A launch without changes looks at nothing")
    func unchangedLaunchDoesNothing() {
        let ids = AppEntityIndexPass.ids(current: [kept, edited], changed: [], indexed: [kept, edited])
        #expect(ids.isEmpty)
    }

    @Test("Added, removed and marked ids are looked at, nothing else")
    func onlyChangesAreLookedAt() {
        let ids = AppEntityIndexPass.ids(current: [kept, added, edited], changed: [edited], indexed: [kept, gone, edited])
        #expect(ids == [added, gone, edited])
    }

    @Test("After a pass the index covers what exists and was looked at, now or before")
    func indexedAfterPass() {
        let indexed = AppEntityIndexPass.indexed(
            before: [kept, gone],
            looked: [added, gone],
            failed: [],
            current: [kept, added]
        )
        #expect(indexed == [kept, added])
    }

    @Test("Ids that failed to index stay out, so the next launch retries them")
    func failedIdsStayOut() {
        let indexed = AppEntityIndexPass.indexed(before: nil, looked: [kept, added], failed: [added], current: [kept, added])
        #expect(indexed == [kept])
        #expect(AppEntityIndexPass.ids(current: [kept, added], changed: [], indexed: indexed) == [added])
    }
}

/// CODE_AUDIT_Since_3.0.1 §3.1: the ids a module's index covers survive a relaunch.
@Suite("App Entity index ledger")
@MainActor
struct AppEntityIndexLedgerTests {
    private let directory = URL.temporaryDirectory.appending(path: "AppEntityIndexLedgerTests-\(UUID().uuidString)", directoryHint: .isDirectory)

    @Test("No list before the first run")
    func missingListIsNil() async {
        let ledger = AppEntityIndexLedger(directory: directory)
        #expect(await ledger.indexedIds(for: "rule") == nil)
    }

    @Test("A written list is read back by the next launch")
    func listSurvivesRelaunch() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let ids: Set<UUID> = [UUID(), UUID()]
        await AppEntityIndexLedger(directory: directory).setIndexedIds(ids, for: "map")

        let relaunched = AppEntityIndexLedger(directory: directory)
        #expect(await relaunched.indexedIds(for: "map") == ids)
        #expect(await relaunched.indexedIds(for: "dice") == nil, "each module keeps its own list")
    }

    @Test("An empty list differs from no list")
    func emptyListIsNotFirstRun() async {
        defer { try? FileManager.default.removeItem(at: directory) }
        await AppEntityIndexLedger(directory: directory).setIndexedIds([], for: "audio")
        #expect(await AppEntityIndexLedger(directory: directory).indexedIds(for: "audio") == [])
    }

    @Test("An unreadable list counts as missing, so the next run covers every item")
    func unreadableListIsNil() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: directory.appending(path: "pdf.json"))
        #expect(await AppEntityIndexLedger(directory: directory).indexedIds(for: "pdf") == nil)
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
        var cancelled = false
    }

    @Test("A burst of invalidations is one reindex; one during a reindex runs it again, never overlapping")
    func burstsCoalesceAndNeverOverlap() async throws {
        let counter = Counter()
        AppIntentContentInvalidator.configure {
            counter.runs += 1
            counter.running += 1
            if counter.running > 1 { counter.overlapped = true }
            try? await Task.sleep(for: .seconds(2))
            if Task.isCancelled { counter.cancelled = true }
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
        // CODE_AUDIT_Since_3.0.1 §3.3: the new debounce cancelled the task the reindex ran in.
        #expect(counter.cancelled == false, "the running reindex was not cancelled")
    }
}
