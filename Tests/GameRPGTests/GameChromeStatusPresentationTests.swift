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
            lostMaster: false,
            sharePlayState: .inactive
        )

        #expect(presentation.battleRoundIndicator == .inactive)
    }

    @Test("Active battle uses only the round number")
    func activeBattleIndicator() {
        let presentation = GameChromeStatusPresentation(
            isBattleRunning: true,
            battleRound: 1,
            lostMaster: false,
            sharePlayState: .inactive
        )

        #expect(presentation.battleRoundIndicator == .round(1))
    }

    struct ConnectionCase: Sendable, CustomTestStringConvertible {
        let lostMaster: Bool
        let sharePlayState: SharePlayConnectionState
        let expected: GameConnectionStatusPresentation
        let testDescription: String
    }

    @Test(
        "Connection indicator represents the selected transport and state",
        arguments: [
            ConnectionCase(
                lostMaster: false,
                sharePlayState: .inactive,
                expected: .localNetworkConnected,
                testDescription: "local network connected"
            ),
            ConnectionCase(
                lostMaster: true,
                sharePlayState: .inactive,
                expected: .localNetworkLost,
                testDescription: "local network lost"
            ),
            ConnectionCase(
                lostMaster: true,
                sharePlayState: .waiting,
                expected: .sharePlayWaiting,
                testDescription: "SharePlay awaiting Open in"
            ),
            ConnectionCase(
                lostMaster: false,
                sharePlayState: .joined,
                expected: .sharePlayConnected,
                testDescription: "SharePlay connected"
            ),
            ConnectionCase(
                lostMaster: true,
                sharePlayState: .joined,
                expected: .sharePlayLost,
                testDescription: "SharePlay joined without the game master"
            ),
            ConnectionCase(
                lostMaster: false,
                sharePlayState: .disconnected,
                expected: .sharePlayLost,
                testDescription: "SharePlay invalidated"
            )
        ]
    )
    func connectionIndicator(testCase: ConnectionCase) {
        // Given / When
        let presentation = GameChromeStatusPresentation(
            isBattleRunning: false,
            battleRound: 0,
            lostMaster: testCase.lostMaster,
            sharePlayState: testCase.sharePlayState
        )

        // Then
        #expect(presentation.connectionStatus == testCase.expected)
    }
}
#endif
