// @copyright André Trettin

import CoreExternalRPG
import AndrenalinKit
import SwiftUI

struct RootNaviList: View {
    let root: TableRoot
    let tabId: UUID
    
    var body: some View {
        ManagedNavigationStack {
            RootExtendedList(editController: root.editController(type: .link), tabId: tabId, selection: false)
        }
    }
}

struct RootList: View {
    init(root: TableRoot, tabId: UUID, selection: Bool = false) {
        self.root = root
        self.tabId = tabId
        self.selection = selection
        self._currentRoute = State(wrappedValue: TableRoute.detail(root.listController(tabId: tabId).model.selectedItem, tabId))
    }
    
    let root: TableRoot
    let tabId: UUID
    let selection: Bool
    
    @State private var column: NavigationSplitViewVisibility = .all
    @State private var currentRoute: TableRoute
    
    var body: some View {
        NavigationSplitView(columnVisibility: $column) {
            RootExtendedList(editController: root.editController(type: .main), tabId: tabId, selection: selection)
                .frame(minWidth: 250)
        } detail: {
            ManagedNavigationStack {
                currentRoute
                    .navigationDestinationAutoReceive(InternalRoute.self)
                    .environment(root.listController(tabId: tabId).model)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onNavigationReceive(assign: $currentRoute, delay: 0.8)
    }
}

struct RootExtendedList: View {
    let editController: EditController
    let tabId: UUID
    let selection: Bool
    
    @Environment(TableRoot.self) private var root
    @Environment(\.navigator) private var navigator
    @State private var firstInit: Bool = true
    
#if os(macOS)
    @Environment(\.openWindow) private var openWindow
#endif
    
    var body: some View {
        listView
            .environment(listController.model)
            .onChange(of: root.itemController.itemDataModel.items, initial: true) {
                if firstInit {
                    listController.update(models: root.itemController.itemDataModel.items.map { ItemRowModel(itemId: $0, typeId: root.itemController.itemDataModel.networkModule) })
                    firstInit = false
                } else {
                    withAnimation {
                        listController.update(models: root.itemController.itemDataModel.items.map { ItemRowModel(itemId: $0, typeId: root.itemController.itemDataModel.networkModule) })
                    }
                }
            }
            .onChange(of: root.itemController.itemDataModel.updateHiddenCounter) {
                withAnimation { listController.resetFilter() }
            }
            .onChange(of: root.rootModel.selectedItem, initial: true) {
                guard selection == true, let selectedItem = root.rootModel.selectedItem else { return }
                root.rootModel.selectedItem = nil
                withAnimation { listController.setSelectedItem(model: selectedItem) }
            }
            .onChange(of: root.rootModel.gameItemSelection, initial: true) {
                guard let selectedItem = root.rootModel.gameItemSelection else { return }
                root.rootModel.gameItemSelection = nil
                withAnimation { listController.setSelectedItem(model: selectedItem) }
            }
            .onChange(of: listController.model.selectedItem, initial: false) {
                navigator.send(TableRoute.detail(listController.model.selectedItem, tabId))
            }
            .onChange(of: listController.model.searchText, initial: false) {
                editController.resetSearch(listController.model.searchText)
            }
    }
    
    private var listController: ListController {
        root.listController(tabId: tabId)
    }
    
    @MainActor
    private var listView: some View {
        ItemList(listController: listController) { item, isSelected in
            TableRow(item: item, isSelected: isSelected, cacheItemListModel: listController.model.cacheItemList.itemCache(for: item.id))
        } editGroupView: { items, showEditor in
            EditGroupEditorList(selectedItems: items, editController: EditGroupController(itemControllable: root.itemController, editControllable: editController, rootControllable: root.rootControllable, selections: items), isPresented: showEditor)
        } exportView: { items, showExport in
            ExportProgressFile(exportController: root.rootControllable.exportControllable, showExport: showExport) {
                let ids = root.exportController.exporting(itemIds: ItemModuleIds(items: Array(items)))
                return root.rootControllable.exportControllable.export(ids: ids)
            }
        } generatorView: { item in
#if os(macOS)
            Color.clear
                .onAppear {
                    root.resetGeneratorController(rootItem: item.wrappedValue)
                    openWindow(id: WindowIdentifier.generatorTableEditor.rawValue)
                    item.wrappedValue = nil
                }
#else
            GeneratorInline(root: root, item: item)
#endif
        }
    }
}

#Preview {
    RootList(root: .preview, tabId: UUID())
}
