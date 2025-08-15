// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct DetailView: View {
    let model: SpaceDataModel
    
    @Environment(SpaceRootModel.self) private var root
    @Environment(ListModel.self) private var listModel
    
    @State private var selection = GroupItemSelectionModel()
    @State private var openFileWindowModel = OpenFileWindowModel()
    
    var body: some View {
        FileDetailEditorView(model: model, editController: root.editController, menuController: menuController, fileTypes: FileController.fileTypes) {
            SpaceRoute.detail($0)
        } importer: {
            FileImporterView(model: model, editController: root.editController, fileTypes: FileController.fileTypes)
        } background: {
            backgroundHeader
        } editor: {
        } row: { itemId in
            if let model = root.itemController.modelSync(for: itemId) {
                MainRowView(model: model)
            }
        } bottom: {
            GroupedPhotoView(cacheController: root.cacheController, model: model)
        }
        .environment(selection)
        .environment(openFileWindowModel)
    }
}

private extension DetailView {
    @ViewBuilder
    var backgroundHeader: some View {
        if model.specialCategory == false && model.url != nil {
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
        } else if model.specialCategory == true || model.url != nil {
            Label {
                Text(SpaceDataModel.typeId.localizedTitle)
                    .font(.largeTitle)
            } icon: {
                Image(systemName: SpaceDataModel.typeId.icon)
                    .font(.largeTitle)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background {
                    ConcentricRectangle().fill(SpaceDataModel.typeId.color.gradient)
                        .ignoresSafeArea(edges: .top)
                        .backgroundExtensionEffect()
                }
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
    
    DetailView(model: models[0])
}
