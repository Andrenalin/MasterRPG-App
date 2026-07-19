// @copyright André Trettin

#if canImport(Testing)
import Testing

@testable import GameRPG

@Suite("Game chrome status presentation")
struct GameChromeStatusPresentationTests {
    @Test("Inactive battle uses the placeholder")
    func inactiveBattleIndicator() {
        let presentation = GameChromeStatusPresentation(
            isBattleRunning: false,
            battleRound: 7,
            isSharePlayActive: false
        )

        #expect(presentation.battleRoundIndicator == .inactive)
    }

    @Test("Active battle uses only the round number")
    func activeBattleIndicator() {
        let presentation = GameChromeStatusPresentation(
            isBattleRunning: true,
            battleRound: 1,
            isSharePlayActive: false
        )

        #expect(presentation.battleRoundIndicator == .round(1))
    }

    @Test("SharePlay replaces the Wi-Fi connection indicator")
    func sharePlayConnectionVisibility() {
        let networkPresentation = GameChromeStatusPresentation(
            isBattleRunning: false,
            battleRound: 0,
            isSharePlayActive: false
        )
        let sharePlayPresentation = GameChromeStatusPresentation(
            isBattleRunning: false,
            battleRound: 0,
            isSharePlayActive: true
        )

        #expect(networkPresentation.showsConnectionStatus)
        #expect(!sharePlayPresentation.showsConnectionStatus)
    }
}
#endif
