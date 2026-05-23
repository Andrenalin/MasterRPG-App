// @copyright André Trettin

import CoreRPG
import CharacterRPG
import SwiftUI

struct SelectedPlayerView: View {
    let root: GameRoot

    @AppStorage("lastPlayerUUID", store: .standard)
    private var playerUUID: String = ""

    @State private var selection: ItemSelectionModel = ItemSelectionModel()
    
    var body: some View {
        GroupBoxTV(isCard: true) {
            root.characterRoot.viewController.dropChooseView(model: selection)
                .frame(maxWidth: .infinity)
#if os(macOS)
                .padding()
#endif
        } label: {
            Label {
                Text(root.gameModel.selectedCharacter != nil ? "Selected Player" : "Player missing", bundle: .module)
                    .font(.headline)
            } icon: {
                Image(systemName: "theatermasks.fill")
                    .imageScale(.large)
            }
        }
        .task {
            root.resetSelectedCharacter(uuidString: playerUUID)
            selection.resetSelection(itemId: root.gameModel.selectedCharacter, entryId: nil)
        }
        .onChange(of: playerUUID, initial: true) {
            root.gameModel.selectedCharacter <=> selection.itemId
        }
        .onChange(of: selection.itemId) {
            root.gameModel.selectedCharacter <=> selection.itemId
        }
        .onChange(of: root.gameModel.selectedCharacter, initial: false) { _, newCharacter in
            if let playerId = newCharacter {
                selection.resetSelection(itemId: playerId, entryId: nil)
                playerUUID <=> playerId.uuidString
            }
        }
    }
}
