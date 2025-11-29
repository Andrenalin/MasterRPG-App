// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
@testable import DiceRPG
import Foundation
@testable import AudioRPG
@testable import MapRPG
@testable import PdfRPG
@testable import PhotoRPG
import RPGResources
import RPGResourcesDebug
@testable import TableRPG
@testable import CharacterRPG

import Testing

struct MockRoot {
    static func importTestData(_ name: String = ResourcesDebug.mapTestData, itemCounter: Int = 1) async throws -> MapRootModel {
        let audioRoot = await AudioRootModel.testRoot()
        let diceRoot = await DiceRootModel.testRoot()
        let pdfRoot = await PdfRootModel.testRoot()
        let photoRoot = await PhotoRootModel.testRoot()
        let tableRoot = await TableRootModel.testRoot(diceRoot: diceRoot, pdfRoot: pdfRoot)
        let characterRoot = await CharacterRootModel.testRoot(diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot)
        let root = await MapRootModel.testRoot(audioRoot: audioRoot, diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot, characterRoot: characterRoot)

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
        let task6 = root.characterRoot.importControllable.importUrl(from: url)
        let _ = try await task6.value
        let task7 = root.audioRoot.importControllable.importUrl(from: url)
        let _ = try await task7.value

        return root
    }
    
    static func resetTestData(for root: MapRootModel) async throws {
        await root.itemController.resetData()
        await root.audioRoot.itemControllable.resetData()
        await root.diceRoot.itemControllable.resetData()
        await root.pdfRoot.itemControllable.resetData()
        await root.photoRoot.itemControllable.resetData()
        await root.tableRoot.itemControllable.resetData()
        await root.characterRoot.itemControllable.resetData()
    }
}
#endif
