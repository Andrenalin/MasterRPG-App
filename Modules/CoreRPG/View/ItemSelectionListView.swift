// @copyright André Trettin

import CoreExternalRPG
import SwiftData
import SwiftUI

public struct ItemSelectionListView<ListController: ListControllable, Row: View>: View where ListController.Model.ID == UUID {
    public init(listController: ListController, parentModel: ListController.Model? = nil, module: NetworkModules, route: @escaping (UUID) -> any NavigationDestination, @ViewBuilder row: @escaping (UUID) -> Row) {
        self.listController = listController
        self.module = module
        self.route = route
        self.row = row
    }
    let listController: ListController
    let module: NetworkModules
    let route: (UUID) -> any NavigationDestination
    let row: (UUID) -> Row
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.navigator) private var navigator

    @Environment(CacheItemListModel.self) private var cacheItemListModel
    @Environment(ListDisplayModel.self) private var listDisplayModel

#if os(iOS) || os(visionOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif
    
    public var body: some View {
        listView
            .frame(minWidth: 250, idealWidth: 350)
            .overlay {
                if listModel.displayedItems.isEmpty && !listController.searchModel.searchText.isEmpty {
                    ContentUnavailableView.search
                }
            }
            .animation(.smooth, value: listModel.displayedItems.count)
            .scrollIndicatorsFlash(onAppear: true)
            .scrollIndicatorsFlash(trigger: listModel.displayedItems.count)
#if !os(visionOS)
            .scrollDismissesKeyboard(.immediately)
#endif
            .navigationTitle(module.title)
            .onAppear {
                listModel.resetListModel()
            }
            .onChange(of: listModel.listSelection) {
                guard !listModel.listSelection.isEmpty else { return }
                listModel.update(selection: listModel.listSelection)
            }
            .onChange(of: listModel.selected) {
//                if let id = listModel.selected {
//                    listModel.listSelection <=> Set(arrayLiteral: id)
//                    let local = totalItems(items: items)
//                    guard let modelId = local.first(where: { $0.id == id })?.model.id else { return }
//                    navigator.navigate(to: route(modelId), method: .push)
//                } else {
//                    listModel.resetListSelection()
//                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                }
                ToolbarItemGroup(placement: secondaryMenuPlacement) {
                    secondaryActionMenu
                }
            }
    }
}

private extension ItemSelectionListView {
    var listModel: ListModel {
        listController.listModel(for: nil)
    }

    @ViewBuilder
    var secondaryActionMenu: some View {
        ControlGroup {
            CompactDisplayModeToggle(listDisplayModel: listDisplayModel)
            MediumDisplayModeToggle(listDisplayModel: listDisplayModel)
            RegularDisplayModeToggle(listDisplayModel: listDisplayModel)
        }
        ControlGroup {
            ListModeToggle(listDisplayModel: listDisplayModel)
            FolderModeToggle(listDisplayModel: listDisplayModel)
        }
    }

    @ViewBuilder
    var listView: some View {
        @Bindable var listModel = listModel
        List(selection: $listModel.listSelection) {
            itemRows()
        }
    }
    
    func itemRows() -> some View {
        ForEach(listModel.displayedItems) { item in
            row(item.itemId)
                .selectListItem {
                    if listModel.selection.contains(item.id) {
                        listModel.selection.removeAll { $0 == item.id }
                    } else {
                        listModel.selection.append(item.id)
                    }
                } isSelected: {
                    listModel.selection.contains(item.id)
                }
                .padding(.leading, CGFloat(item.level * 16))
                .listRowInsets(EdgeInsets(top: 2, leading: leadingPadding, bottom: 2, trailing: 0))
                .listRowSeparator(item.isOpen ? .visible : .hidden, edges: .bottom)
        }
    }
    
    var leadingPadding: CGFloat {
        CGFloat(valueFor(iOS: 8, macOS: 4, tvOS: 8, visionOS: 8))
    }

    var secondaryMenuPlacement: ToolbarItemPlacement {
#if os(tvOS)
        .automatic
#else
        .secondaryAction
#endif
    }
}
