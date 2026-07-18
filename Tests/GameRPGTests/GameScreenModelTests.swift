// @copyright André Trettin

#if canImport(Testing)
import CoreGraphics
import CoreRPG
import Testing

@testable import GameRPG

@MainActor
@Suite("Game screen map layout")
struct GameScreenModelTests {
    @Test("Sidebar visibility remains independent overlay state")
    func sidebarVisibilityState() {
        let model = GameScreenModel()

        #expect(!model.isInlineSidebarVisible)

        model.showMainTab = .game
        #expect(model.isInlineSidebarVisible)

        model.showMainTab = .none
        model.showSettingTab = .setting
        #expect(model.isInlineSidebarVisible)
    }

    @Test("Changing sidebar width mutates only sidebar presentation state")
    func sidebarWidthState() {
        let model = GameScreenModel()
        let compactWidth = model.sideBarWidth

        model.toggleSideBarWidth()

        #expect(model.sideBarWidth > compactWidth)
    }

    @Test("Visible main overlay reserves its measured width plus map spacing")
    func mapViewportReservationTracksMainOverlay() {
        let model = GameScreenModel()
        model.updateInlineMainOverlayWidth(320)

        #expect(model.mapTrailingViewportReservation == 0)

        model.showMainTab = .game
        #expect(
            model.mapTrailingViewportReservation
                == 320 + GameScreenModel.mapOverlaySpacing
        )

        model.showSettingTab = .setting
        model.showMainTab = .none
        #expect(model.isInlineSidebarVisible)
        #expect(model.mapTrailingViewportReservation == 0)
    }

    @Test("Invalid overlay widths cannot corrupt map geometry")
    func mapViewportReservationRejectsInvalidWidth() {
        let model = GameScreenModel()
        model.showMainTab = .value
        model.updateInlineMainOverlayWidth(.infinity)

        #expect(model.mapTrailingViewportReservation == 0)
    }

    @Test("3D table remains local to the main game display")
    func inlineTableSupportExcludesExternalPlayerDisplay() {
        #expect(GameMapContentType.master.supportsInlineThreeDTable)
        #expect(GameMapContentType.player.supportsInlineThreeDTable)
        #expect(!GameMapContentType.externalPlayer.supportsInlineThreeDTable)
    }
}
#endif
