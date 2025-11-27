// @copyright André Trettin

import AndrenalinKit
import SwiftUI
import RPGValues

struct UpdateMapPinEditor: View {
    let editController: EditController
    let entryId: UUID?
    let pinId: UUID?
    
    @Environment(MapRootModel.self) private var root
    @Environment(SelectionSheetLinkModel.self) private var selectionModel
    
    @State private var characterPinId: UUID?

    var body: some View {
        Button {
            selectionModel.selectionView = AnyView(showCharakterSelectionView())
            withAnimation { selectionModel.selection = true }
        } label: {
            Label {
                Text("Pin from Charakter / Monster", bundle: .module)
            } icon: {
                Image(systemName: NetworkModules.value.icon)
            }
        }
    }
    
    private func showCharakterSelectionView() -> some View {
        root.valueRoot.viewController.viewSelect(root: root.valueRoot) {
            if let characterPinId {
                return [ItemRowModel(itemId: characterPinId, typeId: .value)]
            }
            return []
        } toggleSelection: { selection, _ in
            if selection.itemId == characterPinId {
                characterPinId = nil
            } else {
                characterPinId = selection.itemId
            }
        } dismissAction: {
            if let characterPinId {
                withAnimation {
                    if let pinId {
                        editController.replacePinData(pinId: pinId, with: characterPinId)
                    }
                    if let entryId {
                        editController.addMonsters(to: entryId, monsters: [ItemRowModel(itemId: characterPinId, typeId: .value)], number: 1)
                    }
                }
                self.characterPinId = nil
            }
            selectionModel.selection = false
        }
    }
}

#Preview {
    UpdateMapPinEditor(editController: .preview, entryId: nil, pinId: UUID())
}
