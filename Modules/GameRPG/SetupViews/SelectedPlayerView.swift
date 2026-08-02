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

    @Environment(AppWindowSizeModel.self) private var appSizeModel
    
    @Environment(\.navigator) private var navigator

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
                TipView(MasterRPGTips.chooseCharacter)
                characterSelection
            }
#else
            Group {
                if isCompactLayout {
                    VStack(alignment: .leading, spacing: 12) {
                        characterSelection
                    }
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        characterSelection
                    }
                }
            }
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
        .themedSurface()
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

    @ViewBuilder private var characterSelection: some View {
        root.characterRoot.viewController.dropChooseView(model: selection)
            .frame(maxWidth: .infinity)
#if os(macOS)
            .padding()
#endif
        
        if root.gameModel.selectedCharacter != nil {
            sharePlayStart
        }

    }

    private func updateTipSelection(_ characterID: UUID?) {
        MasterRPGTips.setSelectedCharacter(characterID != nil)
        guard characterID != nil else { return }
        Task {
            await MasterRPGTips.donateCharacterSelected()
        }
    }

    var sharePlayStart: some View {
        VStack(alignment: .trailing, spacing: 12) {
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
    SelectedPlayerView(root: .preview)
}
