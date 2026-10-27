// @copyright André Trettin

import CoreRPG
import DiceRPG
import SwiftUI

struct GameDiceVisibilityPersistence: ViewModifier {
    let gameScreenModel: GameScreenModel
    let diceDisplayModel: DiceDisplayModel

    @Environment(AppSettingsModel.self) private var appSettingsModel

    func body(content: Content) -> some View {
        content
            .onChange(of: appSettingsModel.showGameDice, initial: true) { _, isVisible in
                guard gameScreenModel.showDice != isVisible else { return }
                gameScreenModel.showDice = isVisible
            }
            .onChange(of: gameScreenModel.showDice) { _, isVisible in
                guard appSettingsModel.showGameDice != isVisible else { return }
                appSettingsModel.showGameDice = isVisible
            }
            .onChange(of: appSettingsModel.showGameQuickDice, initial: true) { _, isVisible in
                guard gameScreenModel.showQuickDice != isVisible else { return }
                gameScreenModel.showQuickDice = isVisible
            }
            .onChange(of: gameScreenModel.showQuickDice) { _, isVisible in
                guard appSettingsModel.showGameQuickDice != isVisible else { return }
                appSettingsModel.showGameQuickDice = isVisible
            }
            .onChange(of: appSettingsModel.showGamePlayerDice, initial: true) { _, isVisible in
                guard diceDisplayModel.showPlayerDice != isVisible else { return }
                diceDisplayModel.showPlayerDice = isVisible
            }
            .onChange(of: diceDisplayModel.showPlayerDice) { _, isVisible in
                guard appSettingsModel.showGamePlayerDice != isVisible else { return }
                appSettingsModel.showGamePlayerDice = isVisible
            }
    }
}

extension View {
    func persistGameDiceVisibility(
        gameScreenModel: GameScreenModel,
        diceDisplayModel: DiceDisplayModel
    ) -> some View {
        modifier(
            GameDiceVisibilityPersistence(
                gameScreenModel: gameScreenModel,
                diceDisplayModel: diceDisplayModel
            )
        )
    }
}
