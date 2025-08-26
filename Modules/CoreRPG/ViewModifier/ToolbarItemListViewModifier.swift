// @copyright André Trettin

import SwiftData
import SwiftUI

extension View {
    func toolbarItemListModifier(root: any ItemRootControllable, parentModel: ItemDataModel?) -> some View {
        modifier(ToolbarItemListViewModifier(root: root, parentModel: parentModel))
    }
}

struct ToolbarItemListViewModifier: ViewModifier {
    let root: any ItemRootControllable
    let parentModel: ItemDataModel?

    @Environment(\.modelContext) private var modelContext

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
                        addItemButton(for: .item)
                    }
                }
            }
    }
}

private extension ToolbarItemListViewModifier {
    var listController: any ListControllable {
        root.listControllable
    }

    var listModel: ListModel {
        listController.listModel(for: parentModel)
    }

    var listDisplayModel: ListDisplayModel {
        listController.listDisplayModel
    }

    @ViewBuilder
    var actionMenu: some View {
        Menu {
            MenuDisplayModeToggle(listDisplayModel: listDisplayModel, showSelectionButton: false) {
                if parentModel == nil {
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
        if !listDisplayModel.isSelectionMode {
            MenuSelectionButtonView(listDisplayModel: listDisplayModel)
        }
        ControlGroup {
            addItemButton(for: .folder)
            addItemButton(for: .collection)
        }
        .disabled(listDisplayModel.isListMode)

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

    var secondaryMenuPlacement: ToolbarItemPlacement {
#if os(tvOS)
        .automatic
#else
        .secondaryAction
#endif
    }
}
