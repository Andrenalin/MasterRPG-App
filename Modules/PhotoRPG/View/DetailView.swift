// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct DetailView: View {
    let model: PhotoDataModel

    @Environment(PhotoRootModel.self) private var root
    @Environment(ListModel.self) private var listModel

    @State private var selection = GroupItemSelectionModel()
    @State private var openFileWindowModel = OpenFileWindowModel()

    var body: some View {
        FileDetailEditorView(model: model, editController: root.editController, menuController: menuController, fileTypes: FileController.fileTypes) {
            PhotoRoute.detail($0)
        } importer: {
            VStack {
                PhotoImporterView(model: model, prominent: true)
            }
        } background: {
            backgroundHeader
        } editor: {
            if !model.specialCategory {
                degreesPickerView
                    .overlay(alignment: .bottomTrailing) {
                        if !model.specialCategory {
                            PhotoInlineImporterView(model: model)
                                .padding(.bottom, 32)
                        }
                    }
            }
        } row: { itemId in
            if let model = root.itemController.modelSync(for: itemId) {
                MainRowView(model: model)
            }
        } bottom: {
            GroupedPhotoView(cacheController: root.cacheController, model: model)
        } inspector: {
            LinkRootView(isInspector: true)
        }
        .environment(selection)
        .environment(openFileWindowModel)
    }
}

private extension DetailView {
    @ViewBuilder
    var backgroundHeader: some View {
        if model.specialCategory == false && model.url != nil {
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    GroupedPhotoView(cacheController: root.cacheController, model: model)
                        .stretchy()
                }
            }
            .ignoresSafeArea(.keyboard)
            .ignoresSafeArea(edges: .top)
            .backgroundExtensionEffect()
        } else if model.specialCategory == true || model.url != nil {
            Label {
                Text(PhotoDataModel.typeId.localizedTitle)
                    .font(.largeTitle)
            } icon: {
                Image(systemName: PhotoDataModel.typeId.icon)
                    .font(.largeTitle)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background {
                    ConcentricRectangle().fill(PhotoDataModel.typeId.color.gradient)
                        .ignoresSafeArea(edges: .top)
                        .backgroundExtensionEffect()
                }
        }
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

    var menuController: any ItemListContextMenuControllable {
        ContextMenuMultiController(editController: root.editController, itemController: root.itemController, listModel: listModel)
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [PhotoDataModel]

    DetailView(model: models[0])
}
