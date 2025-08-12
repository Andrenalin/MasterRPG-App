// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ListView: View {
    let listModel: ListModel
    
    @Environment(\.modelContext) private var modelContext
    @Environment(AudioRootModel.self) private var root
    @Environment(SearchModel.self) private var searchModel
        
    @Query(filter: #Predicate<AudioDataModel>{ $0.displayState == 0 }, sort: \AudioDataModel.name, animation: .smooth) private var items: [AudioDataModel]
    
    var body: some View {
        ItemListView(editController: root.editController, menuController: menuController, items: items, module: AudioDataModel.typeId) { id in
            AudioRoute.detail(id)
        } row: { model in
            MainRowView(model: model)
        }
//        .onAppear {
//            withAnimation { root.audioPlayerModel.showPlayerToolBar = true }
//        }
#if !os(tvOS)
        .onDrop(of: [.fileURL], delegate: FileDropDelegate(for: FileController.fileTypes, updateFile: updateFile))
#endif
    }

    private var menuController: any ItemListContextMenuControllable {
        ContextMenuMultiController(editController: root.editController, itemController: root.itemController, listModel: listModel)
    }
    
    private func updateFile(url: URL) {
        Task { @MainActor in
            let model = root.editController.addNew(modelContext: modelContext, type: .item)
            try? await Task.sleep(for: .seconds(0.5))
            withAnimation {
                root.editController.resetFile(url: url, in: model)
                listModel.update(selection: [model.id])
            }
        }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [AudioDataModel]
    @Previewable @Environment(ListModel.self) var listModel
    
    ManagedNavigationStack {
        ListView(listModel: listModel)
    }
}
