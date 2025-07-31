// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct DetailView: View {
    let model: SpaceDataModel
    
    @Environment(SpaceRootModel.self) private var root
    
    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
            
            FileDetailEditorView(model: model, editController: root.editController, name: \.name, category: \.category, tags: \.tags, description: \.information, url: \.url, specialCategory: \.specialCategory, fileTypes: FileController.fileTypes) {
                FileImporterView(model: model, editController: root.editController, fileTypes: FileController.fileTypes)
            } inside: {
                contentView
            }
            .overlay(alignment: .bottomTrailing) {
                FileImporterView(model: model, editController: root.editController, fileTypes: FileController.fileTypes, isProminent: false)
            }
        }
    }
    
    var contentView: some View {
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
        .mask(LinearGradient(
            gradient: Gradient(colors: [.black, .black, .black, .clear]),
            startPoint: .top, endPoint: .bottom))
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
