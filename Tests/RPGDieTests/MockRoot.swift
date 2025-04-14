// @copyright André Trettin

import AndrenalinKit
import Foundation
import RPGResources
import RPGResourcesDebug
import Testing

@testable import RPGDie

struct MockRoot {
    static func importTestData(_ name: String = ResourcesDebug.diceTestData, itemCounter: Int = 5) async throws -> DiceRoot {
        let root = await DiceRoot.testRoot()

        try await resetTestData(for: root)

        let bundle = ResourcesDebug.bundle
        let url = bundle.url(forResource: name, withExtension: "gmz").unsafelyUnwrapped
        let task = root.importController.importUrl(from: url)
        let _ = try await task.value
        await #expect(root.itemController.itemDataModel.items.count == itemCounter)
        
        return root
    }
    
    static func resetTestData(for root: DiceRoot) async throws {
        await root.itemController.resetData()
    }
}
