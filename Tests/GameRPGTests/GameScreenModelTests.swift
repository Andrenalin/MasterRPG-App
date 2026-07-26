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

    @Test("Battle, primary, and settings content share one exclusive sidebar slot")
    func battleSidebarIsMutuallyExclusive() {
        let model = GameScreenModel()

        model.showMainTab = .game
        model.showSettingTab = .setting
        #expect(model.showMainTab == .none)
        #expect(model.showSettingTab == .setting)

        model.toggleBattleRoundSidebar()
        #expect(model.showsBattleRoundSidebar)
        #expect(model.showMainTab == .none)
        #expect(model.showSettingTab == .none)
        #expect(model.isInlineSidebarVisible)

        model.showMainTab = .game
        #expect(!model.showsBattleRoundSidebar)
        #expect(model.showMainTab == .game)
        #expect(model.showSettingTab == .none)

        model.showsBattleRoundSidebar = true
        model.showSettingTab = .setting
        #expect(!model.showsBattleRoundSidebar)
        #expect(model.showMainTab == .none)
        #expect(model.showSettingTab == .setting)
    }

    @Test("Battle sidebar toggles closed and the shared hide action clears every presentation")
    func battleSidebarToggleAndHide() {
        let model = GameScreenModel()

        model.toggleBattleRoundSidebar()
        #expect(model.showsBattleRoundSidebar)

        model.toggleBattleRoundSidebar()
        #expect(!model.showsBattleRoundSidebar)
        #expect(!model.isInlineSidebarVisible)

        model.showMainTab = .game
        model.hideInlineSidebar()
        #expect(model.showMainTab == .none)
        #expect(model.showSettingTab == .none)
        #expect(!model.showsBattleRoundSidebar)
        #expect(!model.isInlineSidebarVisible)
    }

    @Test("Battle overlay reserves the same measured map width as primary content")
    func battleSidebarMapViewportReservation() {
        let model = GameScreenModel()
        model.updateInlineMainOverlayWidth(360)

        model.showsBattleRoundSidebar = true

        #expect(
            model.mapTrailingViewportReservation
                == 360 + GameScreenModel.mapOverlaySpacing
        )

        model.hideInlineSidebar()
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
