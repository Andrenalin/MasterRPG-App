// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct DetailView: View {
    let model: PhotoDataModel

    @Environment(PhotoRootModel.self) private var root
    @Environment(ListModel.self) private var listModel

    @State private var selection = GroupItemSelectionModel()

    var body: some View {
        FileDetailEditorView(model: model, editController: root.editController, fileTypes: FileController.fileTypes) {
            VStack {
                PhotoImporterView(model: model, prominent: true)
            }
        } background: {
            backgroundHeader
        } editor: {
            if model.specialCategory {
                detailListView
            } else {
                degreesPickerView
                    .overlay(alignment: .bottomTrailing) {
                        if !model.specialCategory {
                            PhotoInlineImporterView(model: model)
                                .padding(.bottom, 32)
                        }
                    }
            }
        } bottom: {
            GroupedPhotoView(cacheController: root.cacheController, model: model)
        }
        .environment(selection)
    }
}

private extension DetailView {
    var backgroundHeader: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 8) {
                GroupedPhotoView(cacheController: root.cacheController, model: model)
                    .stretchy()
            }
        }
        .ignoresSafeArea(.keyboard)
        .ignoresSafeArea(edges: .top)
        .backgroundExtensionEffect()
    }

    @ViewBuilder
    var degreesPickerView: some View {
        @Bindable var model = model

        Picker("Degrees", selection: $model.degrees) {
            Text("0°").tag(0.0)
            Text("90°").tag(90.0)
            Text("180°").tag(180.0)
            Text("270°").tag(270.0)
        }
        .pickerStyle(.segmented)
        .padding(.vertical, 6)
        .padding(.horizontal)
    }

    var detailListView: some View {
        DetailListView(editController: root.editController, menuController: menuController, listModel: listModel.listModel(for: model.id, parentIsFolder: model.category == .folder), parentModel: model, items: model.subItems, module: PhotoDataModel.typeId) { id in
            PhotoRoute.detail(id)
        } row: { model in
            MainRowView(model: model)
        }
    }

    var menuController: any ItemListContextMenuControllable {
        ContextMenuMultiController(editController: root.editController, itemController: root.itemController, listModel: listModel)
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [PhotoDataModel]
    @Previewable @Environment(\.modelContext) var modelContext

    DetailView(model: models[0])
        .environment(CacheItemListModel())
}
