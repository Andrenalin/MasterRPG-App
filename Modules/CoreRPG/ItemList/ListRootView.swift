// @copyright André Trettin

import CoreExternalRPG
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ListRootView: View {
    let root: ItemRootControllable

    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<ItemDataModel>{ $0.displayState == 0 }, sort: \ItemDataModel.name, animation: .smooth) private var items: [ItemDataModel]

    var body: some View {
        Text("List")
//        ItemListView(listController: root.listControllable, editController: root.editControllable, menuController: menuController, parentModel: nil, module: root.module) { id in
//            ItemRootRoute.detail(id)
//        } row: { itemId in
//            if let model = root.itemControllable.modelSync(for: itemId) {
//                //MainRowView(model: model)
//            }
//        }
        .onChange(of: items, initial: true) {
//            withAnimation { root.listControllable.update(items: items) }
        }
//#if !os(tvOS)
//        .onDrop(of: [.fileURL], delegate: FileDropDelegate(for: FileController.fileTypes, updateFile: updateFile))
//#endif
    }
}

//private extension ListRootView {
//    var menuController: any ItemListContextMenuControllable {
//        ContextMenuMultiController(editController: root.editControllable, itemController: root.itemControllable, listModel: root.listControllable.listModel)
//    }
//    
//    func updateFile(url: URL) {
//        Task { @MainActor in
//            let model = root.editControllable.addNew(modelContext: modelContext, type: .item)
//            try? await Task.sleep(for: .seconds(0.5))
//            withAnimation {
//                root.editControllable.resetFile(url: url, in: model)
//                root.listControllable.listModel.set(selectedItemId: model.id)
//            }
//        }
//    }
//}

