// @copyright André Trettin

import AdventureRPG
import CoreRPG
import MapRPG
import SwiftUI
import TipKit

struct SelectedAdventureView: View {
    let root: GameRoot

    @AppStorage(GameStorageKeys.lastAdventureUUID, store: .standard)
    private var lastAdventureUUID: String = ""

    @Environment(AppWindowSizeModel.self) private var appSizeModel

    @State private var selection: ItemSelectionModel = ItemSelectionModel()

    private var isCompactLayout: Bool {
        appSizeModel.mode == .compact
    }

    var body: some View {
        GroupBoxTV(isCard: true, withoutGroup: true) {
#if os(tvOS)
            VStack {
                TipView(MasterRPGTips.chooseAdventure)
                SelectedAdventureViewAdventureSelectionView(root: root, selection: selection)
            }
#else
            Group {
                if isCompactLayout {
                    VStack(alignment: .leading, spacing: 12) {
                        SelectedAdventureViewAdventureSelectionView(root: root, selection: selection)
                        SelectedAdventureViewOptionView(root: root, isCompactLayout: isCompactLayout)
                    }
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        SelectedAdventureViewAdventureSelectionView(root: root, selection: selection)
                    }
                    .overlay(alignment: .trailing) {
                        SelectedAdventureViewOptionView(root: root, isCompactLayout: isCompactLayout)
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
    
    private func updateTipSelection(_ adventureID: UUID?) {
        MasterRPGTips.setSelectedAdventure(adventureID != nil)
        guard adventureID != nil else { return }
        Task {
            await MasterRPGTips.donateAdventureSelected()
        }
    }
}

// MARK: - Extracted subviews (CODE_AUDIT §8.3)

private struct SelectedAdventureViewAdventureSelectionView: View {
    let root: GameRoot
    let selection: ItemSelectionModel

    var body: some View {
        root.adventureRoot.viewController.dropChooseView(model: selection)
            .frame(maxWidth: .infinity)
#if os(macOS)
            .padding()
#endif
    }
}

private struct SelectedAdventureViewOptionView: View {
    let root: GameRoot
    let isCompactLayout: Bool

    @ViewBuilder
    var body: some View {
        if isCompactLayout {
            // Phone width: Import/Play stack together as one leading
            // column, a spacer opens up the row, and the code button forms
            // its own trailing column, bottom-aligned against the column.
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    SelectedAdventureViewImportOrClearButtonView(root: root)
#if !os(tvOS)
                    if root.gameModel.selectedAdventure != nil {
                        GameSharePlayButton(root: root)
                    }
#endif
                }
#if !os(tvOS)
                if root.gameModel.selectedAdventure != nil {
                    Spacer()
                    SelectedAdventureViewMasterJoinCodeButtonView(root: root)
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
                SelectedAdventureViewImportOrClearButtonView(root: root)
#if !os(tvOS)
                if root.gameModel.selectedAdventure != nil {
                    GameSharePlayButton(root: root)
                    SelectedAdventureViewMasterJoinCodeButtonView(root: root)
                }
#endif
            }
            .padding(12)
        }
    }
}

private struct SelectedAdventureViewImportOrClearButtonView: View {
    let root: GameRoot

    @Environment(\.navigator) private var navigator

    @ViewBuilder
    var body: some View {
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

    private var hasMapGameItems: Bool {
        !root.mapRoot.gameControllable.gameModel.items.isEmpty
    }

    /// Clears the saved game from every module, not only maps: the other modules kept their
    /// staged copies (and files) until the next game. See CODE_AUDIT_Folder §5.25.
    private func clearMapGameItems() {
        let adventureGameControllable = root.adventureRoot.adventureGameControllable
        Task {
            await adventureGameControllable.resetGame()
        }
    }
}

#if !os(tvOS)

private struct SelectedAdventureViewMasterJoinCodeButtonView: View {
    let root: GameRoot

    var body: some View {
        @Bindable var gameJoinCodeModel = root.gameJoinCodeModel
        return GameJoinCodeSetupButton(title: "Game Master Code", code: $gameJoinCodeModel.masterCode)
    }
}
#endif

#Preview(traits: .mockData) {
    SelectedAdventureView(root: .preview)
        .setAppSizeMode()
}
