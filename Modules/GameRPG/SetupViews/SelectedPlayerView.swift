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

    private var isCompactLayout: Bool {
        appSizeModel.mode == .compact
    }

    var body: some View {
        GroupBoxTV(isCard: true, withoutGroup: true) {
#if os(tvOS)
            VStack {
                TipView(MasterRPGTips.chooseCharacter)
                SelectedPlayerViewCharacterSelectionView(root: root, selection: selection)
            }
#else
            Group {
                if isCompactLayout {
                    VStack(alignment: .leading, spacing: 12) {
                        SelectedPlayerViewCharacterSelectionView(root: root, selection: selection)
                        
                        if root.gameModel.selectedCharacter != nil {
                            SelectedPlayerViewSharePlayStartView(root: root, isCompactLayout: isCompactLayout)
                        }
                    }
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        SelectedPlayerViewCharacterSelectionView(root: root, selection: selection)
                    }
                    .overlay(alignment: .trailing) {
                        if root.gameModel.selectedCharacter != nil {
                            SelectedPlayerViewSharePlayStartView(root: root, isCompactLayout: isCompactLayout)
                        }
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
#if os(macOS)
            .padding()
#endif
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

    private func updateTipSelection(_ characterID: UUID?) {
        MasterRPGTips.setSelectedCharacter(characterID != nil)
        guard characterID != nil else { return }
        Task {
            await MasterRPGTips.donateCharacterSelected()
        }
    }
}

// MARK: - Extracted subviews (CODE_AUDIT §8.3)

private struct SelectedPlayerViewCharacterSelectionView: View {
    let root: GameRoot
    let selection: ItemSelectionModel

    @ViewBuilder
    var body: some View {
        root.characterRoot.viewController.dropChooseView(model: selection)
            .frame(maxWidth: .infinity)
#if os(macOS)
            .padding()
#endif
    }
}

private struct SelectedPlayerViewSharePlayStartView: View {
    let root: GameRoot
    let isCompactLayout: Bool

    var body: some View {
        // A phone-width layout lines the SharePlay and code buttons up in
        // one row, with a spacer opening up the space between them, instead
        // of stacking them so the card stays compact.
        let layout: AnyLayout = isCompactLayout
            ? AnyLayout(HStackLayout(spacing: 12))
            : AnyLayout(VStackLayout(alignment: .trailing, spacing: 12))

        return layout {
#if !os(tvOS)
            GameSharePlayButton(root: root)
            if isCompactLayout {
                Spacer()
            }
            SelectedPlayerViewPlayerJoinCodeButtonView(root: root)
#endif
        }
        .padding(12)
    }
}

#if !os(tvOS)

private struct SelectedPlayerViewPlayerJoinCodeButtonView: View {
    let root: GameRoot

    var body: some View {
        @Bindable var gameJoinCodeModel = root.gameJoinCodeModel
        return GameJoinCodeSetupButton(title: "Your Player Code", code: $gameJoinCodeModel.playerCode)
    }
}
#endif

#Preview(traits: .mockData) {
    SelectedPlayerView(root: .preview)
}
