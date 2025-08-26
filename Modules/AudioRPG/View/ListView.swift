// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AudioRootModel.self) private var root

    @Query(filter: #Predicate<AudioDataModel>{ $0.displayState == 0 }, sort: \AudioDataModel.name, animation: .smooth) private var items: [AudioDataModel]
    
    var body: some View {
        OldItemListView(listController: root.listController, editController: root.editController, menuController: menuController, parentModel: nil, module: AudioDataModel.typeId) { id in
            AudioRoute.detail(id)
        } row: { itemId in
            if let model = root.itemController.modelSync(for: itemId) {
                MainRowView(model: model)
            }
        }
        .onChange(of: items, initial: true) {
            withAnimation { root.listController.update(items: items) }
        }
#if !os(tvOS)
        .onDrop(of: [.fileURL], delegate: FileDropDelegate(for: FileController.fileTypes, updateFile: updateFile))
#endif
    }
}

private extension ListView {
    var menuController: any ItemListContextMenuControllable {
        ContextMenuMultiController(editController: root.editController, itemController: root.itemController, listModel: root.listController.listModel)
    }
    
    func updateFile(url: URL) {
        Task { @MainActor in
            let model = root.editController.addNew(modelContext: modelContext, type: .item)
            try? await Task.sleep(for: .seconds(0.5))
            withAnimation {
                root.editController.resetFile(url: url, in: model)
                root.listController.listModel.set(selectedItemId: model.id)
            }
        }
    }
}

#Preview(traits: .mockData) {
    ManagedNavigationStack {
        ListView()
    }
}
