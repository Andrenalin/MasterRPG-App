// @copyright André Trettin

import CoreRPG
import SwiftUI
import MapRPG
import CharacterRPG

struct GameRootView: View {
    let root: GameRoot

    @Environment(AppGameStateModel.self) private var appGameStateModel

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()

        GameView(root: root)
            .onChange(of: root.gameModel.gameConfig.state, initial: true) { _, newState in
                let isRunning = newState == .started
                if appGameStateModel.isGameRunning != isRunning {
                    appGameStateModel.isGameRunning = isRunning
                }
                let newModus: GameModus = isRunning
                    ? (root.gameModel.gameConfig.isMaster ? .master : .player)
                    : .edit
                if appGameStateModel.gameModus != newModus {
                    appGameStateModel.gameModus = newModus
                }
            }
    }
}

private struct GameView: View {
    let root: GameRoot

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        Group {
            if let playerController = root.gameModel.playerController {
                if root.gameModel.gameConfig.isMaster {
                    if let adventureId = root.gameModel.gameConfig.master.adventureId {
                        MasterGameScreen(root: root, playerController: playerController, adventureId: adventureId)
                    }
                } else {
                    PlayerGameScreen(root: root, playerController: playerController)
                }
            }
        }
        .modifier(GameActionEnvironmentSetUpViewModifier(root: root))

#if os(iOS)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
#endif
#if os(iOS) || os(visionOS)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
#endif
    }
}

struct GameActionEnvironmentSetUpViewModifier: ViewModifier {
    let root: GameRoot

    func body(content: Content) -> some View {
        content
            .environment(\.mapActions, root.mapRoot.mapActions)
            .environment(\.networkActions, root.networkActions)
            .environment(\.sharingControlActions, root.sharingControlActions)
            .environment(\.sharingFeatureActions, root.sharingFeatureActions)
            .environment(
                \.itemGenerationResultAction,
                ItemGenerationResultAction(id: .object(ObjectIdentifier(root))) { summary in
                    root.gameModel.generatedValueEntry = ValueEntryModel(
                        generationSummary: summary
                    )
                }
            )
    }
}


#Preview(traits: .mockData) {
    GameRootView(root: .preview)
        .environment(AppFocusModel())
}
