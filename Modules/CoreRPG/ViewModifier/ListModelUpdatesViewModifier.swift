// @copyright André Trettin

import CoreExternalRPG
import SwiftUI

extension View {
    func listModelUpdatesModifier(listControllable: any ListControllable, parentModel: ItemDataModel?) -> some View {
        modifier(ListModelUpdatesViewModifier(listControllable: listControllable, parentModel: parentModel))
    }
}

struct ListModelUpdatesViewModifier: ViewModifier {
    let listControllable: any ListControllable
    let parentModel: ItemDataModel?
    
    @Environment(\.navigator) private var navigator
    
#if os(iOS) || os(visionOS)
    @State private var editMode: EditMode = .inactive
#endif
    
    func body(content: Content) -> some View {
        content
#if os(iOS) || os(visionOS)
            .environment(\.editMode, $editMode)
#endif
            .onChange(of: listModel.listSelection) {
                withAnimation {  updateListSelection() }
            }
            .onChange(of: listModel.selected) {
                withAnimation { updateSelected() }
            }
            .onChange(of: listControllable.listDisplayModel.listMode) {
                withAnimation { listControllable.resetFilter(parentModel: parentModel) }
            }
            .onChange(of: listControllable.listDisplayModel.isSelectionMode) {
                withAnimation { listModel.update(selectionMode: listControllable.listDisplayModel.isSelectionMode) }
#if os(iOS) || os(visionOS)
                withAnimation { editMode = listControllable.listDisplayModel.isSelectionMode ? .active : .inactive }
#endif
            }
    }
}

private extension ListModelUpdatesViewModifier {
    var listModel: ListModel {
        listControllable.listModel(for: parentModel)
    }

    var displayItems: [ListItemModel] {
        listControllable.displayItems(for: parentModel)
    }

    func updateListSelection() {
        listModel.update(selection: listModel.listSelection)
    }

    func updateSelected() {
        if let id = listModel.selected {
            listModel.listSelection <=> Set(arrayLiteral: id)
        } else {
            listModel.resetListSelection()
        }
    }
}
