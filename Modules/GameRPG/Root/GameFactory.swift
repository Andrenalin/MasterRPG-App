// @copyright André Trettin

import AudioRPG
import CharacterRPG
import CoreRPG
import DiceRPG
#if !os(tvOS)
import GeneratorRPG
#endif
import MapRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import TableRPG
import SwiftUI
import WeatherRPG

public enum GameFactory {
    @MainActor public static func rootSearchView(root: GameRoot, navigator: Navigator) -> some View {
        SearchRootView(root: root, navigator: navigator)
    }
        
    @MainActor @ViewBuilder public static func detailSearchView(root: GameRoot, navigator: Navigator) -> some View {
        SearchDetailView(root: root, navigator: navigator)
    }
    
    @MainActor public static func rootGameView(root: GameRoot) -> some View {
        GameRootView(root: root)
    }

    @MainActor public static func rootSetupView(
        root: GameRoot,
        openStatistics: @escaping @MainActor () -> Void,
        openSupporter: @escaping @MainActor () -> Void = {}
    ) -> some View {
        GameRootSetupView(
            root: root,
            openStatistics: openStatistics,
            openSupporter: openSupporter
        )
    }

    @MainActor public static func statisticsView(
        root: GameRoot,
        showsDismissButton: Bool = false
    ) -> some View {
        GameStatisticsDashboardView(
            model: root.statisticsModel,
            gameCenterModel: root.gameCenterModel,
            gameCenterController: root.gameCenterController,
            showsDismissButton: showsDismissButton
        )
    }

    @MainActor public static func battleRoundView(root: GameRoot) -> some View {
        BattleRoundWindowView(root: root)
    }
}
