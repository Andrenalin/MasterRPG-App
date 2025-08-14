// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ListModel.self) private var listModel
    @Environment(PdfRootModel.self) private var root
        
    @Query(filter: #Predicate<PdfDataModel>{ $0.displayState == 0 }, sort: \PdfDataModel.name, animation: .smooth) private var items: [PdfDataModel]
    
    var body: some View {
        ItemListView(editController: root.editController, menuController: menuController, items: items, module: PdfDataModel.typeId) { id in
            PdfRoute.detail(id)
        } row: { model in
            MainRowView(model: model)
        }
#if !os(tvOS)
        .onDrop(of: [.fileURL], delegate: FileDropDelegate(for: FileController.fileTypes, updateFile: updateFile))
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
}

#Preview(traits: .mockData) {
    ManagedNavigationStack {
        ListView()
    }
}
