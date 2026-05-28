// @copyright André Trettin

import SwiftUI

extension View {
    public func toolbarItemListModifier(root: any ItemRootControllable, listControllable: any FolderListControllable, parentModel: (any ItemDataAccessable)?, modal: Bool = false, dismissHandler: (() -> Void)? = nil) -> some View {
        modifier(ToolbarItemListViewModifier(root: root, listController: listControllable, parentModel: parentModel, modal: modal, dismissHandler: dismissHandler))
    }
}

struct ToolbarItemListViewModifier: ViewModifier {
    let root: any ItemRootControllable
    let listController: any FolderListControllable
    let parentModel: (any ItemDataAccessable)?
    let modal: Bool
    let dismissHandler: (() -> Void)?

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
#if os(visionOS)
                        .foregroundStyle(.primary)
#endif
                }
#endif
                // Single stable ToolbarItem — avoids _ConditionalContent in the preference tree
                // which would cause a deep AG graph traversal on every navigation transition.
                ToolbarItem(placement: .primaryAction) {
                    if listDisplayModel.isSelectionMode && modal == false {
                        MenuSelectionButtonView(listDisplayModel: listDisplayModel)
#if os(visionOS)
                            .foregroundStyle(.primary)
#endif
                    } else if modal == false || (parentModel != nil && parentModel!.specialCategory) {
                        addItemButton(for: .item)
#if os(visionOS)
                            .foregroundStyle(.primary)
#endif
                    }
                }

#if !os(macOS)
                ToolbarItem(placement: .confirmationAction) {
                    if modal == true {
                        dismissButton
#if os(visionOS)
                            .foregroundStyle(.primary)
#endif
                    }
                }
#endif
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
                } else if let parentModel, parentModel.specialCategory && modal == false {
                    // For special categories (folder/collection), show appropriate add buttons
                    if parentModel.category == .folder {
                        addItemButton(for: .folder)
                        addItemButton(for: .collection)
                    } else if parentModel.category == root.itemControllable.collectionCategory {
                        // Collections cannot contain folders
                        addItemButton(for: .collection)
                    }
                    Divider()
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    @ViewBuilder
    var secondaryActionMenu: some View {
        // Use opacity/hidden instead of conditional presence to keep the toolbar preference
        // tree stable across selection mode changes and navigation transitions.
        MenuSelectionButtonView(listDisplayModel: listDisplayModel)
            .opacity(!listDisplayModel.isSelectionMode && modal == false ? 1 : 0)
        if parentModel == nil && modal == false {
            ControlGroup {
                addItemButton(for: .item)
                addItemButton(for: .folder)
                    .disabled(parentModel?.category == root.itemControllable.collectionCategory)
                addItemButton(for: .collection)
            }
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

            if modal == false {
                ControlGroup {
                    toggleFolder()
                }
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
            } else {
                listController.add(model: newModel)
            }
        }
    }
    
    var dismissButton: some View {
        Button {
            dismissHandler?()
            dismiss()
        } label: {
            Image(systemName: "checkmark")
        }
    }
}
