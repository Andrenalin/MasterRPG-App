// @copyright André Trettin

import AdventureRPG
import CoreRPG
import SwiftUI

struct SelectedAdventureView: View {
    let root: GameRoot

    @AppStorage("lastAdventureUUID", store: .standard)
    private var lastAdventureUUID: String = ""

    @State private var selection: ItemSelectionModel = ItemSelectionModel()
    
    var body: some View {
        GroupBoxTV(isCard: true) {
            VStack {
                root.adventureRoot.viewController.dropChooseView(model: selection)
            }
            .frame(maxWidth: .infinity)
#if os(macOS)
            .padding()
#endif
        } label: {
            Label {
                Text(root.gameModel.selectedAdventure != nil ? "Selected Adventure" : "Adventure missing", bundle: .module)
                    .font(.headline)
            } icon: {
                Image(systemName: "wand.and.stars")
                    .imageScale(.large)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(2)) {
                root.resetSelectedAdventure(uuidString: lastAdventureUUID)
                selection.resetSelection(itemId: root.gameModel.selectedAdventure)
            }
        }
        .onChange(of: lastAdventureUUID, initial: true) {
            root.gameModel.selectedAdventure <=> selection.itemId
        }
        .onChange(of: selection.itemId) {
            root.gameModel.selectedAdventure <=> selection.itemId
        }
        .onChange(of: root.gameModel.selectedAdventure) {
            if let adventureId = root.gameModel.selectedAdventure {
                selection.resetSelection(itemId: adventureId)
                lastAdventureUUID <=> adventureId.uuidString
            }
        }
    }
}
