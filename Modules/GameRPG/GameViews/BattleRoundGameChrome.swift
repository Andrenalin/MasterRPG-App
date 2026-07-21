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

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        let model = root.mapRoot.mapGameControllable.battleRoundModel

        ZStack {
            if model.isRunning {
                if gameScreenModel.showsBattleRoundAnnouncement {
                    BattleRoundCounterView(model: model, style: .announcement)
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
        .task(id: BattleRoundAnnouncementID(isRunning: model.isRunning, round: model.roundCounter)) {
            guard model.isRunning else {
                gameScreenModel.showsBattleRoundAnnouncement = false
                return
            }

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

private struct BattleRoundAnnouncementID: Equatable {
    let isRunning: Bool
    let round: Int
}
