// @copyright André Trettin

import AndrenalinKit
import Foundation
import RPGDie
import RPGAudios
import RPGPdfs
import RPGPhotos
import RPGTables
import RPGValues
import RPGResourcesDebug
import Testing

@testable import RPGMaps

struct ImportControllerTests {
    @Test func importing() async throws {
        let root = try await MockRoot.importTestData()
        await root.itemController.resetData()

        let sut = root.importController

        let bundle = ResourcesDebug.bundle
        let url = bundle.url(forResource: ResourcesDebug.mapTestData, withExtension: "gmz").unsafelyUnwrapped

        let task = sut.importUrl(from: url)
        let _ = try await task.value
        #expect(await root.itemController.itemDataModel.items.count == 1)
    }
}
