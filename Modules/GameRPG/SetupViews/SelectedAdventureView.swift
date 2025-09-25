// @copyright André Trettin

import AdventureRPG
import CoreRPG
import SwiftUI

struct SelectedAdventureView: View {
    let root: GameRootController

    @AppStorage("lastAdventureUUID", store: .standard)
    private var lastAdventureUUID: String = ""

    @State private var selection: ItemSelectionModel = ItemSelectionModel()
    
    var body: some View {
        GroupBoxTV(isCard: true) {
            VStack {
                ViewThatFits {
                    HStack {
                        selectedView
                        root.adventureRoot.viewController.selectionView(root: root.adventureRoot, model: selection)
                    }

                    VStack {
                        selectedView
                        Divider()
                        root.adventureRoot.viewController.selectionView(root: root.adventureRoot, model: selection)
                    }
                }
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
            }
        }
        .onChange(of: root.gameModel.selectedAdventure) {
            if let adventureId = root.gameModel.selectedAdventure {
                lastAdventureUUID <=> adventureId.uuidString
            }
        }
        .onChange(of: selection.itemId, initial: false) {
            root.gameModel.selectedAdventure <=> selection.itemId
        }
    }

    private var selectedView: some View {
        VStack {
            if let id = root.gameModel.selectedAdventure {
//                root.viewController.selectedAdventureView(with: id)
//                    .id(id)
            } else {
                Text("Select an adventure for the current game to enjoy the focused adventure view during the game. The adventure itself can be empty and changed during the game.", bundle: .module)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
