// @copyright André Trettin

import SwiftUI

struct ItemListToolBarViewModifier: ViewModifier {
    let listController: any ListControllable
    let itemListConfiguration: ItemListConfiguration
    let childrenConfiguration: ItemListChildrenConfiguration

    func body(content: Content) -> some View {
        content
            .toolbar {
                #if !os(macOS)
                if itemListConfiguration.canAdd && childrenConfiguration.canNavigate {
                    ToolbarItem(id: "Add\(itemListModel.listTitleName)", placement: .navigation) {
                        ItemListAddNewButton(listController: listController, canAdd: true)
                    }
                }
                #endif

                if itemListConfiguration.modalOk {
                    ToolbarItem(id: "CloseOk\(itemListModel.listTitleName)", placement: primaryPlacement) {
                        ModalCloseOkButton(dismissAction: itemListConfiguration.modalDismissAction)
                    }
                }
                if itemListConfiguration.modal {
                    ToolbarItem(id: "Close\(itemListModel.listTitleName)", placement: .navigation) {
                        ModalCloseButton(dismissAction: itemListConfiguration.modalDismissAction)
                    }
                }
                if itemListModel.selectionMode == nil {
                    ToolbarItem(id: "Edit\(itemListModel.listTitleName)", placement: .navigation) {
                        selectModeView
                    }
                }
            }
            .toolbarRole(.automatic)
            .toolbar(itemListModel.showGeneratorItem == nil ? .visible : .hidden, for: toolBarPlacement)
    }

    var itemListModel: ListModel {
        listController.model
    }

    var toolBarPlacement: ToolbarPlacement {
#if os(macOS)
        .automatic
#else
        .navigationBar
#endif
    }

    var primaryPlacement: ToolbarItemPlacement {
#if os(macOS)
        .automatic
#else
        .primaryAction
#endif
    }

    @ViewBuilder
    var selectModeView: some View {
        if childrenConfiguration.canNavigate {
#if os(iOS) || os(visionOS)
            EditButton()
#else
            EmptyView()
#endif
        } else {
            Button {
                withAnimation {
                    listController.model.selectedItems = []
                    listController.model.allowEditing.toggle()
                }
            } label: {
                if listController.model.allowEditing {
                    Text("Done", bundle: .module)
                } else {
                    Text("Edit", bundle: .module)
                }
            }
        }
    }
}

struct ItemListAddNewButton: View {
    let listController: any ListControllable
    let canAdd: Bool

    var body: some View {
        if canAdd {
            Button {
                Task {
                    await listController.addNew()
                }
            } label: {
                Label { Text("Add", bundle: .module) } icon: { Image(systemName: "plus") }
            }
        } else {
            EmptyView()
        }
    }
}
