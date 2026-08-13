// @copyright André Trettin

import AdventureRPG
import CoreRPG
import MapRPG
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
                adventureSelection
            }
#else
            Group {
                if isCompactLayout {
                    VStack(alignment: .leading, spacing: 12) {
                        adventureSelection
                        optionView
                    }
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        adventureSelection
                    }
                    .overlay(alignment: .trailing) {
                        optionView
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
#if os(macOS)
            .padding()
#endif
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
    
    @ViewBuilder
    var optionView: some View {
        if isCompactLayout {
            // Phone width: Import/Play stack together as one leading
            // column, a spacer opens up the row, and the code button forms
            // its own trailing column, bottom-aligned against the column.
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    importOrClearButton
#if !os(tvOS)
                    if root.gameModel.selectedAdventure != nil {
                        sharePlayButton
                    }
#endif
                }
#if !os(tvOS)
                if root.gameModel.selectedAdventure != nil {
                    Spacer()
                    masterJoinCodeButton
                }
#endif
            }
            .padding(12)
        } else {
            // iPad/Mac/visionOS width: this block is itself pinned to the
            // card's trailing edge (see the `.overlay(alignment: .trailing)`
            // above), so its own options align trailing too instead of
            // hugging the block's leading edge.
            VStack(alignment: .trailing, spacing: 12) {
                importOrClearButton
#if !os(tvOS)
                if root.gameModel.selectedAdventure != nil {
                    sharePlayButton
                    masterJoinCodeButton
                }
#endif
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private var importOrClearButton: some View {
        if hasMapGameItems {
            Button {
                clearMapGameItems()
            } label: {
                Label { Text("Clear Saved Game", bundle: .module) } icon: { Image(systemName: "trash") }
            }
        } else {
            Button {
                navigator.navigate(to: ImportRoute.importGame, method: .managedSheet)
            } label: {
                Label { Text("Import Saved Game", bundle: .module) } icon: { Image(systemName: "square.and.arrow.down") }
            }
        }
    }

#if !os(tvOS)
    private var sharePlayButton: some View {
        SharePlayButton("Play RPG Online", activity: RPGActivity())
            .opacity(sharePlayStore.canActivateSharePlay ? 0 : 1)
            .allowsHitTesting(!sharePlayStore.canActivateSharePlay)
            .accessibilityHidden(sharePlayStore.canActivateSharePlay)
    }

    private var masterJoinCodeButton: some View {
        @Bindable var gameJoinCodeModel = root.gameJoinCodeModel
        return GameJoinCodeSetupButton(title: "Game Master Code", code: $gameJoinCodeModel.masterCode)
    }
#endif

    private var hasMapGameItems: Bool {
        !root.mapRoot.gameControllable.gameModel.items.isEmpty
    }

    private func clearMapGameItems() {
        let mapGameControllable = root.mapRoot.gameControllable
        Task {
            await mapGameControllable.reset()
        }
    }
}

#Preview(traits: .mockData) {
    SelectedAdventureView(root: .preview)
        .setAppSizeMode()
}
