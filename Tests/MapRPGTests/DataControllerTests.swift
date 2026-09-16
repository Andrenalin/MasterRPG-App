// @copyright André Trettin

#if canImport(Testing)
import CoreData
import CoreGraphics
import CoreRPG
import Foundation
import SwiftUI
import Testing

@testable import MapRPG

@MainActor
struct DataControllerTests {
    @Test func replaceFetchUpdateAndDelete() async throws {
        let store = try PersistentTestStore(bundles: [
            CoreRPG.Resources.bundle,
            MapRPG.Resources.bundle
        ])
        let sut = DataController(context: store.context, token: NetworkModules.map.token)
        let pinEntity = try #require(store.container.managedObjectModel.entitiesByName["RPGMapPin"])
        let deadAttribute = try #require(pinEntity.attributesByName["isDead"])
        let characterAttribute = try #require(pinEntity.attributesByName["characterId"])
        let healthPercentAttribute = try #require(pinEntity.attributesByName["healthPercent"])
        let mapEntity = try #require(store.container.managedObjectModel.entitiesByName["RPGMap"])
        let wallsDataAttribute = try #require(mapEntity.attributesByName["wallsData"])
        #expect(!deadAttribute.isOptional)
        #expect((deadAttribute.defaultValue as? NSNumber)?.boolValue == false)
        #expect(characterAttribute.isOptional)
        // Optional with no default, so unset pins (and pre-migration rows)
        // decode back as `nil` — the "health unknown" grey border.
        #expect(healthPercentAttribute.isOptional)
        #expect(healthPercentAttribute.defaultValue == nil)
        #expect(!wallsDataAttribute.isOptional)
        #expect(wallsDataAttribute.defaultValue as? String == "")

        let itemId = UUID()
        let parentId = UUID()
        let photoId = UUID()
        let characterId = UUID()
        let firstEntry = MapEntryModel(
            id: UUID(),
            name: "Hall",
            content: "A bright hall",
            coordinates: [CGPoint(x: 1, y: 2), CGPoint(x: 3, y: 4)],
            isHexGrid: true,
            isShown: true
        )
        let secondEntry = MapEntryModel(
            id: UUID(),
            name: "Vault",
            content: "Locked door",
            coordinates: [CGPoint(x: 5, y: 6), CGPoint(x: 7, y: 8)],
            isHexGrid: false,
            isShown: false
        )
        let displayConfig = DisplayConfigModel(
            id: UUID(),
            tileCoordinates: [CGPoint(x: 9, y: 10), CGPoint(x: 11, y: 12)],
            color: .black,
            border: DisplayBorderViewModel(id: UUID(), thickness: 3, color: .red)
        )
        let firstPin = MapPinModel(
            id: UUID(),
            name: "Start",
            photoId: UUID(),
            characterId: characterId,
            location: CGPoint(x: 13, y: 14),
            size: .large,
            isShown: true,
            isDead: true,
            isHighlighted: true,
            healthPercent: 42.5
        )
        let secondPin = MapPinModel(
            id: UUID(),
            name: "Exit",
            photoId: UUID(),
            location: CGPoint(x: 15, y: 16),
            size: .small,
            isShown: false
        )
        let firstWall = MapWallModel(
            sourceIdentifier: "world:crypt:scene:entry:wall:first",
            start: CGPoint(x: 17, y: 18),
            end: CGPoint(x: 19, y: 20),
            movementRestriction: .normal,
            sightRestriction: .limited,
            doorType: .secret,
            doorState: .locked,
            minimumElevation: -5,
            maximumElevation: 15,
            levelIdentifier: "crypt",
            rawMetadata: .object(["sound": .integer(20)])
        )
        let original = MapModel(
            id: itemId,
            name: "Dungeon",
            description: "Original map",
            tags: ["map", "dungeon"],
            category: .dungeon,
            displayState: 2,
            entries: [firstEntry, secondEntry],
            displayConfig: displayConfig,
            photoId: photoId,
            width: 600,
            height: 400,
            mapPins: [firstPin, secondPin],
            walls: [firstWall],
            pinScale: 2,
            hexMapScale: 25,
            parentId: parentId
        )

        try sut.replaceSync(id: itemId, with: original)
        try await sut.save()

        let fetchedOriginal = try #require(try await sut.fetch(id: itemId) as? MapModel)
        #expect(fetchedOriginal.name == "Dungeon")
        #expect(fetchedOriginal.description == "Original map")
        #expect(fetchedOriginal.tags == ["map", "dungeon"])
        #expect(fetchedOriginal.category == .dungeon)
        #expect(fetchedOriginal.displayState == 2)
        #expect(fetchedOriginal.entries.map(\.id) == [firstEntry.id, secondEntry.id])
        #expect(fetchedOriginal.entries.first?.coordinates == firstEntry.coordinates)
        #expect(fetchedOriginal.entries.first?.isHexGrid == true)
        #expect(fetchedOriginal.entries.first?.isShown == true)
        #expect(fetchedOriginal.displayConfig.tileCoordinates == displayConfig.tileCoordinates)
        #expect(fetchedOriginal.displayConfig.borderThickness == 3)
        #expect(fetchedOriginal.photoId == photoId)
        #expect(fetchedOriginal.width == 600)
        #expect(fetchedOriginal.height == 400)
        #expect(fetchedOriginal.mapPins.map(\.id) == [firstPin.id, secondPin.id])
        #expect(fetchedOriginal.mapPins.first?.location == firstPin.location)
        #expect(fetchedOriginal.mapPins.first?.size == .large)
        #expect(fetchedOriginal.mapPins.first?.photoId == firstPin.photoId)
        #expect(fetchedOriginal.mapPins.first?.characterId == characterId)
        #expect(fetchedOriginal.mapPins.first?.isShown == true)
        #expect(fetchedOriginal.mapPins.first?.isDead == true)
        #expect(fetchedOriginal.mapPins.first?.isHighlighted == false)
        // healthPercent is game-session-only data — it's never persisted to
        // CoreData (deliberately scrubbed on save, never restored on load),
        // regardless of what was set on the domain model before saving.
        #expect(fetchedOriginal.mapPins.first?.healthPercent == nil)
        #expect(fetchedOriginal.mapPins.last?.healthPercent == nil)
        #expect(fetchedOriginal.walls == [firstWall])
        #expect(fetchedOriginal.pinScale == 2)
        #expect(fetchedOriginal.hexMapScale == 25)
        #expect(fetchedOriginal.parentId == parentId)

        let updatedEntry = MapEntryModel(
            id: secondEntry.id,
            name: "Vault Revised",
            content: "Unlocked door",
            coordinates: [CGPoint(x: 20, y: 21)],
            isHexGrid: false,
            isShown: true
        )
        let updatedDisplayConfig = DisplayConfigModel(
            id: displayConfig.id,
            tileCoordinates: [CGPoint(x: 22, y: 23)],
            color: .black,
            border: DisplayBorderViewModel(id: UUID(), thickness: 6, color: .red)
        )
        let updatedPin = MapPinModel(
            id: secondPin.id,
            name: "Exit Revised",
            photoId: nil,
            location: CGPoint(x: 24, y: 25),
            size: .huge,
            isShown: true,
            isDead: false,
            healthPercent: 12
        )
        let updatedWall = MapWallModel(
            sourceIdentifier: firstWall.sourceIdentifier,
            start: CGPoint(x: 26, y: 27),
            end: CGPoint(x: 28, y: 29),
            movementRestriction: .none,
            sightRestriction: .distance,
            doorType: .door,
            doorState: .open
        )
        let updated = MapModel(
            id: itemId,
            name: "Dungeon Revised",
            description: "Updated map",
            tags: ["map"],
            category: .building,
            displayState: 4,
            entries: [updatedEntry],
            displayConfig: updatedDisplayConfig,
            photoId: nil,
            width: 300,
            height: 200,
            mapPins: [updatedPin],
            walls: [updatedWall],
            pinScale: 1.5,
            hexMapScale: 10,
            parentId: nil
        )

        try await sut.replace(id: itemId, with: updated)
        try await sut.save()

        let fetchedUpdated = try #require(try await sut.fetch(id: itemId) as? MapModel)
        #expect(fetchedUpdated.name == "Dungeon Revised")
        #expect(fetchedUpdated.description == "Updated map")
        #expect(fetchedUpdated.tags == ["map"])
        #expect(fetchedUpdated.category == .building)
        #expect(fetchedUpdated.displayState == 4)
        #expect(fetchedUpdated.entries.map(\.id) == [updatedEntry.id])
        #expect(fetchedUpdated.entries.first?.name == "Vault Revised")
        #expect(fetchedUpdated.entries.first?.coordinates == updatedEntry.coordinates)
        #expect(fetchedUpdated.entries.first?.isShown == true)
        #expect(fetchedUpdated.displayConfig.tileCoordinates == updatedDisplayConfig.tileCoordinates)
        #expect(fetchedUpdated.displayConfig.borderThickness == 6)
        #expect(fetchedUpdated.photoId == nil)
        #expect(fetchedUpdated.width == 300)
        #expect(fetchedUpdated.height == 200)
        #expect(fetchedUpdated.mapPins.map(\.id) == [updatedPin.id])
        #expect(fetchedUpdated.mapPins.first?.name == "Exit Revised")
        #expect(fetchedUpdated.mapPins.first?.location == updatedPin.location)
        #expect(fetchedUpdated.mapPins.first?.size == .huge)
        #expect(fetchedUpdated.mapPins.first?.isShown == true)
        #expect(fetchedUpdated.mapPins.first?.isDead == false)
        #expect(fetchedUpdated.mapPins.first?.characterId == nil)
        // Same as above — `updatedPin.healthPercent = 12` on the domain
        // model must never survive the CoreData round trip.
        #expect(fetchedUpdated.mapPins.first?.healthPercent == nil)
        #expect(fetchedUpdated.walls == [updatedWall])
        #expect(fetchedUpdated.pinScale == 1.5)
        #expect(fetchedUpdated.hexMapScale == 10)
        #expect(fetchedUpdated.parentId == nil)

        #expect(Set(try await sut.fetchIds()) == Set([itemId]))
        #expect(try await sut.fetchAll().count == 1)

        try await sut.delete(id: itemId)
        try await sut.save()

        let deleted = try await sut.fetch(id: itemId)
        #expect(deleted == nil)
        #expect(try await sut.fetchIds().isEmpty)
    }

