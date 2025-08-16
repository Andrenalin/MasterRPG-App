// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

struct InspectorRootView: View {
    let model: AudioDataModel
    
    @Environment(\.modelContext) private var modelContext
    @Environment(AudioRootModel.self) private var root
    @Environment(ListDisplayModel.self) private var listDisplayModel
    @Environment(SearchModel.self) private var searchModel
    
    @Query(filter: #Predicate<AudioDataModel>{ $0.displayState == 0 }, sort: \AudioDataModel.name, animation: .smooth) private var items: [AudioDataModel]

    @State private var inspectorDisplayModel = ListDisplayModel()
    
    var body: some View {
        NavigationStack {
            @Bindable var searchModel = searchModel

            Picker(selection: $inspectorDisplayModel.listMode) {
                ForEach(ListDisplayModel.ListMode.allCases) { mode in
                    Text(mode.title)
                        .tag(mode)
                }
            } label: {
                Text("List Mode")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            
            TextField("Filter", text: $searchModel.searchText)
                .padding(.horizontal)
            
            LinkItemListView(editController: root.editController, items: items, parentModel: model) { itemId in
                if let model = root.itemController.modelSync(for: itemId) {
                    MainRowView(model: model)
                }
            }
            .environment(inspectorDisplayModel)
//            .onChange(of: listDisplayModel.displayMode, initial: true) {
//                inspectorDisplayModel.displayMode = listDisplayModel.displayMode
//            }
            .onChange(of: model.category) {
                inspectorDisplayModel.listMode = model.category == .folder ? .folder : .list
            }
            .searchable(text: $searchModel.searchText, placement: .automatic)
        }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [AudioDataModel]
    
    InspectorRootView(model: models.first(where: { $0.id == MockData.playlistId })!)
}
