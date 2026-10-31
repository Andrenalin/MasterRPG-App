// @copyright André Trettin

import CoreData
import Foundation
import Testing

@testable import CoreRPG

/// Sorting duplicate rows needs the CloudKit record names. The lookup waits on a utility-priority
/// queue of the container, so a save looks the names up before it takes the context's thread, and
/// a pass that meets duplicates with unknown names changes nothing and asks for them.
@MainActor
@Suite("Duplicate row order – record name lookup")
struct DuplicateRowOrderLookupTests {
    private func makeContext() throws -> (NSManagedObjectContext, URL) {
        let momd = try #require(CoreRPG.Resources.bundle.url(forResource: "Model", withExtension: "momd"))
        let model = try #require(NSManagedObjectModel(contentsOf: momd))
        let folder = URL.temporaryDirectory.appending(path: "DuplicateRowOrderLookupTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try coordinator.addPersistentStore(type: .sqlite, configuration: nil, at: folder.appending(path: "store.sqlite"), options: nil)
        let context = NSManagedObjectContext(.mainQueue)
        context.persistentStoreCoordinator = coordinator
        return (context, folder)
    }

    private func insertTag(_ title: String, count: Int32, module: Int16 = 3, in context: NSManagedObjectContext) -> TagDataModel {
        let tag = TagDataModel(context: context)
        tag.module = module
        tag.title = title
        tag.count = count
        return tag
    }

    @Test("The lookup reports which rows it covered, and none has a record name without a CloudKit container")
    func lookupCoversTheAskedRows() async throws {
        let (context, folder) = try makeContext()
        defer { try? FileManager.default.removeItem(at: folder) }
        let rows = [insertTag("A", count: 1, in: context), insertTag("A", count: 2, in: context)]
        try context.save()

        let names = await DuplicateRowOrder.recordNames(for: rows.map(\.objectID))

        #expect(names.covers(rows))
        #expect(names.byObjectId.isEmpty, "a local store has no CloudKit records")
        #expect(!DuplicateRowOrder.RecordNames().covers(rows), "rows nobody looked up are not covered")
    }

    @Test("Rows are sorted with looked-up names the way the blocking call sorts them")
    func sortedUsingNamesMatchesTheBlockingSort() async throws {
        let (context, folder) = try makeContext()
        defer { try? FileManager.default.removeItem(at: folder) }
        let rows = (0..<4).map { insertTag("A", count: Int32($0), in: context) }
        try context.save()

        let names = await DuplicateRowOrder.recordNames(for: rows.map(\.objectID))

        #expect(DuplicateRowOrder.sorted(rows, using: names).map(\.objectID) == DuplicateRowOrder.sorted(rows).map(\.objectID))
    }

    @Test("A tag save keeps one of the duplicate rows and leaves the others' module alone")
    func tagSaveRemovesDuplicates() async throws {
        let (context, folder) = try makeContext()
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = insertTag("Dragon", count: 1, in: context)
        _ = insertTag("Dragon", count: 1, in: context)
        _ = insertTag("Dragon", count: 1, in: context)
        _ = insertTag("Dragon", count: 1, module: 4, in: context)
        try context.save()

        let controller = TagController()
        controller.model.context = context
        controller.reset(tag: "Dragon", count: 5, module: NetworkModules(rawValue: 3) ?? .none)
        try await controller.savePendingTags()

        let request: NSFetchRequest<NSFetchRequestResult> = TagDataModel.fetchRequest()
        let rows = try #require(try context.fetch(request) as? [TagDataModel])
        let ofModule3 = rows.filter { $0.module == 3 }
        #expect(ofModule3.count == 1)
        #expect(ofModule3.first?.count == 5)
        #expect(rows.filter { $0.module == 4 }.count == 1, "the other module was not part of the save")
        #expect(!context.hasChanges, "the save was committed")
    }

    @Test("A tag save without duplicates writes the changed row in a single pass")
    func tagSaveWithoutDuplicates() async throws {
        let (context, folder) = try makeContext()
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = insertTag("Elf", count: 1, in: context)
        try context.save()

        let controller = TagController()
        controller.model.context = context
        controller.reset(tag: "Elf", count: 2, module: NetworkModules(rawValue: 3) ?? .none)
        try await controller.savePendingTags()

        let request: NSFetchRequest<NSFetchRequestResult> = TagDataModel.fetchRequest()
        let rows = try #require(try context.fetch(request) as? [TagDataModel])
        #expect(rows.count == 1)
        #expect(rows.first?.count == 2)
    }
}
