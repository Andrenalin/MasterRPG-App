// @copyright André Trettin

#if canImport(Testing)
import CoreData
import Foundation
import Testing

@testable import MapRPG

/// The map model gained the optional `degrees`. A store written before that must open with the
/// lightweight migration the persistence controllers switch on (`shouldMigrateStoreAutomatically`,
/// `shouldInferMappingModelAutomatically`) and read the rotation as nil. The old schema is the
/// current model without the attribute.
@Suite("Map model migration")
struct MapModelMigrationTests {
    private static func currentModel() throws -> NSManagedObjectModel {
        let momd = try #require(MapRPG.Resources.bundle.url(forResource: "Model", withExtension: "momd"))
        let url = momd.appending(path: "RPGMap.mom")
        return try #require(NSManagedObjectModel(contentsOf: url))
    }

    private static func modelBeforeTheRotation() throws -> NSManagedObjectModel {
        let model = try #require(currentModel().copy() as? NSManagedObjectModel)
        let map = try #require(model.entitiesByName["RPGMap"])
        map.properties = map.properties.filter { $0.name != "degrees" }
        return model
    }

    private static func temporaryStoreUrl() throws -> URL {
        let folder = URL.temporaryDirectory.appending(path: "MapModelMigrationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "store.sqlite")
    }

    private static func loadStore(at url: URL, model: NSManagedObjectModel, migrate: Bool) throws -> NSPersistentStoreCoordinator {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let options: [AnyHashable: Any] = migrate
            ? [NSMigratePersistentStoresAutomaticallyOption: true, NSInferMappingModelAutomaticallyOption: true]
            : [:]
        let _ = try coordinator.addPersistentStore(type: .sqlite, configuration: nil, at: url, options: options)
        return coordinator
    }

    @Test("The rotation is the only difference to the schema before it")
    func onlyTheRotationIsNew() throws {
        let before = try Self.modelBeforeTheRotation()
        let current = try Self.currentModel()
        let beforeMap = try #require(before.entitiesByName["RPGMap"])
        let currentMap = try #require(current.entitiesByName["RPGMap"])

        #expect(beforeMap.attributesByName["degrees"] == nil)
        #expect(Set(currentMap.attributesByName.keys).subtracting(beforeMap.attributesByName.keys) == ["degrees"])
        #expect(before.entityVersionHashesByName["RPGMap"] != current.entityVersionHashesByName["RPGMap"])
        #expect(before.entityVersionHashesByName["RPGMapPin"] == current.entityVersionHashesByName["RPGMapPin"])
    }

    @Test("A mapping model can be inferred for the new attribute")
    func mappingIsInferred() throws {
        let mapping = try NSMappingModel.inferredMappingModel(
            forSourceModel: Self.modelBeforeTheRotation(),
            destinationModel: Self.currentModel()
        )

        #expect(!mapping.entityMappings.isEmpty)
    }

    @Test("A store from before the rotation opens with the migration, keeps its maps and reads the rotation as nil")
    func existingStoreMigrates() throws {
        let url = try Self.temporaryStoreUrl()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let before = try Self.modelBeforeTheRotation()
        let current = try Self.currentModel()
        let mapId = UUID()

        do {
            let coordinator = try Self.loadStore(at: url, model: before, migrate: false)
            let context = NSManagedObjectContext(.privateQueue)
            context.persistentStoreCoordinator = coordinator
            try context.performAndWait {
                let map = NSEntityDescription.insertNewObject(forEntityName: "RPGMap", into: context)
                map.setValue(mapId, forKey: "uuid")
                map.setValue("Old map", forKey: "name")
                map.setValue(640, forKey: "width")
                try context.save()
            }
            for store in coordinator.persistentStores {
                try coordinator.remove(store)
            }
        }

        // Without the migration options the current model refuses the old store.
        #expect(throws: (any Error).self) {
            _ = try Self.loadStore(at: url, model: current, migrate: false)
        }

        let coordinator = try Self.loadStore(at: url, model: current, migrate: true)
        let context = NSManagedObjectContext(.privateQueue)
        context.persistentStoreCoordinator = coordinator
        try context.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: "RPGMap")
            let maps = try context.fetch(request)
            #expect(maps.count == 1)
            let map = try #require(maps.first)
            #expect(map.value(forKey: "uuid") as? UUID == mapId)
            #expect(map.value(forKey: "name") as? String == "Old map")
            #expect(map.value(forKey: "width") as? Double == 640)
            #expect(map.value(forKey: "degrees") == nil, "an old row has no recorded rotation")

            map.setValue(NSNumber(value: 90), forKey: "degrees")
            try context.save()
            context.refreshAllObjects()
            #expect((try context.fetch(request).first?.value(forKey: "degrees") as? NSNumber)?.doubleValue == 90)
        }
    }
}
#endif
