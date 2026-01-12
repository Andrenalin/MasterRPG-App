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
                selection.resetSelection(itemId: root.gameModel.selectedGameMaster, entryId: nil)
            }
        }
        .onChange(of: gameMasterUUID, initial: true) {
            root.gameModel.selectedGameMaster <=> selection.itemId
        }
        .onChange(of: selection.itemId) {
            root.gameModel.selectedGameMaster <=> selection.itemId
        }
        .onChange(of: root.gameModel.selectedGameMaster, initial: false) {
            if let playerId = root.gameModel.selectedGameMaster {
                selection.resetSelection(itemId: playerId, entryId: nil)
                gameMasterUUID <=> playerId.uuidString
            }
        }
    }
}