    @Test func mapDataControllerCreatesTrimmedMap() async throws {
        let store = try PersistentTestStore(bundles: [
            CoreRPG.Resources.bundle,
            MapRPG.Resources.bundle
        ])
        let photoId = UUID()
        let sut = MapDataController()

        await sut.addNewMap(
            context: store.context,
            name: "  Cellar  ",
            text: "  Hidden stairs  ",
            photoId: photoId
        )

        let dataController = DataController(context: store.context, token: NetworkModules.map.token)
        let models = try await dataController.fetch()
        let model = try #require(models.first)

        #expect(model.name == "Cellar")
        #expect(model.description == "Hidden stairs")
        #expect(model.category == .entry)
        #expect(model.photoId == photoId)
        #expect(model.walls.isEmpty)
    }
}

private struct PersistentTestStore {
    let container: NSPersistentContainer
    let context: NSManagedObjectContext

    @MainActor
    init(bundles: [Bundle]) throws {
        let model = try #require(NSManagedObjectModel.mergedModel(from: bundles))
        container = NSPersistentContainer(name: "DataControllerTests-\(UUID().uuidString)", managedObjectModel: model)

        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]

        var loadError: (any Error)?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        if let loadError {
            throw loadError
        }

        context = container.newBackgroundContext()
    }
}
#endif
