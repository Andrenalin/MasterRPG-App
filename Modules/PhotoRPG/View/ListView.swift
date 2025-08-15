// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(PhotoRootModel.self) private var root
    @Environment(ListModel.self) private var listModel

    @Query(filter: #Predicate<PhotoDataModel>{ $0.displayState == 0 }, sort: \PhotoDataModel.name, animation: .smooth) private var items: [PhotoDataModel]
    
    var body: some View {
        ItemListView(editController: root.editController, menuController: menuController, listModel: listModel, parentModel: nil, items: items, module: PhotoDataModel.typeId) { id in
            PhotoRoute.detail(id)
        } row: { model in
            MainRowView(model: model)
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
        ContextMenuMultiController(editController: root.editController, itemController: root.itemController, listModel: listModel)
    }

    func updateFile(url: URL) {
        Task { @MainActor in
            let model = root.editController.addNew(modelContext: modelContext, type: .item)
            try? await Task.sleep(for: .seconds(0.5))
            withAnimation {
                root.editController.resetFile(url: url, in: model)
                listModel.update(selection: [model.id])
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
                    listModel.update(selection: [model.id])
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
