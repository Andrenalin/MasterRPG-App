// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(PhotoRootModel.self) private var root

    @Query(filter: #Predicate<PhotoDataModel>{ $0.displayState == 0 }, sort: \PhotoDataModel.name, animation: .smooth) private var items: [PhotoDataModel]
    
    var body: some View {
        ItemListView(listController: root.listController, editController: root.editController, menuController: menuController, parentModel: nil, module: PhotoDataModel.typeId) { id in
            PhotoRoute.detail(id)
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
#if os(macOS)
        .importsItemProviders(EditController.importImageTypes, onImport: importImage(_:))
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

#if os(macOS)
    nonisolated private func importImage(_ providers: [NSItemProvider]) -> Bool {
        EditController.importImageFromProviders(providers) { data in
            guard let data = data else { return }
            Task { @MainActor in
                let model = root.editController.addNew(modelContext: modelContext, type: .item)
                try? await Task.sleep(for: .seconds(0.5))
                withAnimation {
                    root.editController.resetFile(data: data, model: model)
                    //root.listController.listModel.update(selection: [model.id])
                }
            }
        }
    }
#endif
}

#Preview(traits: .mockData) {
    ManagedNavigationStack {
        ListView()
    }
}
