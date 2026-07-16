// @copyright André Trettin

import CoreRPG
import SwiftUI

struct BrowserRowView: View {
    let root: GameRoot
    let playerNetworkControllable: any PlayerNetworkControllable
    let model: BrowserGameModel

    @Environment(\.browserMode) private var browserMode

    var body: some View {
        if !isDeactivate {
            Button {
                Task {
                    await root.startGame(to: model, mode: gameType)
                }
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(labelText, bundle: .module)
                        Text(connectionModeLabel, bundle: .module)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: connectionModeIcon)
                        .imageScale(.large)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var connectionModeIcon: String {
        switch model.connectionMode {
        case .observer: "crown.fill"
        case .proxy: "arrow.uturn.backward.circle.fill"
        }
    }

    private var connectionModeLabel: LocalizedStringKey {
        switch model.connectionMode {
        case .observer: "Game Master"
        case .proxy: "Player"
        }
    }

    private var labelText: LocalizedStringKey {
        if isConnected {
            return "Disconnect from: \(model.deviceName)"
        }
        if browserMode == .observer {
            return "Observe: \(model.deviceName)"
        }
        return "Connect to: \(model.deviceName)"
    }

    private var gameType: GameType {
        switch browserMode {
        case .observer: .observer
        case .player: .player
        case .proxy: .proxy
        }
    }
}

private extension BrowserRowView {
    var isConnected: Bool {
        playerNetworkControllable.networkModel.playerConnectionId == model.id
    }

    var isDeactivate: Bool {
        let id = playerNetworkControllable.networkModel.playerConnectionId
        return id != nil && id != model.id
    }
}

#Preview {
    BrowserRowView(
        root: .previewFixture(game: .player),
        playerNetworkControllable: PlayerNetworkController(name: "Aria"),
        model: BrowserGameModel(
            id: GamePreviewData.masterID,
            endpointName: "Morgan.MasterRPG",
            connectionMode: .observer
        )
    )
}
