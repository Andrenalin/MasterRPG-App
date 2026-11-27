// @copyright André Trettin

import CoreRPG
import MapRPG
import SwiftUI

/// Battle presentation chrome is a sibling of the full-window game surface.
/// It never proposes a size to the map or RealityView.
struct BattleRoundGameChrome: View {
    let root: GameRoot

    @Environment(GameScreenModel.self) private var gameScreenModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    /// The attacker named in the announcement, taken when a round is
    /// announced. The chrome sits on every game screen; reading the name live
    /// made it depend on the whole battle roster, so every hit-point or
    /// highlight change re-evaluated it. It needs the running flag and the
    /// round only.
    @State private var announcedAttackerName: String?

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        let model = root.mapRoot.mapGameControllable.battleRoundModel
        let round = model.roundCounter

        ZStack {
            if model.isRunning {
                if gameScreenModel.showsBattleRoundAnnouncement {
                    BattleRoundAnnouncementCounter(
                        round: round,
                        attackerName: announcedAttackerName
                    )
                    .accessibilityElement(children: .combine)
                    .transition(.scale(scale: 0.82).combined(with: .opacity))
                    .allowsHitTesting(false)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .animation(
            accessibilityReduceMotion ? nil : .spring(duration: 0.4, bounce: 0.18),
            value: gameScreenModel.showsBattleRoundAnnouncement
        )
        .task(id: BattleRoundAnnouncementId(isRunning: model.isRunning, round: round)) {
            guard model.isRunning else {
                gameScreenModel.showsBattleRoundAnnouncement = false
                return
            }

            // Read here, outside `body`, so the roster is not a dependency
            // of this view.
            announcedAttackerName = model.activeEntry.flatMap { model.attacker(for: $0) }?.name

            withAnimation(accessibilityReduceMotion ? nil : .spring(duration: 0.32)) {
                gameScreenModel.showsBattleRoundAnnouncement = true
            }

            do {
                try await Task.sleep(for: accessibilityReduceMotion ? .seconds(0.8) : .seconds(1.35))
            } catch {
                return
            }

            withAnimation(accessibilityReduceMotion ? nil : .spring(duration: 0.4, bounce: 0.18)) {
                gameScreenModel.showsBattleRoundAnnouncement = false
            }
        }
        .onDisappear {
            gameScreenModel.showsBattleRoundAnnouncement = false
        }
    }
}

private struct BattleRoundAnnouncementId: Equatable {
    let isRunning: Bool
    let round: Int
}

private struct BattleRoundGameChromePreview: View {
    @State private var root: GameRoot
    @State private var screenModel: GameScreenModel

    init() {
        let screenModel = GameScreenModel()
        screenModel.showsBattleRoundAnnouncement = true
        _root = State(initialValue: GameRoot.previewFixture())
        _screenModel = State(initialValue: screenModel)
    }

    var body: some View {
        BattleRoundGameChrome(root: root)
            .environment(screenModel)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("Battle announcement") {
    BattleRoundGameChromePreview()
}
