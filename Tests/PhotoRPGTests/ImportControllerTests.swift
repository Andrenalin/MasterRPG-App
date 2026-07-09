// @copyright André Trettin

import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import PhotoRPG

@MainActor
struct ImportControllerTests {
    @Test func importing() async throws {
        let root = PhotoRootModel.testRoot()
        await root.itemController.resetData()

        let sut = root.importController

        let bundle = ResourcesDebug.bundle
        let url = bundle.url(forResource: ResourcesDebug.photoTestData, withExtension: "gmz").unsafelyUnwrapped

        let task = sut.importUrl(from: url)
        let _ = try await task.value
        #expect(root.itemController.itemDataModel.items.count == 3)
    }
}
