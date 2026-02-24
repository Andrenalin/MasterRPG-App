// @copyright André Trettin

import CoreRPG
import Foundation
import RPGResources
import RPGResourcesDebug
import Testing

@testable import SpaceRPG

struct MockRoot {
    static func importTestData(_ name: String = ResourcesDebug.spaceTestData, itemCounter: Int = 1) async throws -> SpaceRootModel {
        let root = await SpaceRootModel.testRoot()

        try await resetTestData(for: root)

        let bundle = ResourcesDebug.bundle
        let url = bundle.url(forResource: name, withExtension: "gmz").unsafelyUnwrapped
        let task = await root.importController.importUrl(from: url)
        let _ = try await task.value
        await #expect(root.itemController.itemDataModel.items.count == itemCounter)
        
        return root
    }
    
    static func resetTestData(for root: SpaceRootModel) async throws {
        await root.itemController.resetData()
    }
}
