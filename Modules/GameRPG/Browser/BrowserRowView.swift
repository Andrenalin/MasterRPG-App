// @copyright André Trettin

import CoreRPG
import SwiftUI

struct BrowserRowView: View, Equatable {
    let root: GameRoot
    let playerNetworkControllable: any PlayerNetworkControllable
    let model: BrowserGameModel

    @Environment(\.browserMode) private var browserMode
    @Environment(\.supporterTier) private var supporterTier

    @State private var isEnteringCode = false
    @State private var enteredCode = ""
    /// The code an in-flight connection attempt was made with — set right
    /// before dialing, whether that code came from `savedMasterCode` or the
    /// entry sheet. Watched below to save a code that worked and to fall
    /// back to the entry sheet for one that didn't.
    @State private var attemptedCode: String?

    var body: some View {
        if !isDeactivate {
            Button {
                if isConnected {
                    Task { await connect(joinCode: "") }
                } else if let savedCode = savedMasterCode {
                    Task { await connect(joinCode: savedCode) }
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
            .onChange(of: playerNetworkControllable.networkModel.isConnected) { _, connected in
                guard connected, let attemptedCode else { return }
                if model.connectionMode == .observer {
                    root.gameJoinCodeModel.lastUsedMasterJoinCode = attemptedCode
                }
                self.attemptedCode = nil
            }
        }
    }

    /// This device's own remembered Game Master code, tried automatically
    /// before prompting — only meaningful for a direct-to-Master connection;
    /// a proxy's code isn't remembered the same way since it's tied to
    /// whichever Player is currently proxying, not a stable identity.
    private var savedMasterCode: String? {
        guard model.connectionMode == .observer else { return nil }
        return root.gameJoinCodeModel.lastUsedMasterJoinCode
    }

    private func connect(joinCode: String) async {
        let wasConnected = isConnected
        attemptedCode = joinCode.isEmpty ? nil : joinCode
        await root.startGame(
            to: model,
            mode: gameType,
            supporterTier: supporterTier,
            joinCode: joinCode
        )
        guard !wasConnected else { return }
        if root.gameModel.gameConfig.state == .started {
            await MasterRPGTips.donateGameStartedOrJoined()
        } else if !joinCode.isEmpty {
            // `startGame` now awaits the actual handshake outcome, so landing
            // back here not started means the join code (saved or freshly
            // entered) was rejected. Prompt for a fresh one instead of
            // silently sitting back on the button.
            attemptedCode = nil
            enteredCode = ""
            isEnteringCode = true
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

extension BrowserRowView {
    /// `playerNetworkControllable` itself isn't compared — like `root`, it's
    /// a shared controller reference, not row content; what actually
    /// changes this row's rendered output is which device `model` is, and
    /// its two derived connection-state booleans. See CODE_AUDIT_13 §8.7.
    static func == (lhs: BrowserRowView, rhs: BrowserRowView) -> Bool {
        lhs.model.id == rhs.model.id
            && lhs.root === rhs.root
            && lhs.isConnected == rhs.isConnected
            && lhs.isDeactivate == rhs.isDeactivate
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
                        .foregroundStyle(.secondary)
                    Text(connectionModeLabel, bundle: .module)
                        .bold()
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)

                GameJoinCodeField(title: "Code", code: $code, submitLabel: .join, onSubmit: submitIfValid)
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
                    Button("Join", role: .confirm, action: submitIfValid)
                        .disabled(!GameJoinCodeModel.isValidCode(code))
                }
            }
        }
#if os(macOS)
        .frame(minWidth: 320, minHeight: 260)
#endif
    }

    /// Shared by the toolbar's Join button and the OTP field's return key —
    /// pressing return on the last digit joins immediately instead of
    /// requiring a separate tap, but only once the code is actually valid.
    private func submitIfValid() {
        guard GameJoinCodeModel.isValidCode(code) else { return }
        onJoin()
        dismiss()
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
