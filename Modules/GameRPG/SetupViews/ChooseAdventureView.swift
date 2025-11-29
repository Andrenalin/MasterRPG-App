// @copyright André Trettin

import CoreRPG
import SwiftUI
import AdventureRPG

struct ChooseAdventureView: View {
    let root: GameRoot

#if !os(tvOS)
    @Environment(\.openWindow) private var openWindow
#endif
    @Environment(SelectionSheetLinkModel.self) private var selectionSheetLinkModel

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
                    openWindow(id: NetworkModules.adventure.linkWindowId)
#else
                    selectionSheetLinkModel.selectionView = AnyView(selectionView)
                    selectionSheetLinkModel.selection = true
#endif
                }

            } label: {
                Label { Text("Choose", bundle: .module) } icon: { Image(systemName: NetworkModules.adventure.icon) }
            }
        }
        .frame(maxWidth: .infinity)
#if os(macOS)
        .padding()
#endif
    }

    private var selectionView: some View {
        root.adventureRoot.viewController.viewSelect(root: root.adventureRoot) {
            if let id = root.gameModel.selectedAdventure, root.adventureRoot.linkController.validateLink(itemId: id) == true {
                return [ItemRowModel(itemId: id, typeId: .adventure)]
            }
            return []
        } toggleSelection: { model, _ in
            if root.adventureRoot.linkController.validateLink(itemId: model.itemId) && root.gameModel.selectedAdventure != model.itemId {
                root.gameModel.selectedAdventure <=> model.itemId
            } else {
                root.gameModel.selectedAdventure = nil
            }
        } dismissAction: {
            selectionSheetLinkModel.selection = false
        }
    }

    private var dropView: some View {
        Group {
            Text("Drop Adventure here", bundle: .module)
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
        guard link.module == .adventure, root.adventureRoot.linkController.validateLink(itemId: link.itemId) else { return false }
        withAnimation { root.gameModel.selectedAdventure <=> link.itemId }
        return true
    }
}
