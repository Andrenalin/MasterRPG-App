// @copyright André Trettin

#if canImport(Testing)
import AndrenalinKit
@testable import RPGAdventures
import RPGDie
import Foundation
import AudioRPG
@testable import RPGGame
import RPGMaps
import PdfRPG
import PhotoRPG
import RPGResources
import RPGResourcesDebug
import SpaceRPG
import RPGTables
import RPGValues
import WeatherRPG

import Testing

struct MockRoot {
    static func importTestData(into root: AdventureRootModel, name: String = ResourcesDebug.adventureTestData, itemCounter: Int = 3) async throws {

        let bundle = ResourcesDebug.bundle
        let url = bundle.url(forResource: name, withExtension: "gmz").unsafelyUnwrapped
        let task = root.importController.importUrl(from: url)
        let _ = try await task.value
        await #expect(root.itemController.itemDataModel.items.count == itemCounter)
    }
    
    static func resetTestData(for root: AdventureRootModel) async throws {
        await root.resetData()
    }
    
    static func createGameRoot() async throws -> GameRoot {
        let audioRoot = await AudioRootModel.testRoot()
        let diceRoot = await DiceRootModel.testRoot()
        let pdfRoot = await PdfRootModel.testRoot()
        let photoRoot = await PhotoRootModel.testRoot()
        let spaceRoot = await SpaceRootModel.testRoot()
        let weatherRoot = await WeatherRootModel.testRoot(photoRoot: photoRoot)
        let tableRoot = await TableRootModel.testRoot(diceRoot: diceRoot, pdfRoot: pdfRoot)
        let valueRoot = await CharacterRootModel.testRoot(diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot)
        let mapRoot = await MapRootModel.testRoot(audioRoot: audioRoot, diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot, valueRoot: valueRoot)
        let adventureRoot = await AdventureRootModel.testRoot(audioRoot: audioRoot, diceRoot: diceRoot, mapRoot: mapRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, spaceRoot: spaceRoot, tableRoot: tableRoot, valueRoot: valueRoot, weatherRoot: weatherRoot)
        
        return await GameRoot(adventureRoot: adventureRoot, audioRoot: audioRoot, diceRoot: diceRoot, mapRoot: mapRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, spaceRoot: spaceRoot, tableRoot: tableRoot, valueRoot: valueRoot, weatherRoot: weatherRoot)
    }
    
    static func resetGameController(for root: GameRoot) async throws {
        await root.adventureRoot.gameControllable.reset()
        await root.audioRoot.gameControllable.reset()
        await root.diceRoot.gameControllable.reset()
        await root.mapRoot.gameControllable.reset()
        await root.pdfRoot.gameControllable.reset()
        await root.photoRoot.gameControllable.reset()
        await root.spaceRoot.gameControllable.reset()
        await root.tableRoot.gameControllable.reset()
        await root.valueRoot.gameControllable.reset()
        await root.weatherRoot.gameControllable.reset()
    }

}
#endif
