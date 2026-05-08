// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing
@testable import PhotoRPG

@testable import WeatherRPG

@MainActor
struct SheetControllerTests {
    @Test func weatherSheetBasic() async throws {
        let photoRoot = PhotoRootModel.testRoot()
        let root = WeatherRootModel.testRoot(photoRoot: photoRoot)

        let sut = SheetController(itemController: root.itemController)

        let itemId = Foundation.UUID()
        let weatherModel = WeatherModel(
            id: itemId,
            name: "Test Weather",
            description: "Sunny",
            tags: [],
            category: .scenario,
            displayState: 0,
            weatherUpdate: Foundation.UUID(),
            time: 12.0,
            cloudThickness: .none,
            stormType: .none,
            rainAngle: 0,
            rainIntensity: 0,
            lightningFrequency: 0,
            lightningMaxBolts: 0,
            lightningForkProbability: 0,
            photoId: nil
        )
        root.itemController.itemDataModel.itemData[itemId] = weatherModel

        let model = sut.sheet(root: RootManager(anyRoot: root), itemId: itemId, destination: nil, level: 0, isShown: true, isEditor: false)

        #expect(model.name == "Test Weather")
        #expect(model.description == "Sunny")
        #expect(model.isShown == true)
        #expect(model.level == 0)
        #expect(model.sheetType == SheetModelType.weather)
        #expect(model.source.itemId == itemId)
        #expect(model.source.typeId == NetworkModules.weather)
    }

    @Test func weatherSheetWithDestination() async throws {
        let photoRoot = PhotoRootModel.testRoot()
        let root = WeatherRootModel.testRoot(photoRoot: photoRoot)

        let sut = SheetController(itemController: root.itemController)

        let itemId = Foundation.UUID()
        let weatherModel = WeatherModel(
            id: itemId,
            name: "Test",
            description: "",
            tags: [],
            category: .scenario,
            displayState: 0,
            weatherUpdate: Foundation.UUID(),
            time: 12.0,
            cloudThickness: .none,
            stormType: .none,
            rainAngle: 0,
            rainIntensity: 0,
            lightningFrequency: 0,
            lightningMaxBolts: 0,
            lightningForkProbability: 0,
            photoId: nil
        )
        root.itemController.itemDataModel.itemData[itemId] = weatherModel

        let destination = ItemRowModel(itemId: Foundation.UUID(), typeId: NetworkModules.adventure)
        let model = sut.sheet(root: RootManager(anyRoot: root), itemId: itemId, destination: destination, level: 1, isShown: false, isEditor: false)

        #expect(model.destination.itemId == destination.itemId)
        #expect(model.level == 1)
        #expect(model.isShown == false)
    }

    @Test func weatherSheetNoEntries() async throws {
        let photoRoot = PhotoRootModel.testRoot()
        let root = WeatherRootModel.testRoot(photoRoot: photoRoot)

        let sut = SheetController(itemController: root.itemController)

        let itemId = Foundation.UUID()
        let weatherModel = WeatherModel(
            id: itemId,
            name: "Test",
            description: "",
            tags: [],
            category: .scenario,
            displayState: 0,
            weatherUpdate: Foundation.UUID(),
            time: 12.0,
            cloudThickness: .none,
            stormType: .none,
            rainAngle: 0,
            rainIntensity: 0,
            lightningFrequency: 0,
            lightningMaxBolts: 0,
            lightningForkProbability: 0,
            photoId: nil
        )
        root.itemController.itemDataModel.itemData[itemId] = weatherModel

        let model = sut.sheet(root: RootManager(anyRoot: root), itemId: itemId, destination: nil, level: 0, isShown: true, isEditor: false)

        // Weather sheets have inline weather widget but no sub-entries
        #expect(model.entries.isEmpty)
        #expect(model.inlineEntries.count == 1)
        #expect(model.inlineEntries.first?.sheetType == SheetModelType.weather)
    }
}
#endif
