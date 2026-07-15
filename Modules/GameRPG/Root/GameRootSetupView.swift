// @copyright André Trettin

import CoreRPG
import SwiftUI

struct GameRootSetupView: View {
    let root: GameRoot
    let openStatistics: @MainActor () -> Void
    
    @Environment(AppGameStateModel.self) private var appGameStateModel
    @Environment(ScenesManager.self) private var scenesManager
    
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

                GameOptionView(root: root)

                Button(action: openStatistics) {
                    GameStatisticsEntryLabel(sessionCount: root.statisticsModel.summary.sessionCount)
                }
                .buttonStyle(.borderedProminent)
                .padding()
            }
        }
        .task {
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

private struct GameStatisticsEntryLabel: View {
    let sessionCount: Int

    var body: some View {
        HStack {
            Image(systemName: "chart.bar.xaxis")
                .imageScale(.large)

            VStack(alignment: .leading) {
                Text("Game Statistics", bundle: .module)
                    .bold()
                if sessionCount == 0 {
                    Text("Explore an example dashboard", bundle: .module)
                        .font(.caption)
                } else {
                    Text("Recorded games: \(sessionCount)", bundle: .module)
                        .font(.caption)
                }
            }

            Spacer()

            Image(systemName: "chevron.forward")
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview(traits: .mockData) {
    GameRootSetupView(root: .preview, openStatistics: {})
        .environment(AppGameStateModel())
        .environment(ScenesManager())
        .environment(AppSettingsModel())
        .environment(AppNavigationModel(appGameStateModel: AppGameStateModel()))
}
