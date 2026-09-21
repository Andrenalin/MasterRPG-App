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
    /// A join attempt is in flight. `isConnected` is already true then (the controller records
    /// the target before the handshake), so this is what tells connecting from connected.
    /// See CODE_AUDIT_Join §8.1.
    @State private var isConnecting = false
    @State private var wasCancelled = false
    /// Why the last attempt failed, shown in the code sheet. See CODE_AUDIT_Join §8.2.
    @State private var lastFailure: PlayerJoinFailure?

    var body: some View {
        if !isDeactivate {
            Button {
                if isConnecting {
                    cancelConnecting()
                } else if isConnected {
                    Task { await connect(joinCode: "") }
                } else if let savedCode = savedMasterCode {
                    Task { await connect(joinCode: savedCode) }
                } else {
                    enteredCode = ""
                    lastFailure = nil
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
                    if isConnecting {
                        ProgressView()
                    } else {
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
            }
            .buttonStyle(.borderedProminent)
            .clipShape(.capsule)
            .sheet(isPresented: $isEnteringCode) {
                GameJoinCodeEntrySheet(
                    deviceName: model.deviceName,
                    connectionModeLabel: connectionModeLabel,
                    failure: lastFailure,
                    code: $enteredCode
                ) {
                    Task { await connect(joinCode: enteredCode) }
                }
            }
        }
    }

    /// This device's remembered code for *this* Game Master, tried automatically before
    /// prompting — only meaningful for a direct-to-Master connection, and only for the host
    /// that accepted it: replaying it against any other advertiser would burn one of that host's
    /// failure allowances and hand it a handshake derived from an unrelated code. A proxy's code
    /// isn't remembered since it's tied to whichever Player is currently proxying.
    /// See CODE_AUDIT_Join §5.9.
    private var savedMasterCode: String? {
        guard model.connectionMode == .observer else { return nil }
        return root.gameJoinCodeModel.rememberedMasterJoinCode(forHost: model.endpointName)
    }

    private func cancelConnecting() {
        wasCancelled = true
        Task { await playerNetworkControllable.stop() }
    }

    private func connect(joinCode: String) async {
        let wasConnected = isConnected
        wasCancelled = false
        lastFailure = nil
        if !wasConnected { isConnecting = true }
        await root.startGame(
            to: model,
            mode: gameType,
            supporterTier: supporterTier,
            joinCode: joinCode
        )
        isConnecting = false
        guard !wasConnected, !wasCancelled else { return }
        enteredCode = ""
        if root.gameModel.gameConfig.state == .started {
            // Saved here, where the outcome is known, rather than from a view `onChange` that may
            // never run if this row has already left the screen. See CODE_AUDIT_Join §5.11.
            if model.connectionMode == .observer, !joinCode.isEmpty {
                root.gameJoinCodeModel.rememberMasterJoinCode(joinCode, forHost: model.endpointName)
            }
            await MasterRPGTips.donateGameStartedOrJoined()
        } else if !joinCode.isEmpty {
            // `startGame` awaits the actual handshake outcome, so landing back here not started
            // means the attempt failed: prompt again and say why.
            lastFailure = playerNetworkControllable.networkModel.joinFailure
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
        if isConnecting {
            return "Connecting to: \(model.deviceName)"
        }
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

private extension PlayerJoinFailure {
    var message: LocalizedStringKey {
        switch self {
        case .badCode: "That code was not accepted. Check it and try again."
        case .unreachable: "Couldn't reach the host. Wait a few seconds and try again."
        case .timedOut: "The host did not accept the connection in time. Check the code and that Local Network access is allowed, then try again."
        }
    }
}

/// Prompts for the host's join code before a new connection is attempted.
/// Not shown for disconnecting — that needs no code, see `connect(joinCode:)`.
private struct GameJoinCodeEntrySheet: View {
    let deviceName: String
    let connectionModeLabel: LocalizedStringKey
    let failure: PlayerJoinFailure?
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

                if let failure {
                    Text(failure.message, bundle: .module)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                GameJoinCodeField(title: "Code", code: $code, submitLabel: .join, onSubmit: submitIfValid)
            }
            .padding()
            .navigationTitle(Text("Enter Code", bundle: .module))
#if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() } label: { Text("Cancel", bundle: .module) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm, action: submitIfValid) { Text("Join", bundle: .module) }
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
