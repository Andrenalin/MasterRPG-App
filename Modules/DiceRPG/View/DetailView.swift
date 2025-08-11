// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct DetailView: View {
    let model: DiceDataModel

    @Environment(DiceRootModel.self) private var root
    @Environment(ListModel.self) private var listModel

    @State private var selection = GroupItemSelectionModel()
    @State private var openFileWindowModel = OpenFileWindowModel()

    var body: some View {
        let _ = Self._printChanges()
        FileDetailEditorView(model: model, editController: root.editController, fileTypes: []) {
        } background: {
            backgroundHeader
        } editor: {
            if model.specialCategory {
                detailListView
            } else {
                DiceEditor(model: model)
                DiceOptionEditor(model: model)
            }
        } bottom: {
//            GroupedPhotoView(cacheController: root.cacheController, model: model)
        }
        .environment(selection)
        .environment(openFileWindowModel)
    }
}

private extension DetailView {
    var backgroundHeader: some View {
        DiceViewer(model: model, isEditor: false)
//        ScrollView(showsIndicators: false) {
//            LazyVStack(alignment: .leading, spacing: 8) {
//                ConcentricRectangle().fill(Color.blue.gradient)
//                    .overlay {
//                        DiceViewer(model: model)
//                    }
//                    .frame(minHeight: 600)
//            }
//        }
//        //.ignoresSafeArea(.keyboard)
//        .ignoresSafeArea(edges: .top)
//        .backgroundExtensionEffect()
        
    }

    var detailListView: some View {
        DetailListView(editController: root.editController, menuController: menuController, listModel: listModel.listModel(for: model.id, parentIsFolder: model.category == .folder), parentModel: model, items: model.subItems, module: DiceDataModel.typeId) { id in
            DiceRoute.detail(id)
        } row: { model in
            MainRowView(model: model)
        }
    }

    var menuController: any ItemListContextMenuControllable {
        ContextMenuMultiController(editController: root.editController, itemController: root.itemController, listModel: listModel)
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [DiceDataModel]
    @Previewable @Environment(DiceRootModel.self) var root
    
    DetailView(model: models[0])
        .environment(CacheItemListModel())
        .environment(ListModel())
        .environment(root.searchModel)
        .environment(DeviceRotationModel())
}
