// @copyright André Trettin

import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import DiceRPG

struct ImportControllerTests {
    @Test func importing() async throws {
        let root = await DiceRootModel.testRoot()
        await root.itemController.resetData()
        
        let sut = root.importController
        
        let bundle = ResourcesDebug.bundle
        let url = bundle.url(forResource: ResourcesDebug.diceTestData, withExtension: "gmz").unsafelyUnwrapped

        let task = sut.importUrl(from: url)
        let _ = try await task.value
        #expect(await root.itemController.itemDataModel.items.count == 5)
    }
}
