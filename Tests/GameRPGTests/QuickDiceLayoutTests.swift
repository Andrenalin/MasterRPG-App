// @copyright André Trettin

@testable import CoreRPG
import Foundation
import Testing

@testable import GameRPG

@MainActor
@Suite("Quick dice layout")
struct QuickDiceLayoutTests {
    @Test("The sidebar keeps its full height while the overlay is hidden or not yet measured")
    func noReservationWithoutOverlay() {
        let sut = GameScreenModel()
        sut.updateQuickDiceOverlayHeight(120)
        #expect(sut.quickDiceBottomReservation == 0)

        sut.showQuickDice = true
        sut.updateQuickDiceOverlayHeight(0)
        #expect(sut.quickDiceBottomReservation == 0)
    }

    @Test("The sidebar stops above the overlay, its spacing and the bottom safe area")
    func reservation() {
        let sut = GameScreenModel()
        sut.showQuickDice = true
        sut.updateQuickDiceOverlayHeight(120)
        sut.updateChromeSafeAreaInsets(top: 0, trailing: 0, bottom: 20)

        #expect(sut.quickDiceBottomReservation == 120 + 20 + GameScreenModel.mapOverlaySpacing)
    }

#if !os(visionOS)
    @Test("The toggle button sits beside the overlay, else beside the sidebar, else at the screen edge")
    func toggleReservation() {
        let sut = GameScreenModel()
        #expect(sut.quickDiceToggleTrailingReservation == 0)

        sut.updateInlineMainOverlayWidth(250)
        sut.showSettingTab = .setting
        #expect(sut.quickDiceToggleTrailingReservation == 250)

        sut.showQuickDice = true
        #expect(sut.quickDiceToggleTrailingReservation == sut.sideBarWidth)

        sut.showQuickDice = false
        sut.hideInlineSidebar()
        #expect(sut.quickDiceToggleTrailingReservation == 0)
    }
#endif

    @Test("Invalid measurements count as zero")
    func invalidHeight() {
        let sut = GameScreenModel()
        sut.updateQuickDiceOverlayHeight(.nan)
        #expect(sut.quickDiceOverlayHeight == 0)
    }

    @Test("The quick dice setting is off by default and restored by a new settings model")
    func settingRoundTrip() throws {
        let suiteName = "QuickDiceLayoutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = AppSettingsModel(defaults: defaults)
        #expect(!first.showGameQuickDice)
        first.showGameQuickDice = true

        #expect(AppSettingsModel(defaults: defaults).showGameQuickDice)
    }
}
