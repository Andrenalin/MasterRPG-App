// @copyright André Trettin

import CoreRPG
import CharacterRPG
import SwiftUI
import TipKit

struct SelectedPlayerView: View {
    let root: GameRoot

    @AppStorage("lastPlayerUUID", store: .standard)
    private var playerUUID: String = ""

    @State private var selection: ItemSelectionModel = ItemSelectionModel()
    
    var body: some View {
        GroupBoxTV(isCard: true) {
#if os(tvOS)
            VStack {
                TipView(MasterRPGTips.chooseCharacter)
                characterSelection
            }
#else
            characterSelection
                .popoverTip(MasterRPGTips.chooseCharacter)
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
            updateTipSelection(root.gameModel.selectedCharacter)
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
            updateTipSelection(newCharacter)
        }
    }

    private var characterSelection: some View {
        root.characterRoot.viewController.dropChooseView(model: selection)
            .frame(maxWidth: .infinity)
#if os(macOS)
            .padding()
#endif
    }

    private func updateTipSelection(_ characterID: UUID?) {
        MasterRPGTips.setSelectedCharacter(characterID != nil)
        guard characterID != nil else { return }
        Task {
            await MasterRPGTips.donateCharacterSelected()
        }
    }
}

#Preview {
    SelectedPlayerView(root: .preview)
}
