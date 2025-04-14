// @copyright André Trettin

#if canImport(Testing)
import AndrenalinKit
@testable import RPGAdventures
import RPGDie
import Foundation
import RPGAudios
import RPGMaps
import RPGPdfs
import RPGPhotos
import RPGResources
import RPGResourcesDebug
import RPGSpaces
import RPGTables
import RPGValues
import RPGWeathers

import Testing

struct MockRoot {
    static func importTestData(_ name: String = ResourcesDebug.adventureTestData, itemCounter: Int = 3) async throws -> AdventureRoot {
        let audioRoot = await AudioRoot.testRoot()
        let diceRoot = await DiceRoot.testRoot()
        let pdfRoot = await PdfRoot.testRoot()
        let photoRoot = await PhotoRoot.testRoot()
        let spaceRoot = await SpaceRoot.testRoot()
        let weatherRoot = await WeatherRoot.testRoot(photoRoot: photoRoot)
        let tableRoot = await TableRoot.testRoot(diceRoot: diceRoot, pdfRoot: pdfRoot)
        let valueRoot = await ValueRoot.testRoot(diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot)
        let mapRoot = await MapRoot.testRoot(audioRoot: audioRoot, diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot, valueRoot: valueRoot)
        let root = await AdventureRoot.testRoot(audioRoot: audioRoot, diceRoot: diceRoot, mapRoot: mapRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, spaceRoot: spaceRoot, tableRoot: tableRoot, valueRoot: valueRoot, weatherRoot: weatherRoot)

        await root.itemController.resetData()

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
        let task6 = root.valueRoot.importControllable.importUrl(from: url)
        let _ = try await task6.value
        let task10 = root.mapRoot.importControllable.importUrl(from: url)
        let _ = try await task10.value

        let task = root.importController.importUrl(from: url)
        let _ = try await task.value
        await #expect(root.itemController.itemDataModel.items.count == itemCounter)
        
        return root
    }
    
    static func resetTestData(for root: AdventureRoot) async throws {
        await root.resetData()
    }
}
#endif
