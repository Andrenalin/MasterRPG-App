// @copyright André Trettin

import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import PhotoRPG
@testable import WeatherRPG

@Suite("Weather edit controller — slider values")
@MainActor
struct WeatherEditControllerTests {
    /// The time, rain intensity and rain angle sliders write a draft and hand the final value to
    /// the edit controller when the drag ends. See CODE_AUDIT_26 §5.7, §5.8.
    @Test("time, rain and lightning values are saved through the edit controller")
    func sliderValuesAreSaved() async throws {
        let root = WeatherRootModel.testRoot(photoRoot: PhotoFactory.root(tagController: .preview))
        let weatherId = await root.itemController.addNew(type: .scenario)
        let sut = root.editController

        sut.reset(time: 0.75, itemId: weatherId)
        sut.reset(rainIntensity: 640, itemId: weatherId)
        sut.reset(rainAngle: -30, itemId: weatherId)
        sut.reset(lightningMaxBolts: 3, itemId: weatherId)
        // A change of less than one unit still counts: the editor no longer filters the save.
        sut.reset(lightningFrequency: 0.4, itemId: weatherId)

        let saved = try #require(root.itemController.itemSync(for: weatherId))
        #expect(saved.time == 0.75)
        #expect(saved.rainIntensity == 640)
        #expect(saved.rainAngle == -30)
        #expect(saved.lightningMaxBolts == 3)
        #expect(saved.lightningFrequency == 0.4)
    }
}
