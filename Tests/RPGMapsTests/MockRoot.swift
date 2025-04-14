// @copyright André Trettin

#if canImport(Testing)
import AndrenalinKit
@testable import RPGDie
import Foundation
@testable import RPGAudios
@testable import RPGMaps
@testable import RPGPdfs
@testable import RPGPhotos
import RPGResources
import RPGResourcesDebug
@testable import RPGTables
@testable import RPGValues

import Testing

struct MockRoot {
    static func importTestData(_ name: String = ResourcesDebug.mapTestData, itemCounter: Int = 1) async throws -> MapRoot {
        let audioRoot = await AudioRoot.testRoot()
        let diceRoot = await DiceRoot.testRoot()
        let pdfRoot = await PdfRoot.testRoot()
        let photoRoot = await PhotoRoot.testRoot()
        let tableRoot = await TableRoot.testRoot(diceRoot: diceRoot, pdfRoot: pdfRoot)
        let valueRoot = await ValueRoot.testRoot(diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot)
        let root = await MapRoot.testRoot(audioRoot: audioRoot, diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot, valueRoot: valueRoot)

        await root.itemController.resetData()

        let bundle = ResourcesDebug.bundle
        let url = bundle.url(forResource: name, withExtension: "gmz").unsafelyUnwrapped
        let task = root.importController.importUrl(from: url)
        let _ = try await task.value
        await #expect(root.itemController.itemDataModel.items.count == itemCounter)
        
        let task2 = root.pdfRoot.importControllable.importUrl(from: url)
        let _ = try await task2.value
        let task3 = root.diceRoot.importControllable.importUrl(from: url)
        let _ = try await task3.value
        let task4 = root.photoRoot.importControllable.importUrl(from: url)
        let _ = try await task4.value
        let task5 = root.tableRoot.importControllable.importUrl(from: url)
        let _ = try await task5.value
        let task6 = root.valueRoot.importControllable.importUrl(from: url)
        let _ = try await task6.value
        let task7 = root.audioRoot.importControllable.importUrl(from: url)
        let _ = try await task7.value

        return root
    }
    
    static func resetTestData(for root: MapRoot) async throws {
        await root.itemController.resetData()
        await root.audioRoot.itemControllable.resetData()
        await root.diceRoot.itemControllable.resetData()
        await root.pdfRoot.itemControllable.resetData()
        await root.photoRoot.itemControllable.resetData()
        await root.tableRoot.itemControllable.resetData()
        await root.valueRoot.itemControllable.resetData()
    }
}
#endif
