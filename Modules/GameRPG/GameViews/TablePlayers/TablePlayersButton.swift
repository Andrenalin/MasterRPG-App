// @copyright André Trettin

#if !os(tvOS)
import CharacterRPG
import CoreRPG
import SwiftUI

/// Opens `TablePlayersView`: the game master's players, or a player's companions.
struct TablePlayersButton: View {
    let root: GameRoot

    @State private var isPresented = false

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        let isMaster = root.gameModel.gameConfig.isMaster
        Button {
            isPresented.toggle()
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
        .popover(isPresented: $isPresented) {
            ManagedPresentationView {
                TablePlayersView(root: root)
                    .id(isMaster)
            }
            .frame(minWidth: 340, idealWidth: 400, minHeight: 480, idealHeight: 620)
        }
    }
}

#Preview(traits: .mockData) {
    TablePlayersView(root: GameRoot.previewFixture())
}

#endif
