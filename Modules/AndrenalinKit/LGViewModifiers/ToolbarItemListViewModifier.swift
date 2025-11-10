// @copyright André Trettin

import SwiftData
import SwiftUI

extension View {
    func toolbarItemListModifier(root: any ItemRootControllable, listControllable: any FolderListControllable, parentModel: (any ItemDataAccessable)?, modal: Bool = false) -> some View {
        modifier(ToolbarItemListViewModifier(root: root, listController: listControllable, parentModel: parentModel, modal: modal))
    }
}

struct ToolbarItemListViewModifier: ViewModifier {
    let root: any ItemRootControllable
    let listController: any FolderListControllable
    let parentModel: (any ItemDataAccessable)?
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
                ToolbarItemGroup(placement: .secondaryActionAll) {
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
    var listModel: FolderListModel {
        listController.listModel
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
                    
                    toggleFolder()
                        .disabled(listModel.selected == nil)

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
            
            ControlGroup {
                toggleFolder()
            }
        }
    }

    func toggleFolder() -> some View {
        Button {
            if let selected = listModel.selected, let item = listController.displayItems.first(where: { $0.id == selected }) {
                listController.toggleFolder(item: item)
            }
        } label: {
            Label {
                Text("Toggle Folder", bundle: .module)
            } icon: {
                Image(systemName: "list.bullet.indent")
            }
        }
#if !os(tvOS)
        .keyboardShortcut(.leftArrow, modifiers: [.command, .shift])
#endif
    }

    func addItemButton(for type: EditControllerAddType) -> some View {
        Button {
            Task {
                await addItem(for: type)
            }
        } label: {
            Label {
                Text(type.title)
            } icon: {
                Image(systemName: type.icon(collection: root.itemControllable.collectionCategory.icon))
            }
        }
    }

    func addItem(for type: EditControllerAddType) async {        
        guard let newModel = await root.editControllable.addNew(type: type) else { return }
        withAnimation {
            if parentModel != nil {
                root.editControllable.addItem(itemId: newModel.id, parentId: listModel.selectedParentId)
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
}
