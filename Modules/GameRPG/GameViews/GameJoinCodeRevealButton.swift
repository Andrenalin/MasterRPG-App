// @copyright André Trettin

import CoreRPG
import SwiftUI

/// Tap-to-reveal display of this device's own join code — the same code
/// edited in [[GameJoinCodeField]] on the setup screen — so a host can read
/// it aloud to players who want to join. Renders nothing when this device
/// has no code of its own to share (e.g. a connected Observer/Proxy client).
struct GameJoinCodeRevealButton: View {
    let root: GameRoot
    let isMaster: Bool

    @State private var isPresented = false

    var body: some View {
        if let code = root.ownJoinCode(isMaster: isMaster) {
            Button("Join Code", systemImage: "wifi") {
                isPresented = true
            }
            .labelStyle(.iconOnly)
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
            .help(Text("Show your join code", bundle: .module))
        }
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
                .font(.system(.largeTitle, design: .rounded).monospacedDigit())
                .bold()
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
