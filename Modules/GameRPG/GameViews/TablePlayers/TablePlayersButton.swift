// @copyright André Trettin

#if !os(tvOS)
import CharacterRPG
import CoreRPG
import SwiftUI

/// Opens `TablePlayersView`: the game master's players, or a player's companions.
struct TablePlayersButton: View {
    let root: GameRoot

    @State private var isPresented = false
#if os(visionOS)
    @Environment(ScenesManager.self) private var scenesManager
#endif

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        let isMaster = root.gameModel.gameConfig.isMaster
        Button {
#if os(visionOS)
            toggleWindow()
#else
            isPresented.toggle()
#endif
        } label: {
            Label {
                if isMaster {
                    Text("Players", bundle: .module)
                } else {
                    Text("Companions", bundle: .module)
                }
            } icon: {
                Image(systemName: isMaster ? "person.3" : "person.2")
            }
            .labelStyle(.iconOnly)
        }
        .help(isMaster ? Text("Players", bundle: .module) : Text("Companions", bundle: .module))
        .accessibilityHint(isMaster
            ? Text("Shows the players and the Characters at the table", bundle: .module)
            : Text("Shows the companions you bring to the table", bundle: .module))
#if !os(visionOS)
        .popover(isPresented: $isPresented) {
            TablePlayersWindowView(root: root)
                .frame(minWidth: 340, idealWidth: 400, minHeight: 480, idealHeight: 620)
        }
#endif
    }

#if os(visionOS)
    /// A window, not a popover: a popover inside a seat panel of the 3D table would be tied to
    /// the table's volume. A second tap closes the window again.
    private func toggleWindow() {
        switch scenesManager.getSceneState(for: SceneId.tablePlayers) {
        case .opening, .opened:
            scenesManager.dismissWindow(SceneId.tablePlayers)
        case .closing, .closed:
            scenesManager.openWindow(SceneId.tablePlayers)
        }
    }
#endif
}

/// The players / companions list inside a managed presentation, shown in a popover or, on
/// visionOS, in its own window.
struct TablePlayersWindowView: View {
    let root: GameRoot

    var body: some View {
        ManagedPresentationView {
            TablePlayersView(root: root)
                .id(root.gameModel.gameConfig.isMaster)
        }
    }
}

#Preview(traits: .mockData) {
    TablePlayersView(root: GameRoot.previewFixture())
}

#endif
