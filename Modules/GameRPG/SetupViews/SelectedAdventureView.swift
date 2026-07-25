// @copyright André Trettin

import AdventureRPG
import CoreRPG
import SwiftUI
import TipKit

struct SelectedAdventureView: View {
    let root: GameRoot

    @AppStorage("lastAdventureUUID", store: .standard)
    private var lastAdventureUUID: String = ""

    @State private var selection: ItemSelectionModel = ItemSelectionModel()
    
    var body: some View {
        GroupBoxTV(isCard: true) {
#if os(tvOS)
            VStack {
                TipView(MasterRPGTips.chooseAdventure)
                adventureSelection
            }
#else
            adventureSelection
                .popoverTip(MasterRPGTips.chooseAdventure)
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
        .task {
            root.resetSelectedAdventure(uuidString: lastAdventureUUID)
            selection.resetSelection(itemId: root.gameModel.selectedAdventure, entryId: nil)
            updateTipSelection(root.gameModel.selectedAdventure)
        }
        .onChange(of: lastAdventureUUID, initial: true) {
            root.gameModel.selectedAdventure <=> selection.itemId
        }
        .onChange(of: selection.itemId) {
            root.gameModel.selectedAdventure <=> selection.itemId
        }
        .onChange(of: root.gameModel.selectedAdventure) { _, newAdventure in
            if let adventureId = newAdventure {
                selection.resetSelection(itemId: adventureId, entryId: nil)
                lastAdventureUUID <=> adventureId.uuidString
            }
            updateTipSelection(newAdventure)
        }
    }

    private var adventureSelection: some View {
        root.adventureRoot.viewController.dropChooseView(model: selection)
            .frame(maxWidth: .infinity)
#if os(macOS)
            .padding()
#endif
    }

    private func updateTipSelection(_ adventureID: UUID?) {
        MasterRPGTips.setSelectedAdventure(adventureID != nil)
        guard adventureID != nil else { return }
        Task {
            await MasterRPGTips.donateAdventureSelected()
        }
    }
}

#Preview { SelectedAdventureView(root: .preview) }
