// @copyright André Trettin

import CoreRPG
import SwiftUI
import TipKit

/// The merged wifi/connection-status icon: shows this device's live
/// connection status when one is known (a Player's link to the Master or
/// SharePlay group), and tapping it reveals this device's own join code —
/// the same code edited in [[GameJoinCodeField]] on the setup screen — so a
/// host can read it aloud to players who want to join. Renders nothing when
/// this device has no code of its own to share — except for an observer or proxy, which never
/// host and so show only the connection status.
struct GameJoinCodeRevealButton: View {
    let root: GameRoot
    let isMaster: Bool
    var connectionStatus: GameConnectionStatusPresentation? = nil

    @State private var isPresented = false

    var body: some View {
        if let code = root.ownJoinCode(isMaster: isMaster) {
            codeButton(code: code)
        } else if let connectionStatus {
            // An observer or proxy has no code of its own to share (it never hosts), but still
            // shows its connection to the game.
            Label {
                Text(connectionStatus.title, bundle: .module)
            } icon: {
                Image(systemName: connectionStatus.systemImage)
            }
            .labelStyle(.iconOnly)
            .foregroundStyle(connectionStatus.tint)
            .help(Text(connectionStatus.title, bundle: .module))
        }
    }

    @ViewBuilder
    private func codeButton(code: String) -> some View {
        Button {
            isPresented = true
            Task { await MasterRPGTips.donateJoinCodeViewed() }
        } label: {
            Label {
                Text(title, bundle: .module)
            } icon: {
                Image(systemName: connectionStatus?.systemImage ?? "wifi")
            }
        }
        .labelStyle(.iconOnly)
        .foregroundStyle(connectionStatus?.tint ?? .primary)
#if os(tvOS)
        .sheet(isPresented: $isPresented) {
            GameJoinCodeRevealContent(isMaster: isMaster, code: code)
        }
#else
        .popover(isPresented: $isPresented) {
            GameJoinCodeRevealContent(isMaster: isMaster, code: code)
#if os(iOS)
                .presentationCompactAdaptation(.popover)
#endif
        }
#endif
        .help(Text(title, bundle: .module))
        .accessibilityLabel(Text(title, bundle: .module))
        .popoverTip(MasterRPGTips.showJoinCode)
    }

    /// The connection status's own title when one is known (so VoiceOver/help
    /// still announces "Connection Lost" etc.), falling back to a plain
    /// "Join Code" label for the Master, who has no connection status of
    /// their own to report.
    private var title: LocalizedStringKey {
        connectionStatus?.title ?? "Join Code"
    }
}

private struct GameJoinCodeRevealContent: View {
    let isMaster: Bool
    let code: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title, bundle: .module)
                .font(.headline)
            Text(code)
                .font(.largeTitle)
                .fontDesign(.monospaced)
                .bold()
                .speechSpellsOutCharacters()
            Text("Share this code with players who want to join.", bundle: .module)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(minWidth: 220)
    }

    private var title: LocalizedStringKey {
        isMaster ? "Game Master Code" : "Your Player Code"
    }
}

#Preview {
    GameJoinCodeRevealButton(root: .previewFixture(), isMaster: true)
        .padding()
}
