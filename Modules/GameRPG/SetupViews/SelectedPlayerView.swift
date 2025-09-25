// @copyright André Trettin

import CharacterRPG
import CoreRPG
import SwiftUI

struct SelectedPlayerView: View {
    let root: GameRootController

    @AppStorage("lastPlayerUUID", store: .standard)
    private var playerUUID: String = ""
    
    @State private var selection: ItemSelectionModel = ItemSelectionModel()
    
    var body: some View {
        GroupBoxTV(isCard: true) {
            VStack {
                ViewThatFits {
                    HStack {
                        selectedView

                        root.characterRoot.viewController.selectionView(root: root.characterRoot, model: selection)
                    }

                    VStack {
                        selectedView

                        Divider()

                        root.characterRoot.viewController.selectionView(root: root.characterRoot, model: selection)
                    }
                }
            }
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
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(2)) {
                root.resetSelectedCharacter(uuidString: playerUUID)
            }
        }
        .onChange(of: root.gameModel.selectedCharacter, initial: false) {
            if let playerId = root.gameModel.selectedCharacter {
                playerUUID <=> playerId.uuidString
            }
        }
        .onChange(of: selection.itemId, initial: false) {
            root.gameModel.selectedCharacter <=> selection.itemId
        }
    }

    private var selectedView: some View {
        VStack {
            if let id = root.gameModel.selectedCharacter {
//                root.viewController.selectedCharacterGameMasterView(with: id)
//                    .id(id)
            } else {
                Text("Select a character to join the game. The character should have a name and for convience one value with a dice as default dice for the game view. Any other values for the character are optional. You can still play with a character sheet if you or the game master prefer.", bundle: .module)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}
