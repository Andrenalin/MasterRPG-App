// @copyright André Trettin

import CoreExternalRPG
import AndrenalinKit
import SwiftUI
import WeatherRPG
import RPGValues
import AudioRPG
import RPGDie
import RPGDie
import RPGMaps
import PhotoRPG
import AudioRPG
import PdfRPG
import RPGTables
import RPGTables
import SpaceRPG
import SpaceRPG
import RPGMaps
import PhotoRPG
import PdfRPG

struct RootNaviList: View {
    let root: AdventureRootModel
    let tabId: UUID
    var openAction: ((NetworkModules) -> Void)? = nil
    
    var body: some View {
        let _ = Self._printChanges()
        
        ManagedNavigationStack {
            RootExtendedList(editController: root.editController(type: .link), tabId: tabId, selection: false, openAction: openAction)
        }
    }
}

struct RootList: View {
    init(root: AdventureRootModel, tabId: UUID, selection: Bool = false) {
        self.root = root
        self.tabId = tabId
        self.selection = selection
        self._currentRoute = State(wrappedValue: AdventureRoute.detail(root.listController(tabId: tabId).model.selectedItem?.model.itemId ?? UUID()))
    }
    
    let root: AdventureRootModel
    let tabId: UUID
    let selection: Bool
    
    @State private var column: NavigationSplitViewVisibility = .all
    @State private var currentRoute: AdventureRoute
    
    var body: some View {
        let _ = Self._printChanges()
        
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
    var openAction: ((NetworkModules) -> Void)?
    
    @Environment(AdventureRootModel.self) private var root
    @Environment(\.navigator) private var navigator
    @State private var firstInit: Bool = true
    
    var body: some View {
        let _ = Self._printChanges()
        
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
            .onChange(of: listController.model.gameSelectedItem, initial: true) {
                guard let openAction, let model = listController.model.gameSelectedItem?.model else { return }
                showSelectedLinkWindow(row: model, openAction: openAction)
            }
            .onChange(of: root.rootModel.gameItemSelection, initial: true) {
                guard openAction == nil, let selectedItem = root.rootModel.gameItemSelection else { return }
                root.rootModel.gameItemSelection = nil
                withAnimation { listController.setSelectedItem(model: selectedItem) }
            }
            .onChange(of: listController.model.selectedItem, initial: false) {
                guard let itemId = listController.model.selectedItem?.model.itemId else { return }
                navigator.navigate(to: AdventureRoute.detail(itemId))
            }
            .onChange(of: listController.model.searchText, initial: false) {
                editController.resetSearch(listController.model.searchText)
            }
    }
    
    private var listController: ListController {
        root.listController(tabId: tabId)
    }
    
    private var listView: some View {
        ItemList(listController: listController) { item, isSelected in
            AdventureRow(item: item, isSelected: isSelected, cacheItemListModel: listController.model.cacheItemList.itemCache(for: item.id))
        } editGroupView: { items, showEditor in
            EditGroupEditorList(selectedItems: items, editController: EditGroupController(itemControllable: root.itemController, editControllable: editController, rootControllable: root, selections: items), isPresented: showEditor)
        } exportView: { items, showExport in
            ExportProgressFile(exportController: root.exportController, showExport: showExport) {
                let ids = root.exportController.exporting(itemIds: ItemModuleIds(items: Array(items)))
                return root.exportControllable.export(ids: ids)
            }
        }
    }
    
    @MainActor
    private func showSelectedLinkWindow(row: ItemRowModel, openAction: @escaping (NetworkModules) -> Void) {
        guard let entryId = row.entryId else { return }
        let entry = root.itemController.itemOrEmpty(for: row.itemId)[entryId]
        let links = entry.links(for: entry.content)
        links.forEach {
            guard $0.entryId == nil else { return }
            let selected = ItemRowModel(itemId: $0.itemId, entryId: $0.entryId, typeId: $0.module)
            switch $0.module {
            case .adventure:
                root.rootModel.gameItemSelection = selected
            case .audio:
                root.audioRoot.rootModel.gameItemSelection = selected
            case .dice:
                root.diceRoot.rootModel.gameItemSelection = selected
            case .pdf:
                root.pdfRoot.rootModel.gameItemSelection = selected
            case .map:
                root.mapRoot.rootModel.gameItemSelection = selected
            case .photo:
                root.photoRoot.rootModel.gameItemSelection = selected
            case .space:
                root.spaceRoot.rootModel.gameItemSelection = selected
            case .table:
                root.tableRoot.rootModel.gameItemSelection = selected
            case .value:
                root.valueRoot.rootModel.gameItemSelection = selected
            case .weather:
                root.weatherRoot.rootModel.gameItemSelection = selected
            default:
                break
            }
            openAction($0.module)
        }
    }
}

#Preview {
    RootList(root: .previewWithData, tabId: UUID())
        .frame(width: 800, height: 1000)
        .environment(\.locale, .init(identifier: "de"))
}
