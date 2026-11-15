// @copyright André Trettin

import CoreData
import Foundation
import Testing

@testable import CoreRPG

/// CODE_AUDIT_26 §5.9: the tag table is hydrated from the store before a save may replace the rows.
@MainActor
@Suite("TagController hydration")
struct TagControllerHydrationTests {
    private let module = NetworkModules(rawValue: 3) ?? .none

    private func makeContext() throws -> (NSManagedObjectContext, URL) {
        let momd = try #require(CoreRPG.Resources.bundle.url(forResource: "Model", withExtension: "momd"))
        let model = try #require(NSManagedObjectModel(contentsOf: momd))
        let folder = URL.temporaryDirectory.appending(path: "TagControllerHydrationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        _ = try coordinator.addPersistentStore(type: .sqlite, configuration: nil, at: folder.appending(path: "store.sqlite"), options: nil)
        let context = NSManagedObjectContext(.mainQueue)
        context.persistentStoreCoordinator = coordinator
        return (context, folder)
    }

    private func insertTag(_ title: String, count: Int32, in context: NSManagedObjectContext) {
        let tag = TagDataModel(context: context)
        tag.module = 3
        tag.title = title
        tag.count = count
    }

    private func tag(_ title: String, _ count: Int) -> TagModel {
        TagModel(module: module, title: title, count: count)
    }

    @Test("Persisted counts replace untouched tags, add the in-memory change to touched ones and spare absolute ones")
    func mergeRules() {
        let memory = ["Added": tag("Added", 1), "Removed-only": tag("Removed-only", 0), "Absolute": tag("Absolute", 9)]
        let persisted = [
            "Untouched": tag("Untouched", 4),
            "Added": tag("Added", 5),
            "Gone": tag("Gone", 1),
            "Absolute": tag("Absolute", 2),
        ]

        let result = TagController.merged(
            memory: memory,
            persisted: persisted,
            deltas: ["Added": 1, "Gone": -1],
            absolute: ["Absolute"]
        )

        #expect(result["Untouched"]?.count == 4)
        #expect(result["Added"]?.count == 6)
        #expect(result["Gone"] == nil, "5 persisted - 1 removed here leaves nothing for a count of 1 - 1")
        #expect(result["Absolute"]?.count == 9)
    }

    @Test("A save before the hydration finished keeps the persisted rows of the module")
    func saveHydratesFirst() async throws {
        let (context, folder) = try makeContext()
        defer { try? FileManager.default.removeItem(at: folder) }
        insertTag("Old", count: 2, in: context)
        try context.save()

        let controller = TagController()
        controller.model.context = context
        controller.add(tags: ["New"], module: module)
        try await controller.savePendingTags()

        let request: NSFetchRequest<NSFetchRequestResult> = TagDataModel.fetchRequest()
        let rows = try #require(try context.fetch(request) as? [TagDataModel])
        let counts = Dictionary(uniqueKeysWithValues: rows.map { ($0.title ?? "", Int($0.count)) })
        #expect(counts == ["Old": 2, "New": 1])
        #expect(controller.model.isHydrated)
    }

    @Test("A tag counted in memory before the fetch finished gets the persisted count added")
    func countsAddUpAfterTheFetch() async throws {
        let (context, folder) = try makeContext()
        defer { try? FileManager.default.removeItem(at: folder) }
        insertTag("Dragon", count: 3, in: context)
        try context.save()

        let controller = TagController()
        controller.model.context = context
        controller.add(tags: ["Dragon"], module: module)
        try await controller.savePendingTags()

        #expect(controller.model.tags[module]?["Dragon"]?.count == 4)
        let request: NSFetchRequest<NSFetchRequestResult> = TagDataModel.fetchRequest()
        let rows = try #require(try context.fetch(request) as? [TagDataModel])
        #expect(rows.map(\.count) == [4])
    }

    @Test("A failing fetch skips the save, keeps the pending change and the persisted rows, and retries later")
    func failedFetchSkipsTheSave() async throws {
        let (context, folder) = try makeContext()
        defer { try? FileManager.default.removeItem(at: folder) }
        insertTag("Old", count: 2, in: context)
        try context.save()

        let controller = TagController()
        controller.model.context = context
        controller.model.persistedFetchOverride = { _ in nil }
        controller.add(tags: ["New"], module: module)
        try await controller.savePendingTags()

        #expect(controller.model.hydrationFailed)
        #expect(!controller.model.isHydrated)
        #expect(controller.model.pendingAffectedModules == [module], "the change is kept for the next save")

        // The store comes back: the next save retries the fetch and then saves.
        controller.model.persistedFetchOverride = nil
        try await controller.savePendingTags()

        let request: NSFetchRequest<NSFetchRequestResult> = TagDataModel.fetchRequest()
        let rows = try #require(try context.fetch(request) as? [TagDataModel])
        let counts = Dictionary(uniqueKeysWithValues: rows.map { ($0.title ?? "", Int($0.count)) })
        #expect(counts == ["Old": 2, "New": 1])
        #expect(!controller.model.hydrationFailed)
    }
}
