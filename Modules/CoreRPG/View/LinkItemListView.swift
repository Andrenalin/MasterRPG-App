// @copyright André Trettin

import CoreExternalRPG
import SwiftData
import SwiftUI

public struct LinkItemListView<EditController: EditControllable, Row: View>: View where EditController.Model.ID == UUID {
    public init(editController: EditController, items: [EditController.Model], parentModel: EditController.Model, @ViewBuilder row: @escaping (UUID) -> Row) {
        self.editController = editController
        self.items = items
        self.parentModel = parentModel
        self.row = row
    }
    let editController: EditController
    let items: [EditController.Model]
    let parentModel: EditController.Model
    let row: (UUID) -> Row
    
    @Environment(\.modelContext) private var modelContext

    @Environment(ListDisplayModel.self) private var listDisplayModel
    @Environment(SearchModel.self) private var searchModel
    
    @State private var cacheItemListModel = CacheItemListModel()
    @State private var myDisplayModel = ListDisplayModel()
    @State private var listModel = ListModel()

    public var body: some View {
        NavigationStack {
            @Bindable var searchModel = searchModel
            listView()
                .frame(minWidth: 250, idealWidth: 350)
                .overlay {
                    if filteredItems.isEmpty && !searchModel.searchText.isEmpty {
                        ContentUnavailableView.search
                    }
                }
                .environment(myDisplayModel)
                .environment(listModel)
                .onChange(of: listDisplayModel.displayMode, initial: true) {
                    myDisplayModel.displayMode = listDisplayModel.displayMode
                }
                .animation(.smooth, value: filteredItems.count)
                .scrollIndicatorsFlash(onAppear: true)
                .scrollIndicatorsFlash(trigger: filteredItems.count)
#if !os(visionOS)
                .scrollDismissesKeyboard(.immediately)
#endif
                .searchable(text: $searchModel.searchText, placement: .automatic)
        }
    }
}

private extension LinkItemListView {
        
    var filteredItems: [EditController.Model] {
        var filtered: [EditController.Model]
        if parentModel.category == .folder {
            myDisplayModel.listMode = .folder
            filtered = items
        } else {
            myDisplayModel.listMode = .list
            filtered = items.filter { $0.category != .folder && $0.category != EditController.Model.collectionCategory }
        }
        if !searchModel.selectedTokens.isEmpty {
            let selectedTags = searchModel.selectedTokens.map { $0.tag }
            filtered = filtered.filter { $0.tags.contains(selectedTags) }
        }
        guard !searchModel.searchText.isEmpty else { return filtered }
        return filtered.filter {
            $0.name.localizedStandardContains(searchModel.searchText) ||
            $0.information.localizedStandardContains(searchModel.searchText)
        }
    }

    @ViewBuilder
    func listView() -> some View {
        @Bindable var listModel = listModel
        List(selection: $listModel.listSelection) {
            itemRows()
        }
    }
    
    func itemRows() -> some View {
        ForEach(filteredItems) { item in
            row(item.id)
                .listRowInsets(EdgeInsets(top: 2, leading: leadingPadding, bottom: 2, trailing: 0))
        }
    }
    
    var leadingPadding: CGFloat {
        CGFloat(valueFor(iOS: 8, macOS: 4, tvOS: 8, visionOS: 8))
    }
}
