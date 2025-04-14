// @copyright André Trettin

import AndrenalinKit
import Foundation
import RPGResources
import RPGResourcesDebug
import Testing

@testable import RPGAudios

struct MockRoot {
    static func importTestData(_ name: String = ResourcesDebug.audioTestData, itemCounter: Int = 2) async throws -> AudioRoot {
        let root = await AudioRoot.testRoot()

        try await resetTestData(for: root)

        let bundle = ResourcesDebug.bundle
        let url = bundle.url(forResource: name, withExtension: "gmz").unsafelyUnwrapped
        let task = root.importController.importUrl(from: url)
        let _ = try await task.value
        await #expect(root.itemController.itemDataModel.items.count == itemCounter)
        
        return root
    }
    
    static func resetTestData(for root: AudioRoot) async throws {
        await root.itemController.resetData()
    }
}
