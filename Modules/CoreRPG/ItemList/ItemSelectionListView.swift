// @copyright André Trettin

import CoreExternalRPG
import SwiftData
import SwiftUI

public struct ItemSelectionListView: View {
    public init(root: any ItemRootControllable, parentModel: ItemDataModel?, selectionModel: SingleSelectionModel) {
        self.root = root
        self.selectionModel = selectionModel
        root.listLinkControllable.listDisplayModel.listMode = parentModel?.category == .folder ? .folder : .list
    }
    
    let root: any ItemRootControllable
    let selectionModel: SingleSelectionModel
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.navigator) private var navigator

    @Environment(CacheItemListModel.self) private var cacheItemListModel
    @Environment(ListDisplayModel.self) private var listDisplayModel

#if os(iOS) || os(visionOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif
    
    @Query(filter: #Predicate<ItemDataModel> { $0.displayState == 0 }, sort: \ItemDataModel.name, animation: .smooth) private var items: [ItemDataModel]

    public var body: some View {
        listView
            .frame(minWidth: 250, idealWidth: 350)
            .overlay {
                if listModel.displayedItems.isEmpty && !root.listLinkControllable.searchModel.searchText.isEmpty {
                    ContentUnavailableView.search
                }
            }
            .animation(.smooth, value: listModel.displayedItems.count)
#if os(macOS)
    .listStyle(.inset(alternatesRowBackgrounds: true))
#endif
            .scrollIndicatorsFlash(onAppear: true)
            .scrollIndicatorsFlash(trigger: listModel.displayedItems.count)
#if !os(visionOS)
            .scrollDismissesKeyboard(.immediately)
#endif
            .navigationTitle(root.module.title)
            .onChange(of: items, initial: true) {
                withAnimation { root.listLinkControllable.update(items: items.filter { $0.module == root.module }) }
            }
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
        root.listLinkControllable.listModel(for: nil)
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
            HStack {
                ItemRowView(root: root, model: item.model, cacheItemListModel: cacheItemListModel, isSelected: false) {
                    if root.viewControllable.thumbnailRowViewType == .custom {
                        root.viewControllable.thumbnailRowView(for: item.model.id)
                    } else if root.viewControllable.thumbnailRowViewType == .photo, let cacheController = root.cacheControllable {
                        ThumbnailRowPhotoView(cacheController: cacheController, model: item.model)
                    }
                }

                specialCategoryFolderIndicator(item: item)
            }
            .selectListItem {
                selectionModel.itemId = selectionModel.itemId == item.model.id ? nil : item.model.id
            } isSelected: {
                selectionModel.itemId == item.model.id
            }
            .padding(.leading, CGFloat(item.level * 16))
            .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 0))
            .listRowSeparator(item.isOpen ? .visible : .hidden, edges: .bottom)
        }
    }
    
    var leadingPadding: CGFloat {
        CGFloat(valueFor(iOS: 8, macOS: 4, tvOS: 8, visionOS: 8))
    }
    
    @ViewBuilder
    func specialCategoryFolderIndicator(item: ListItemModel) -> some View {
        if item.model.specialCategory {
            Image(systemName: item.isOpen ? "chevron.down" : "chevron.right")
                .imageScale(.small)
                .padding(.trailing)
                .foregroundStyle(item.isOpen ? Color.accentColor : Color.secondary)
                .contentShape(.rect)
                .onTapGesture {
                    withAnimation { root.listLinkControllable.toggleFolder(item: item) }
                }
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
