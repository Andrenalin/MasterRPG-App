// @copyright André Trettin

import CoreRPG
import SwiftUI

struct GameRootSetupView: View {
    let root: GameRoot
    let openStatistics: @MainActor () -> Void
    let openSupporter: @MainActor () -> Void
    private let startsServices: Bool
    
    @Environment(AppGameStateModel.self) private var appGameStateModel
    @Environment(ScenesManager.self) private var scenesManager

#if os(tvOS)
    @AppStorage(GameStorageKeys.lastSelectedGameType, store: .standard)
    private var selectedRole: GameSetupRole = .join
#else
    @AppStorage(GameStorageKeys.lastSelectedGameType, store: .standard)
    private var selectedRole: GameSetupRole = .player
#endif

    init(
        root: GameRoot,
        openStatistics: @escaping @MainActor () -> Void,
        openSupporter: @escaping @MainActor () -> Void = {},
        startsServices: Bool = true
    ) {
        self.root = root
        self.openStatistics = openStatistics
        self.openSupporter = openSupporter
        self.startsServices = startsServices
    }
    
    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        
        ZStack {
            if appGameStateModel.isGameRunning {
                Color.clear.ignoresSafeArea()
            } else {
                ZStack(alignment: .topTrailing) {
                    PortalGateStartGameView(
                        root: root,
                        role: $selectedRole,
                        openStatistics: openStatistics,
                        openSupporter: openSupporter
                    )
#if os(macOS)
                    Button {
                        scenesManager.openWindow(SceneId.editor)
                    } label: {
                        Label { Text("Editor Window", bundle: .module) } icon: { Image(systemName: "square.and.pencil") }
                            .padding()
                    }
                    .clipShape(.capsule)
                    .padding(.trailing)
#endif
                }
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
        }
    }
}

#Preview(traits: .mockData) {
    GameRootSetupView(
        root: .preview,
        openStatistics: {},
        openSupporter: {},
        startsServices: false
    )
    .environment(AppFocusModel())
}
