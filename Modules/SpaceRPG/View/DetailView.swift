// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct DetailView: View {
    let model: SpaceDataModel
    
    @Environment(SpaceRootModel.self) private var root
    @Environment(ListModel.self) private var listModel
    
    @State private var selection = GroupItemSelectionModel()
    
    var body: some View {
        FileDetailEditorView(model: model, editController: root.editController, name: \.name, category: \.category, tags: \.tags, description: \.information, url: \.url, specialCategory: \.specialCategory, fileTypes: FileController.fileTypes) {
            FileImporterView(model: model, editController: root.editController, fileTypes: FileController.fileTypes)
        } background: {
            backgroundHeader
        } editor: {
            if model.specialCategory {
                detailListView
            }
        } bottom: {
            GroupedPhotoView(cacheController: root.cacheController, model: model)
                .environment(selection)
        }
        .environment(selection)
    }
}

private extension DetailView {
    var backgroundHeader: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack {
                        detailView
                            .frame(minHeight: 600)
                    }
                }
                .frame(height: geometry.size.height)
            }
        }
    }

    var detailListView: some View {
        DetailListView(editController: root.editController, menuController: menuController, listModel: listModel.listModel(for: model.id, parentIsFolder: model.category == .folder), parentModel: model, items: model.subItems, module: SpaceDataModel.typeId) { id in
            SpaceRoute.detail(id)
        } row: { model in
            MainRowView(model: model)
        }
    }

    var menuController: any ItemListContextMenuControllable {
        ContextMenuMultiController(editController: root.editController, itemController: root.itemController, listModel: listModel)
    }
    
    var detailView: some View {
        SpaceViewer(root: root, model: model)
            .id(model.id)
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [SpaceDataModel]
    @Previewable @Environment(\.modelContext) var modelContext
    
    DetailView(model: models[0])
        .environment(SpaceRootModel(modelContext: modelContext))
        .environment(CacheItemListModel())
}
