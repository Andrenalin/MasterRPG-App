// @copyright André Trettin

import CoreRPG
import SwiftUI

struct GameRootSetupView: View {
    let root: GameRoot
    
    @Environment(AppGameStateModel.self) private var appGameStateModel
    @Environment(ScenesManager.self) private var sceneManager
    
    var body: some View {
        ZStack {
            if appGameStateModel.isGameRunning {
                Color.clear.ignoresSafeArea()
            } else {
                MeshAnimationView()
                    .ignoresSafeArea()
                    .opacity(0.5)
            }
            
            ScrollView {
#if os(macOS)
                Button {
                    sceneManager.openWindow(SceneId.editor)
                } label: {
                    Label { Text("Editor Window", bundle: .module) } icon: { Image(systemName: "square.and.pencil") }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .trailing)
#endif

                GameOptionView(root: root)
            }
        }
        .task {
            await root.networkStore.setup(gameModel: root.gameModel)
        }
        .onChange(of: root.gameModel.gameConfig.state, initial: true) { _, newState in
            appGameStateModel.isGameRunning = newState == .started
            appGameStateModel.gameModus = newState == .started
                ? (root.gameModel.gameConfig.isMaster ? .master : .player)
                : .edit
            root.widgetGameRunningChanged()
        }
    }
}

#Preview(traits: .mockData) {
    GameRootSetupView(root: .preview)
        .environment(AppGameStateModel())
        .environment(ScenesManager())
        .environment(AppSettingsModel())
        .environment(AppNavigationModel(appGameStateModel: AppGameStateModel()))
}
