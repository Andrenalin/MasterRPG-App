// @copyright André Trettin

import CoreRPG
import SwiftUI
import CharacterRPG

struct ChooseMasterView: View {
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
        root.valueRoot.viewController.viewSelectMasters(root: root.valueRoot) {
            if let id = root.gameModel.selectedGameMaster, let gameMasterId = root.valueRoot.linkController.validate(id: id, isGameMaster: true) {
                return [ItemRowModel(itemId: gameMasterId, typeId: .value)]
            }
            return []
        } toggleSelection: { model, _ in
            if let itemId = root.valueRoot.linkController.validate(id: model.itemId, isGameMaster: true), root.gameModel.selectedGameMaster != itemId {
                root.gameModel.selectedGameMaster <=> itemId
            } else {
                root.gameModel.selectedGameMaster = nil
            }
        } dismissAction: {
            selectionSheetLinkModel.selection = false
        }
    }

    private var dropView: some View {
        Group {
            Text("Drop Game Master here", bundle: .module)
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
        guard link.module == .value, let gameMasterId = root.valueRoot.linkController.validate(id: link.itemId, isGameMaster: true) else { return false }
        withAnimation {
            root.gameModel.selectedGameMaster = gameMasterId
        }
        return true
    }
}
