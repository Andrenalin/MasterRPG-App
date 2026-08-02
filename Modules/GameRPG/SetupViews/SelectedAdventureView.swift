// @copyright André Trettin

import AdventureRPG
import CoreRPG
import SwiftUI
import TipKit

struct SelectedAdventureView: View {
    let root: GameRoot

    @AppStorage("lastAdventureUUID", store: .standard)
    private var lastAdventureUUID: String = ""

    @Environment(AppWindowSizeModel.self) private var appSizeModel
    @Environment(\.navigator) private var navigator


    @State private var selection: ItemSelectionModel = ItemSelectionModel()

    private var sharePlayStore: RPGSharePlayController {
        root.networkStore.sharePlayStore
    }

    private var isCompactLayout: Bool {
        appSizeModel.mode == .compact
    }

    var body: some View {
        GroupBoxTV(isCard: true, withoutGroup: true) {
#if os(tvOS)
            VStack {
                TipView(MasterRPGTips.chooseAdventure)
                content
            }
#else
            Group {
                if isCompactLayout {
                    VStack(alignment: .leading, spacing: 12) {
                        content
                    }
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        content
                    }
                }
            }
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
        .themedSurface()
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
    
    @ViewBuilder private var content: some View {
        adventureSelection
        if root.gameModel.selectedAdventure != nil {
            optionView
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
    
    var optionView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                navigator.navigate(to: ImportRoute.importGame, method: .managedSheet)
            } label: {
                Label { Text("Import Saved Game", bundle: .module) } icon: { Image(systemName: "square.and.arrow.down") }
            }

#if !os(tvOS)
            SharePlayButton("Play RPG Online", activity: RPGActivity())
                .opacity(sharePlayStore.canActivateSharePlay ? 0 : 1)
                .allowsHitTesting(!sharePlayStore.canActivateSharePlay)
                .accessibilityHidden(sharePlayStore.canActivateSharePlay)
#endif
        }
        .padding(12)
    }

}

#Preview(traits: .mockData) {
    SelectedAdventureView(root: .preview)
        .setAppSizeMode()
}
