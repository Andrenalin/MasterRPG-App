// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
@testable import AdventureRPG
import DiceRPG
import Foundation
import AudioRPG
import MapRPG
import PdfRPG
import PhotoRPG
import RPGResources
import RPGResourcesDebug
import SpaceRPG
import TableRPG
import CharacterRPG
import WeatherRPG

import Testing

struct MockRoot {
    static func importTestData(_ name: String = ResourcesDebug.adventureTestData, itemCounter: Int = 3) async throws -> AdventureRootModel {
        let audioRoot = await AudioRootModel.testRoot()
        let diceRoot = await DiceRootModel.testRoot()
        let pdfRoot = await PdfRootModel.testRoot()
        let photoRoot = await PhotoRootModel.testRoot()
        let spaceRoot = await SpaceRootModel.testRoot()
        let weatherRoot = await WeatherRootModel.testRoot(photoRoot: photoRoot)
        let tableRoot = await TableRootModel.testRoot(diceRoot: diceRoot, pdfRoot: pdfRoot)
        let characterRoot = await CharacterRootModel.testRoot(diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot)
        let mapRoot = await MapRootModel.testRoot(audioRoot: audioRoot, diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot, characterRoot: characterRoot)
        let root = await AdventureRootModel.testRoot(audioRoot: audioRoot, diceRoot: diceRoot, mapRoot: mapRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, spaceRoot: spaceRoot, tableRoot: tableRoot, characterRoot: characterRoot, weatherRoot: weatherRoot)
        
        await root.itemController.resetData()
        
        await root.setUp(root: RootManager(adventureRoot: root, audioRoot: audioRoot, characterRoot: characterRoot, diceRoot: diceRoot, generatorRoot: root, mapRoot: mapRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, spaceRoot: spaceRoot, tableRoot: tableRoot, weatherRoot: weatherRoot), context: nil)

        let bundle = ResourcesDebug.bundle
        let url = bundle.url(forResource: name, withExtension: "gmz").unsafelyUnwrapped

        let task7 = root.audioRoot.importControllable.importUrl(from: url)
        let _ = try await task7.value
        let task3 = root.diceRoot.importControllable.importUrl(from: url)
        let _ = try await task3.value
        let task2 = root.pdfRoot.importControllable.importUrl(from: url)
        let _ = try await task2.value
        let task4 = root.photoRoot.importControllable.importUrl(from: url)
        let _ = try await task4.value
        let task9 = root.spaceRoot.importControllable.importUrl(from: url)
        let _ = try await task9.value
        let task8 = root.weatherRoot.importControllable.importUrl(from: url)
        let _ = try await task8.value
        let task5 = root.tableRoot.importControllable.importUrl(from: url)
        let _ = try await task5.value
        let task6 = root.characterRoot.importControllable.importUrl(from: url)
        let _ = try await task6.value
        let task10 = root.mapRoot.importControllable.importUrl(from: url)
        let _ = try await task10.value

        let task = root.importController.importUrl(from: url)
        let _ = try await task.value
        await #expect(root.itemController.itemDataModel.items.count == itemCounter)
        
        return root
    }
    
    static func resetTestData(for root: AdventureRootModel) async throws {
        await root.resetData()
    }
}
#endif
