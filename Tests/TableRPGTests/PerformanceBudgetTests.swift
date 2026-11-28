// @copyright André Trettin

#if canImport(Testing)
import CoreData
@testable import CoreRPG
import DiceRPG
import Foundation
import PdfRPG
import Testing

@testable import TableRPG

/// CODE_AUDIT_TestGaps §7.1: time budgets for the paths that grew slow before (a full reindex per
/// save, a synchronous load on init). The budgets are generous on purpose, 10 to 20 times what a
/// development Mac needs (write 3.3 s, read 1.5 s, import 3.1 s, export 0.06 s): they catch a change from linear to quadratic work, not a slow machine.
/// The measured time is printed so the margin can be read from the log.
@MainActor
@Suite("Performance budgets: library and import")
struct PerformanceBudgetTests {
    private static func elapsed(_ work: () async throws -> Void) async rethrows -> Duration {
        try await ContinuousClock().measure { try await work() }
    }

    @Test("A library of 10 000 tables is written, saved and read back within the budget")
    func largeLibraryLoads() async throws {
        let store = try BudgetTestStore(bundles: [CoreRPG.Resources.bundle, TableRPG.Resources.bundle])
        let sut = DataController(context: store.context, token: NetworkModules.table.token)
        let ids = (0..<10_000).map { _ in UUID() }

        let writeTime = try await Self.elapsed {
            for (index, id) in ids.enumerated() {
                let model = TableModel(id: id, name: "Table \(index)", description: "", tags: ["library"], category: .loot, displayState: 0, tableType: .list, diceId: nil, entries: [], parentId: nil)
                try sut.replaceSync(id: id, with: model)
            }
            try await sut.save()
        }
        var loaded = 0
        let readTime = try await Self.elapsed {
            loaded = try await sut.fetchAll().count
        }

        print("PERF library 10000 tables: write \(writeTime), read \(readTime)")
        #expect(loaded == ids.count)
        #expect(writeTime < .seconds(60), "writing 10 000 items took \(writeTime)")
        #expect(readTime < .seconds(30), "loading 10 000 items took \(readTime)")
    }

    @Test("A table with 5 000 entries is exported and imported within the budget")
    func largeEntryListRoundTrips() async throws {
        let source = TableRootModel.testRoot(diceRoot: DiceRootModel.testRoot(), pdfRoot: PdfRootModel.testRoot())
        let tableId = await source.itemController.addNew(type: .item)
        let entries = (0..<5_000).map { TableEntryModel(id: UUID(), name: "Entry \($0)", content: "Result number \($0) of the large table") }
        source.editController.save(updated: TableModel(id: tableId, name: "Big", entries: entries), message: "Create table", forceSave: false)
        let exportIds = source.exportController.exporting(itemIds: ItemModuleIds(ids: [tableId], module: .table))

        let stream = OutputStream.toMemory()
        stream.open()
        let exportTime = try await Self.elapsed {
            _ = try await source.exportController.export(itemIds: exportIds, into: stream)
        }
        stream.close()
        let data = try #require(stream.property(forKey: Stream.PropertyKey.dataWrittenToMemoryStreamKey) as? Data)

        let target = TableRootModel.testRoot(diceRoot: DiceRootModel.testRoot(), pdfRoot: PdfRootModel.testRoot())
        let importStream = InputStream(data: data)
        importStream.open()
        defer { importStream.close() }
        let importTime = try await Self.elapsed {
            try await target.importController.importStream(from: importStream, forceSave: false)
        }

        print("PERF 5000-entry table: export \(exportTime), import \(importTime), \(data.count) bytes")
        let importedItem = await target.itemController.item(for: tableId)
        let imported = try #require(importedItem)
        #expect(imported.entries.count == 5_000)
        #expect(exportTime < .seconds(30), "exporting 5 000 entries took \(exportTime)")
        #expect(importTime < .seconds(30), "importing 5 000 entries took \(importTime)")
    }
}

private struct BudgetTestStore {
    let container: NSPersistentContainer
    let context: NSManagedObjectContext

    @MainActor
    init(bundles: [Bundle]) throws {
        let model = try #require(NSManagedObjectModel.mergedModel(from: bundles))
        container = NSPersistentContainer(name: "PerformanceBudget-\(UUID().uuidString)", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: (any Error)?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        context = container.newBackgroundContext()
    }
}
#endif
