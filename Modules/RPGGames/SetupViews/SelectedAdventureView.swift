// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct SelectedAdventureView: View {
    let root: GameRoot

    @AppStorage("lastAdventureUUID", store: .standard)
    private var lastAdventureUUID: String = ""

    var body: some View {
        GroupBoxTV(isCard: true) {
            VStack {
                ViewThatFits {
                    HStack {
                        selectedView
                        ChooseAdventureView(root: root)
                    }

                    VStack {
                        selectedView
                        Divider()
                        ChooseAdventureView(root: root)
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
    }

    private var selectedView: some View {
        VStack {
            if let id = root.gameModel.selectedAdventure {
                root.viewController.selectedAdventureView(with: id)
                    .id(id)
            } else {
                Text("Select an adventure for the current game to enjoy the focused adventure view during the game. The adventure itself can be empty and changed during the game.", bundle: .module)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
