// @copyright André Trettin

#if canImport(Testing)
import AndrenalinKit
@testable import RPGDie
import Foundation
@testable import PdfRPG
@testable import PhotoRPG
import RPGResources
import RPGResourcesDebug
@testable import RPGTables
@testable import RPGValues

import Testing

struct MockRoot {
    static func importTestData(_ name: String = ResourcesDebug.valueTestData, itemCounter: Int = 15) async throws -> CharacterRootModel {
        let diceRoot = await DiceRootModel.testRoot()
        let pdfRoot = await PdfRootModel.testRoot()
        let photoRoot = await PhotoRootModel.testRoot()
        let tableRoot = await TableRootModel.testRoot(diceRoot: diceRoot, pdfRoot: pdfRoot)
        let root = await CharacterRootModel.testRoot(diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot)
        
        try await resetTestData(for: root)

        let bundle = ResourcesDebug.bundle
        let url = bundle.url(forResource: name, withExtension: "gmz").unsafelyUnwrapped

        let task2 = root.pdfRoot.importControllable.importUrl(from: url)
        let _ = try await task2.value
        let task3 = root.diceRoot.importControllable.importUrl(from: url)
        let _ = try await task3.value
        let task4 = root.photoRoot.importControllable.importUrl(from: url)
        let _ = try await task4.value
        let task5 = root.tableRoot.importControllable.importUrl(from: url)
        let _ = try await task5.value


        let task = root.importController.importUrl(from: url)
        let _ = try await task.value
        await #expect(root.itemController.itemDataModel.items.count == itemCounter)
        
        return root
    }
    
    static func resetTestData(for root: CharacterRootModel) async throws {
        await root.itemController.resetData()
        await root.diceRoot.itemControllable.resetData()
        await root.pdfRoot.itemControllable.resetData()
        await root.photoRoot.itemControllable.resetData()
        await root.tableRoot.itemControllable.resetData()
    }
}
#endif
