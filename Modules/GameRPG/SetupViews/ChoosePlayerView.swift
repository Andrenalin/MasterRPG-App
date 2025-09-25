// @copyright André Trettin

import CoreRPG
import CharacterRPG
import SwiftUI

struct ChoosePlayerView: View {
    let root: GameRootController

#if !os(tvOS)
    @Environment(\.openWindow) private var openWindow
#endif

    @State private var dropBackgroundColor: Color = .clear
    @State private var dropForegroundColor: Color = .primary

    var body: some View {
        HStack {
#if os(macOS)
            dropView
#endif
            Button {
                withAnimation {
#if os(macOS)
                    openWindow(id: NetworkModules.value.linkWindowId)
#else
                    selectionSheetLinkModel.selectionView = AnyView(selectionView)
                    selectionSheetLinkModel.selection = true
#endif
                }

            } label: {
                Label { Text("Choose", bundle: .module) } icon: { Image(systemName: NetworkModules.value.icon) }
            }
        }
        .frame(maxWidth: .infinity)
#if os(macOS)
        .padding()
#endif
    }

    private var selectionView: some View {
        root.valueRoot.viewController.viewSelectCharacters {
            if let id = root.gameModel.selectedCharacter, let characterId = root.valueRoot.linkController.validate(id: id, isCharacter: true) {
                return [ItemRowModel(itemId: characterId, typeId: .value)]
            }
            return []
        } toggleSelection: { model, _ in
            if let itemId = root.valueRoot.linkController.validate(id: model.itemId, isCharacter: true), root.gameModel.selectedCharacter != itemId {
                root.gameModel.selectedCharacter <=> itemId
            } else {
                root.gameModel.selectedCharacter = nil
            }
        } dismissAction: {
            selectionSheetLinkModel.selection = false
        }
    }

    private var dropView: some View {
        Group {
            Text("Drop Character here", bundle: .module)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .foregroundStyle(dropForegroundColor)
        .background {
            RoundedRectangle(cornerRadius: 8).fill(dropBackgroundColor)
        }
#if !os(tvOS)
        .dropDestination(for: LinkData.self) { items, _ in
            guard let draggedLinkData = items.first else { return false }
            return drop(link: draggedLinkData)
        } isTargeted: { inDropArea in
            dropBackgroundColor = inDropArea ? .accentColor : .clear
            dropForegroundColor = inDropArea ? .white : .primary
        }
#endif
    }

    private func drop(link: LinkData) -> Bool {
        guard link.module == .value, let characterId = root.valueRoot.linkController.validate(id: link.itemId, isCharacter: true) else { return false }
        withAnimation {
            root.gameModel.selectedCharacter = characterId
        }
        return true
    }
}
