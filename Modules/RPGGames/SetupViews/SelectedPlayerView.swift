// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct SelectedPlayerView: View {
    let root: GameRoot

    @AppStorage("lastPlayerUUID", store: .standard)
    private var playerUUID: String = ""

    var body: some View {
        GroupBoxTV(isCard: true) {
            VStack {
                ViewThatFits {
                    HStack {
                        selectedView

                        ChoosePlayerView(root: root)
                    }

                    VStack {
                        selectedView

                        Divider()

                        ChoosePlayerView(root: root)
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
    }

    private var selectedView: some View {
        VStack {
            if let id = root.gameModel.selectedCharacter {
                root.viewController.selectedCharacterGameMasterView(with: id)
                    .id(id)
            } else {
                Text("Select a character to join the game. The character should have a name and for convience one value with a dice as default dice for the game view. Any other values for the character are optional. You can still play with a character sheet if you or the game master prefer.", bundle: .module)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}
