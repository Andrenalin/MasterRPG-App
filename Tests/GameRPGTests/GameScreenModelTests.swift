// @copyright André Trettin

#if canImport(Testing)
import CoreGraphics
import CoreRPG
import Testing

@testable import GameRPG

@MainActor
@Suite("Game screen map layout")
struct GameScreenModelTests {
    @Test("Map reserves only a visible inline sidebar")
    func mapReservationTracksInlineVisibility() {
        let model = GameScreenModel()

        #expect(model.mapTrailingReservation(usesInlineSidebarLayout: true) == 0)

        model.showMainTab = .game
        #expect(
            model.mapTrailingReservation(usesInlineSidebarLayout: true)
                == model.sideBarWidth + GameScreenModel.mapSidebarSpacing
        )

        #expect(model.mapTrailingReservation(usesInlineSidebarLayout: false) == 0)

        model.showMainTab = .none
        model.showSettingTab = .setting
        #expect(
            model.mapTrailingReservation(usesInlineSidebarLayout: true)
                == model.sideBarWidth + GameScreenModel.mapSidebarSpacing
        )
    }

    @Test("Changing the sidebar width updates the map reservation")
    func mapReservationTracksSidebarWidth() {
        let model = GameScreenModel()
        model.showMainTab = .game
        let compactReservation = model.mapTrailingReservation(usesInlineSidebarLayout: true)

        model.toggleSideBarWidth()

        #expect(model.mapTrailingReservation(usesInlineSidebarLayout: true) > compactReservation)
    }
}
#endif
