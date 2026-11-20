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

    @Test("Sidebar view switches are exclusive and show the sidebar")
    func sidebarViewSwitches() {
        let model = GameScreenModel()

        model.setSidebarPrimaryView(true, primaryModule: .game, allowsPrimaryView: true)
        #expect(model.showMainTab == .game)
        #expect(model.showMainTabIOS)

        model.setSidebarBattleRound(true)
        #expect(model.showsBattleRoundSidebar)
        #expect(model.showMainTab == .none)

        model.setSidebarOtherView(true)
        #expect(model.showSettingTab == .setting)
        #expect(!model.iOSSidebarShowsPrimaryView)

        model.setSidebarOtherView(false)
        model.setSidebarBattleRound(false)
        #expect(!model.isInlineSidebarVisible)
        #expect(!model.showMainTabIOS)
    }

    @Test("An observer cannot switch to the primary view")
    func observerPrimaryViewSwitchIgnored() {
        let model = GameScreenModel()

        model.setSidebarPrimaryView(true, primaryModule: .value, allowsPrimaryView: false)

        #expect(model.showMainTab == .none)
        #expect(!model.showMainTabIOS)
    }

    @Test("Split layouts show the Game View with the Other View or Battle Round")
    func splitLayoutShowsTwoViews() {
        let model = GameScreenModel()
        model.sidebarLayout = .horizontal

        model.setSidebarPrimaryView(true, primaryModule: .game, allowsPrimaryView: true)
        #expect(model.showMainTab == .game)
        #expect(model.showSettingTab == .setting)
        #expect(model.isSplitSidebarVisible)

        model.setSidebarBattleRound(true)
        #expect(model.showMainTab == .game)
        #expect(model.showsBattleRoundSidebar)
        #expect(model.showSettingTab == .none)

        model.setSidebarOtherView(true)
        #expect(model.showMainTab == .game)
        #expect(model.showSettingTab == .setting)
        #expect(!model.showsBattleRoundSidebar)
    }

    @Test("Turning the active second view off in a split layout keeps it")
    func splitSecondaryCannotBeTurnedOff() {
        let model = GameScreenModel()
        model.sidebarLayout = .vertical
        model.setSidebarOtherView(true)

        model.setSidebarOtherView(false)
        #expect(model.showSettingTab == .setting)
        #expect(model.showMainTab == .game)

        model.setSidebarBattleRound(true)
        model.setSidebarBattleRound(false)
        #expect(model.showsBattleRoundSidebar)
    }

    @Test("Hiding the Game View hides the whole split sidebar and reopening restores the second view")
    func splitHideAndRestore() {
        let model = GameScreenModel()
        model.sidebarLayout = .horizontal
        model.setSidebarBattleRound(true)

        model.setSidebarPrimaryView(false, primaryModule: .game, allowsPrimaryView: true)
        #expect(!model.isInlineSidebarVisible)

        model.setSidebarPrimaryView(true, primaryModule: .game, allowsPrimaryView: true)
        #expect(model.showMainTab == .game)
        #expect(model.showsBattleRoundSidebar)
        #expect(model.showSettingTab == .none)
    }

    @Test("A battle that closes its panel falls back to the Other View in a split layout")
    func splitBattleClosingFallsBack() {
        let model = GameScreenModel()
        model.sidebarLayout = .horizontal
        model.setSidebarBattleRound(true)

        model.showsBattleRoundSidebar = false

        #expect(model.showMainTab == .game)
        #expect(model.showSettingTab == .setting)
    }

    @Test("Changing the layout keeps a shown sidebar consistent")
    func layoutChangeNormalizesSidebar() {
        let model = GameScreenModel()
        model.showSettingTab = .setting

        model.sidebarLayout = .vertical
        #expect(model.showMainTab == .game)
        #expect(model.showSettingTab == .setting)

        model.sidebarLayout = .single
        #expect(model.showMainTab == .game)
        #expect(model.showSettingTab == .none)

        model.hideInlineSidebar()
        model.sidebarLayout = .horizontal
        #expect(!model.isInlineSidebarVisible)
    }

    @Test("The vertical layout reserves both columns")
    func verticalLayoutReservesTwoColumns() {
        let model = GameScreenModel()
        model.updateInlineMainOverlayWidth(300)
        model.sidebarLayout = .vertical
        model.setSidebarOtherView(true)

        #expect(model.inlineSidebarWidth == 300 * 2 + GameScreenModel.mapOverlaySpacing)
        #expect(model.mapTrailingViewportReservation == model.inlineSidebarWidth + GameScreenModel.mapOverlaySpacing)

        model.sidebarLayout = .horizontal
        #expect(model.inlineSidebarWidth == 300)
    }

    @Test("The bottom placement reserves the map's bottom, not its trailing edge")
    func bottomPlacementReservesBottom() {
        let model = GameScreenModel()
        model.updateInlineMainOverlayWidth(300)
        model.updateBottomPanelHeight(400)
        model.showMainTab = .game

        #expect(model.mapTrailingViewportReservation > 0)
        #expect(model.mapBottomViewportReservation == 0)

        model.sidebarPlacement = .bottom
        #expect(model.mapTrailingViewportReservation == 0)
        #expect(model.topMenuTrailingReservation == 0)
        #expect(model.mapBottomViewportReservation == 400 + GameScreenModel.mapOverlaySpacing)

        model.hideInlineSidebar()
        #expect(model.mapBottomViewportReservation == 0)
    }

    @Test("Enlarging the bottom sidebar changes its height share, not its width")
    func bottomSidebarEnlargeChangesHeight() {
        let model = GameScreenModel()
        model.sidebarPlacement = .bottom
        let width = model.sideBarWidth

        #expect(model.bottomSidebarHeightFraction == 0.5)
        #expect(!model.isSidebarEnlarged)

        model.toggleSidebarSize()

        #expect(model.isSidebarEnlarged)
        #expect(model.bottomSidebarHeightFraction > 0.5)
        #expect(model.sideBarWidth == width)

        model.sidebarPlacement = .trailing
        #expect(!model.isSidebarEnlarged)
        model.toggleSidebarSize()
        #expect(model.isSidebarEnlarged)
        #expect(model.sideBarWidth > width)
    }

    @Test("The bottom toolbar rises above any view shown in the bottom panel")
    func toolBarRisesAboveBottomPanel() {
        let model = GameScreenModel()
        model.updateBottomPanelHeight(300)
        model.showSettingTab = .setting
        #expect(model.toolBarBottomReservation == 0)

        model.sidebarPlacement = .bottom
        #expect(model.toolBarBottomReservation == 300 + GameScreenModel.mapOverlaySpacing)

        model.hideInlineSidebar()
        #expect(model.toolBarBottomReservation == 0)
    }

    @Test("The quick dice overlay and toggle sit above a shown bottom panel without shortening it")
    func quickDiceAboveBottomPanel() {
        let model = GameScreenModel()
        model.sidebarPlacement = .bottom
        model.updateBottomPanelHeight(300)
        model.updateChromeSafeAreaInsets(top: 59, trailing: 0, bottom: 34)
        model.updateQuickDiceOverlayHeight(120)
        model.showQuickDice = true

        #expect(model.quickDiceToggleBottomReservation == 0)
        model.showMainTab = .game

        // The panel's part under the bottom safe area is not counted.
        #expect(model.quickDiceToggleBottomReservation == 300 - 34 + GameScreenModel.mapOverlaySpacing)
        #expect(model.quickDiceBottomReservation == 0)
        #expect(model.quickDiceToggleTrailingReservation == model.sideBarWidth)

        model.sidebarPlacement = .trailing
        #expect(model.quickDiceBottomReservation > 0)
    }

    @Test("On the iPhone the toolbar rises above an open quick dice overlay")
    func toolBarRisesAboveQuickDiceOverlay() {
        let model = GameScreenModel()
        model.updateQuickDiceOverlayHeight(120)
        model.updateChromeSafeAreaInsets(top: 59, trailing: 0, bottom: 34)
        model.showQuickDice = true

        // Not at regular width.
        #expect(model.toolBarBottomReservation == 0)

        model.isCompactWidth = true
        #expect(model.toolBarBottomReservation == 120 + GameScreenModel.mapOverlaySpacing)
        #expect(model.fullScreenControlsBottomClearance == 120 + GameScreenModel.mapOverlaySpacing + 34)

        // Stacked on top of a bottom panel, which the overlay itself sits above.
        model.sidebarPlacement = .bottom
        model.updateBottomPanelHeight(300)
        model.showMainTab = .game
        #expect(model.toolBarBottomReservation
            == (300 - 34 + GameScreenModel.mapOverlaySpacing) + 120 + GameScreenModel.mapOverlaySpacing)

        model.showQuickDice = false
        #expect(model.toolBarQuickDiceClearance == 0)
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

        model.showsBattleRoundSidebar.toggle()
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

        model.showsBattleRoundSidebar.toggle()
        #expect(model.showsBattleRoundSidebar)

        model.showsBattleRoundSidebar.toggle()
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

    @Test("Top menu only reserves the part of the side panel inside the safe area")
    func topMenuReservationExcludesTrailingOverhang() {
        let model = GameScreenModel()
        let padding = GameScreenModel.chromeHorizontalPadding
        model.updateInlineMainOverlayWidth(300)
        model.updateChromeSafeAreaInsets(top: 0, trailing: 84)

        #expect(model.topMenuTrailingReservation == 0)

        model.showMainTab = .game
        #expect(model.topMenuTrailingReservation == 216 - padding)

        model.updateChromeSafeAreaInsets(top: 0, trailing: .infinity)
        #expect(model.topMenuTrailingReservation == 300 - padding)

        model.updateChromeSafeAreaInsets(top: 0, trailing: 400)
        #expect(model.topMenuTrailingReservation == 0)
    }

    @Test("Side panel content starts one spacing step below the top menu")
    func sidePanelContentTopFollowsMenu() {
        let model = GameScreenModel()
        model.updateTopGameMenuHeight(45)
        #expect(model.sidePanelContentTop == 45 + GameScreenModel.mapOverlaySpacing)

        model.updateChromeSafeAreaInsets(top: 62, trailing: 0)
        #expect(model.sidePanelContentTop == 62 + 45 + GameScreenModel.mapOverlaySpacing)
    }

    @Test("3D table remains local to the main game display")
    func inlineTableSupportExcludesExternalPlayerDisplay() {
        #expect(GameMapContentType.master.supportsInlineThreeDTable)
        #expect(GameMapContentType.player.supportsInlineThreeDTable)
        #expect(!GameMapContentType.externalPlayer.supportsInlineThreeDTable)
    }
}
#endif
