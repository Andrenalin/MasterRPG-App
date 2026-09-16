// @copyright André Trettin

#if canImport(Testing)
import CoreData
import CoreRPG
import Foundation
import Testing

@testable import WeatherRPG

@MainActor
struct DataControllerTests {
    @Test func replaceFetchUpdateAndDelete() async throws {
        let store = try PersistentTestStore(bundles: [
            CoreRPG.Resources.bundle,
            WeatherRPG.Resources.bundle
        ])
        let sut = DataController(context: store.context, token: NetworkModules.weather.token)

        let itemId = UUID()
        let parentId = UUID()
        let photoId = UUID()
        let firstEntry = ChildEntryModel(id: UUID(), childId: UUID())
        let secondEntry = ChildEntryModel(id: UUID(), childId: UUID())
        let weatherUpdate = UUID()
        let original = WeatherModel(
            id: itemId,
            name: "Storm",
            description: "Original weather",
            tags: ["rain", "night"],
            category: .scenario,
            displayState: 6,
            weatherUpdate: weatherUpdate,
            time: 3600,
            cloudThickness: .ultra,
            stormType: .rain,
            rainAngle: 90,
            rainIntensity: 500,
            lightningFrequency: 60,
            lightningMaxBolts: 120,
            lightningForkProbability: 80,
            photoId: photoId,
            entries: [firstEntry, secondEntry],
            parentId: parentId
        )

        try sut.replaceSync(id: itemId, with: original)
        try await sut.save()

        let fetchedOriginal = try #require(try await sut.fetch(id: itemId) as? WeatherModel)
        #expect(fetchedOriginal.name == "Storm")
        #expect(fetchedOriginal.description == "Original weather")
        #expect(fetchedOriginal.tags == ["rain", "night"])
        #expect(fetchedOriginal.category == .scenario)
        #expect(fetchedOriginal.displayState == 6)
        #expect(fetchedOriginal.time == 3600)
        #expect(fetchedOriginal.cloudThickness == .ultra)
        #expect(fetchedOriginal.stormType == .rain)
        #expect(fetchedOriginal.rainAngle == 90)
        #expect(fetchedOriginal.rainIntensity == 500)
        #expect(fetchedOriginal.lightningFrequency == 60)
        #expect(fetchedOriginal.lightningMaxBolts == 120)
        #expect(fetchedOriginal.lightningForkProbability == 80)
        #expect(fetchedOriginal.photoId == photoId)
        #expect(fetchedOriginal.parentId == parentId)
        #expect(fetchedOriginal.entries.map(\.id) == [firstEntry.id, secondEntry.id])
        #expect(fetchedOriginal.entries.map(\.childId) == [firstEntry.childId, secondEntry.childId])

        let updatedEntry = ChildEntryModel(id: secondEntry.id, childId: UUID())
        let updated = WeatherModel(
            id: itemId,
            name: "Clear",
            description: "Updated weather",
            tags: ["day"],
            category: .scenario,
            displayState: 8,
            weatherUpdate: UUID(),
            time: 7200,
            cloudThickness: .thin,
            stormType: .none,
            rainAngle: 0,
            rainIntensity: 0,
            lightningFrequency: 0,
            lightningMaxBolts: 0,
            lightningForkProbability: 0,
            photoId: nil,
            entries: [updatedEntry],
            parentId: nil
        )

        try await sut.replace(id: itemId, with: updated)
        try await sut.save()

        let fetchedUpdated = try #require(try await sut.fetch(id: itemId) as? WeatherModel)
        #expect(fetchedUpdated.name == "Clear")
        #expect(fetchedUpdated.description == "Updated weather")
        #expect(fetchedUpdated.tags == ["day"])
        #expect(fetchedUpdated.displayState == 8)
        #expect(fetchedUpdated.time == 7200)
        #expect(fetchedUpdated.cloudThickness == .thin)
        #expect(fetchedUpdated.stormType == .none)
        #expect(fetchedUpdated.rainIntensity == 0)
        #expect(fetchedUpdated.photoId == nil)
        #expect(fetchedUpdated.parentId == nil)
        #expect(fetchedUpdated.entries.map(\.id) == [updatedEntry.id])
        #expect(fetchedUpdated.entries.first?.childId == updatedEntry.childId)

        #expect(Set(try await sut.fetchIds()) == Set([itemId]))
        #expect(try await sut.fetchAll().count == 1)

        try await sut.delete(id: itemId)
        try await sut.save()

        let deleted = try await sut.fetch(id: itemId)
        #expect(deleted == nil)
        #expect(try await sut.fetchIds().isEmpty)
    }

    @Test func weatherDataControllerCreatesTrimmedWeather() async throws {
        let store = try PersistentTestStore(bundles: [
            CoreRPG.Resources.bundle,
            WeatherRPG.Resources.bundle
        ])
        let photoId = UUID()
        let sut = WeatherDataController()

        await sut.addNewWeather(
            context: store.context,
            name: "  Fog  ",
            text: "  Morning blanket  ",
            photoId: photoId
        )

        let dataController = DataController(context: store.context, token: NetworkModules.weather.token)
        let models = try await dataController.fetch()
        let model = try #require(models.first)

        #expect(model.name == "Fog")
        #expect(model.description == "Morning blanket")
        #expect(model.category == .entry)
        #expect(model.photoId == photoId)
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
