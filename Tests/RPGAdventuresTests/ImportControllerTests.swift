// @copyright André Trettin

#if canImport(Testing)
import AndrenalinKit
import Foundation
import DiceRPG
import AudioRPG
import RPGMaps
import PdfRPG
import PhotoRPG
import SpaceRPG
import TableRPG
import CharacterRPG
import RPGResourcesDebug
import Testing
import WeatherRPG

@testable import RPGAdventures

struct ImportControllerTests {
    @Test func importing() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let sut = root.importController

        let bundle = ResourcesDebug.bundle
        let url = bundle.url(forResource: ResourcesDebug.adventureTestData, withExtension: "gmz").unsafelyUnwrapped
        let task = sut.importUrl(from: url)
        let _ = try await task.value
        await #expect(root.itemController.itemDataModel.items.count == 3)
    }
}
#endif
