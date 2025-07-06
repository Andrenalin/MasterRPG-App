//
//  PhotoList.swift
//  MasterRPG
//
//  Created by Andre Trettin on 03.07.25.
//

import SwiftData
import SwiftUI
import AndrenalinKit

struct PhotoRootView: View {
    @Environment(AppRootModel.self) private var appRootModel
    
    @State private var selectionModel = ListSelectionModel()
    
    @State private var column: NavigationSplitViewVisibility = .all
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar
    
    var body: some View {
        @Bindable var listModel = appRootModel.listModel
        NavigationSplitView(columnVisibility: $column, preferredCompactColumn: $preferredCompactColumn) {
            PhotoListView()
                .environment(selectionModel)
        } detail: {
            if let selected = selectionModel.selectedItem {
                DetailView(item: selected)
                    .environment(selectionModel)
            } else {
                ContentUnavailableView("Photo", image: "photos")
            }
        }
        .ignoresSafeArea(edges: .top)
        .searchable(text: $listModel.searchText, placement: .automatic, prompt: "Search")
        .searchScopes($listModel.searchToken, activation: searchScopeActivition) {
            ForEach(listModel.categoryTags) { category in
                #if os(macOS)
                Label(category.title, systemImage: category.icon)
                    .tag(category)
    #else
                Text(category.title)
                    .tag(category)
                #endif
            }
        }
        .searchPresentationToolbarBehavior(.avoidHidingContent)
    }
    
    var searchPlacement: SearchFieldPlacement {
        .automatic
    }

    var searchScopeActivition: SearchScopeActivation {
#if os(tvOS)
        .automatic
#else
        .onSearchPresentation
#endif
    }
}

struct PhotoListView: View {
    @Environment(AppRootModel.self) private var appRootModel
    @Environment(\.modelContext) private var modelContext
    @Environment(ListSelectionModel.self) private var model

    @Query(sort: \PhotoDataModel.name, animation: .smooth) private var items: [PhotoDataModel]
    
    @State private var selected: UUID?
    @State private var selection: Set<UUID> = []
    @State private var isSelectionMode: Bool = false
    
    #if os(iOS)
    @Environment(\.editMode) private var editMode
    #endif
    
    var body: some View {
        @Bindable var listModel = appRootModel.listModel
        
        let filteredItems = listModel.searchText.isEmpty ? items : items.filter { $0.name.localizedStandardContains(listModel.searchText) || $0.information.localizedStandardContains(listModel.searchText) }
        
        Group {
            if isSelectionMode {
                selectionListView(filteredItems: filteredItems)
            } else {
                listView(filteredItems: filteredItems)
            }
        }
        .animation(.smooth, value: filteredItems)
        .animation(.snappy, value: isSelectionMode)
        .onChange(of: selected) {
            model.selectedItem = items.first { $0.id == selected }
        }
#if os(iOS)
        .onChange(of: editMode) {
            isSelectionMode = (editMode?.wrappedValue == .active) ?? false
        }
        #endif
        .navigationTitle("Photos")
#if os(macOS)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
#endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: addItem) {
                        Label("Add Item", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
#if os(iOS)
                    EditButton()
                    #else
                    Button {
                        isSelectionMode.toggle()
                    } label: {
                        Label("Change Mode to \(isSelectionMode ? "Off" : "On")", systemImage: "list.bullet")
                    }
#endif
                }
            }
    }
    
        private func addItem() {
            withAnimation {
                let newItem = PhotoDataModel(name: "\(Date()) Hello", information: "Some more Text ususally longer", category: .character, tags: ["Held", "Meins"], degrees: Double.random(in: 0...360.0))
                modelContext.insert(newItem)
            }
        }

        private func deleteItems(offsets: IndexSet) {
            withAnimation {
                for index in offsets {
                    modelContext.delete(items[index])
                }
            }
        }
    
    private func listView(filteredItems: [PhotoDataModel]) -> some View {
        List(selection: $selected) {
            ForEach(filteredItems) { item in
                PhotoRow(model: item)
            }
            .onDelete(perform: deleteItems)
        }
    }
    
    private func selectionListView(filteredItems: [PhotoDataModel]) -> some View {
        List(selection: $selection) {
            ForEach(filteredItems) { item in
                PhotoRow(model: item)
            }
        }
    }
}

struct PhotoRow: View {
    let model: PhotoDataModel
    @Environment(AppRootModel.self) private var appRootModel
    
    var body: some View {
        ItemRow(itemId: model.id, model: model, cacheItemListModel: appRootModel.cacheModel, name: \.name, tags: \.tags, description: \.information, isSelected: false, thumbnail: {
            //ThumbnailItem(root: root, model: model, highResolution: false)
            Text(appRootModel.listModel.searchText)
        }, tagAdds: {
            CategoryItemRow(category: model.category)
        }, actionBar: {
        })
    }
}

#Preview {
    PhotoRootView()
        .modelContainer(for: [PhotoDataModel.self, PhotoEntryDataModel.self], inMemory: true)
        .environment(AppRootModel())
        .environment(AppRootModel().listModel)
        .environment(AppRootModel().deviceRotationModel)
}
