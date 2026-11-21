// @copyright André Trettin

#if (os(iOS) || os(macOS)) && canImport(Testing)
@testable import CoreRPG
import Foundation
import Testing

@testable import GameRPG

/// iOS and macOS show the 3D table in place of the 2D map: the controller only flips the
/// setting. The visionOS window handling needs scenes and is not unit-testable.
@MainActor
@Suite("Game table presentation", .serialized)
struct GameTablePresentationControllerTests {
    private func controller() throws -> (GameTablePresentationController, AppSettingsModel) {
        let suite = "GameTablePresentationControllerTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let settings = AppSettingsModel(defaults: defaults)
        let root = GameRoot.previewFixture(game: .master)
        return (GameTablePresentationController(root: root, appSettingsModel: settings), settings)
    }

    @Test("The toggle switches between the 2D map and the 3D table")
    func toggleSwitchesTable() throws {
        let (controller, settings) = try controller()
        #expect(!controller.isPresented)

        controller.toggle()
        #expect(controller.isPresented)
        #expect(settings.showGameTableVolume)

        controller.toggle()
        #expect(!controller.isPresented)
    }
}
#endif
