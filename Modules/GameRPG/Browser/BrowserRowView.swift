// @copyright André Trettin

import CoreRPG
import SwiftUI

struct BrowserRowView: View {
    let root: GameRoot
    let playerNetworkControllable: any PlayerNetworkControllable
    let model: BrowserGameModel

    @Environment(\.browserMode) private var browserMode
    @Environment(\.supporterTier) private var supporterTier

    @State private var isEnteringCode = false
    @State private var enteredCode = ""

    var body: some View {
        if !isDeactivate {
            Button {
                if isConnected {
                    Task { await connect(joinCode: "") }
                } else {
                    enteredCode = ""
                    isEnteringCode = true
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
                    switch model.connectionMode {
                    case .observer:
                        SupporterCrownView(tier: model.supporterTier)
                            .imageScale(.large)
                    case .proxy:
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .imageScale(.large)
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .clipShape(.capsule)
            .sheet(isPresented: $isEnteringCode) {
                GameJoinCodeEntrySheet(
                    deviceName: model.deviceName,
                    connectionModeLabel: connectionModeLabel,
                    code: $enteredCode
                ) {
                    Task { await connect(joinCode: enteredCode) }
                }
            }
        }
    }

    private func connect(joinCode: String) async {
        let wasConnected = isConnected
        await root.startGame(
            to: model,
            mode: gameType,
            supporterTier: supporterTier,
            joinCode: joinCode
        )
        if !wasConnected && root.gameModel.gameConfig.state == .started {
            await MasterRPGTips.donateGameStartedOrJoined()
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

/// Prompts for the host's join code before a new connection is attempted.
/// Not shown for disconnecting — that needs no code, see `connect(joinCode:)`.
private struct GameJoinCodeEntrySheet: View {
    let deviceName: String
    let connectionModeLabel: LocalizedStringKey
    @Binding var code: String
    let onJoin: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(spacing: 4) {
                    Text("Ask \(deviceName) for their code:", bundle: .module)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Text(connectionModeLabel, bundle: .module)
                        .bold()
                }
                GameJoinCodeField(title: "Code", code: $code)
            }
            .padding()
            .navigationTitle(Text("Enter Code", bundle: .module))
#if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Join") {
                        onJoin()
                        dismiss()
                    }
                    .disabled(!GameJoinCodeModel.isValidCode(code))
                }
            }
        }
#if os(macOS)
        .frame(minWidth: 320, minHeight: 220)
#endif
    }
}

#Preview {
    BrowserRowView(
        root: .previewFixture(game: .player),
        playerNetworkControllable: PlayerNetworkController(name: "Aria"),
        model: BrowserGameModel(
            id: GamePreviewData.masterID,
            endpointName: "Morgan.MasterRPG",
            connectionMode: .observer,
            supporterTier: .gold
        )
    )
}
