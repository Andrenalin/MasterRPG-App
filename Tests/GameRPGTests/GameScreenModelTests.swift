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

    @Test("3D table remains local to the main game display")
    func inlineTableSupportExcludesExternalPlayerDisplay() {
        #expect(GameMapContentType.master.supportsInlineThreeDTable)
        #expect(GameMapContentType.player.supportsInlineThreeDTable)
        #expect(!GameMapContentType.externalPlayer.supportsInlineThreeDTable)
    }
}
#endif
