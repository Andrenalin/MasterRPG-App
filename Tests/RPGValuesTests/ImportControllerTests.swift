// @copyright André Trettin

import AndrenalinKit
import Foundation
import RPGDie
import RPGPdfs
import PhotoRPG
import RPGTables
import RPGResourcesDebug
import Testing

@testable import RPGValues

struct ImportControllerTests {
    @Test func importing() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        
        let sut = root.importController

        let bundle = ResourcesDebug.bundle
        let url = bundle.url(forResource: ResourcesDebug.valueTestData, withExtension: "gmz").unsafelyUnwrapped

        let task = sut.importUrl(from: url)
        let _ = try await task.value
        #expect(await root.itemController.itemDataModel.items.count == 15)
    }
}
