// @copyright André Trettin

import AndrenalinKit
@testable import DiceRPG
import Foundation
@testable import PdfRPG
import RPGResources
import RPGResourcesDebug
@testable import RPGTables

import Testing

struct MockRoot {
    static func importTestData(_ name: String = ResourcesDebug.tableTestData, itemCounter: Int = 16) async throws -> TableRootModel {
        let diceRoot = await DiceRootModel.testRoot()
        let pdfRoot = await PdfRootModel.testRoot()
        let root = await TableRootModel.testRoot(diceRoot: diceRoot, pdfRoot: pdfRoot)

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

        return root
    }
    
    static func resetTestData(for root: TableRootModel) async throws {
        await root.itemController.resetData()
        await root.diceRoot.itemControllable.resetData()
        await root.pdfRoot.itemControllable.resetData()
    }
}
