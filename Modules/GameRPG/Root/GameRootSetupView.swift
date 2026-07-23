// @copyright André Trettin

import CoreRPG
import SwiftUI

struct GameRootSetupView: View {
    let root: GameRoot
    let openStatistics: @MainActor () -> Void
    private let startsServices: Bool
    
    @Environment(AppGameStateModel.self) private var appGameStateModel
    @Environment(ScenesManager.self) private var scenesManager

    init(
        root: GameRoot,
        openStatistics: @escaping @MainActor () -> Void,
        startsServices: Bool = true
    ) {
        self.root = root
        self.openStatistics = openStatistics
        self.startsServices = startsServices
    }
    
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
                    scenesManager.openWindow(SceneId.editor)
                } label: {
                    Label { Text("Editor Window", bundle: .module) } icon: { Image(systemName: "square.and.pencil") }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .trailing)
#endif

                Button(action: openStatistics) {
                    GameStatisticsEntryLabel(sessionCount: root.statisticsModel.summary.sessionCount)
                }
                .buttonStyle(.borderedProminent)
                .fixedSize()
                .padding()

                GameOptionView(root: root)
            }
        }
        .task {
            guard startsServices else { return }
            root.networkStore.setup(gameModel: root.gameModel)
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
    GameRootSetupView(root: .preview, openStatistics: {}, startsServices: false)
}
