// @copyright André Trettin

import CoreRPG
import SwiftUI
import CharacterRPG

struct SelectedMasterView: View {
    let root: GameRoot

    @AppStorage("lastGameMasterUUID", store: .standard)
    private var gameMasterUUID: String = ""

    @State private var selection: ItemSelectionModel = ItemSelectionModel()
    var body: some View {
        GroupBoxTV(isCard: true) {
            VStack {
                root.characterRoot.viewController.dropChooseView(model: selection)
            }
            .frame(maxWidth: .infinity)
#if os(macOS)
            .padding()
#endif
        } label: {
            Label {
                Text(root.gameModel.selectedGameMaster != nil ? "Selected Game Master" : "Game Master missing", bundle: .module)
                    .font(.headline)
            } icon: {
                Image(systemName: "theatermask.and.paintbrush.fill")
                    .imageScale(.large)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(2)) {
                root.resetSelectedGameMaster(uuidString: gameMasterUUID)
            }
        }
        .onChange(of: root.gameModel.selectedGameMaster, initial: false) {
            if let playerId = root.gameModel.selectedGameMaster {
                gameMasterUUID <=> playerId.uuidString
                selection.resetSelection(itemId: playerId)
            }
        }
    }

    private var selectedView: some View {
        VStack {
            if let id = root.gameModel.selectedGameMaster {
                root.viewController.selectedCharacterGameMasterView(with: id, isGameMaster: true)
                    .id(id)
            } else {
                Text("Select a game master to start the game. The game master should have a name and for convience one value with a dice as default dice for the game view.", bundle: .module)
                    .lineLimit(10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
