// @copyright André Trettin

import SwiftData
import SwiftUI

extension View {
    func toolbarItemListModifier(root: any ItemRootControllable, listControllable: any ListControllable, parentModel: ItemDataModel?, modal: Bool = false) -> some View {
        modifier(ToolbarItemListViewModifier(root: root, listController: listControllable, parentModel: parentModel, modal: modal))
    }
}

struct ToolbarItemListViewModifier: ViewModifier {
    let root: any ItemRootControllable
    let listController: any ListControllable
    let parentModel: ItemDataModel?
    let modal: Bool

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    

    func body(content: Content) -> some View {
        content
            .toolbar {
#if os(macOS)
                ToolbarItem(placement: .secondaryAction) {
                    actionMenu
                }
#else
                ToolbarItemGroup(placement: secondaryMenuPlacement) {
                    secondaryActionMenu
                }
#endif
                if listDisplayModel.isSelectionMode {
                    ToolbarItem(placement: .primaryAction) {
                        MenuSelectionButtonView(listDisplayModel: listDisplayModel)
                    }
                } else {
                    ToolbarItem(placement: .primaryAction) {
                        if modal == false {
                            addItemButton(for: .item)
                        }
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    if modal == true {
                        dismissButton
                    }
                }
            }
    }
}

private extension ToolbarItemListViewModifier {
    var listModel: ListModel {
        listController.listModel(for: parentModel)
    }

    var listDisplayModel: ListDisplayModel {
        listController.listDisplayModel
    }

    @ViewBuilder
    var actionMenu: some View {
        Menu {
            MenuDisplayModeToggle(listDisplayModel: listDisplayModel, showSelectionButton: false, modal: modal) {
                if parentModel == nil && modal == false {
                    addItemButton(for: .folder)
                        .disabled(listDisplayModel.isListMode)
                    addItemButton(for: .collection)
                        .disabled(listDisplayModel.isListMode)
                    Divider()
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    @ViewBuilder
    var secondaryActionMenu: some View {
        if !listDisplayModel.isSelectionMode && modal == false {
            MenuSelectionButtonView(listDisplayModel: listDisplayModel)
        }
        if modal == false {
            ControlGroup {
                addItemButton(for: .folder)
                addItemButton(for: .collection)
            }
            .disabled(listDisplayModel.isListMode)
        }
        ControlGroup {
            CompactDisplayModeToggle(listDisplayModel: listDisplayModel)
            MediumDisplayModeToggle(listDisplayModel: listDisplayModel)
            RegularDisplayModeToggle(listDisplayModel: listDisplayModel)
        }
        if parentModel == nil {
            ControlGroup {
                ListModeToggle(listDisplayModel: listDisplayModel)
                FolderModeToggle(listDisplayModel: listDisplayModel)
            }
        }
    }

    func addItemButton(for type: EditControllerAddType) -> some View {
        Button {
            addItem(for: type)
        } label: {
            Label {
                Text(type.title)
            } icon: {
                Image(systemName: type.icon(collection: root.itemControllable.collectionCategory.icon))
            }
        }
    }

    func addItem(for type: EditControllerAddType) {
        let newModel = root.editControllable.addNew(modelContext: modelContext, module: root.module, type: type)
        withAnimation {
            if parentModel != nil {
                root.editControllable.addItem(itemId: newModel.id, in: modelContext, parentId: listModel.selectedParentId, folderId:  listModel.lastFolderId)
            }
            listController.add(model: newModel)
        }
    }
    
    var dismissButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "checkmark")
        }
    }

    var secondaryMenuPlacement: ToolbarItemPlacement {
#if os(tvOS)
        .automatic
#else
        .secondaryAction
#endif
    }
}
