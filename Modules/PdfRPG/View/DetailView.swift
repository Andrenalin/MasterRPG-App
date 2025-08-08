// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct DetailView: View {
    let model: PdfDataModel
    
    @Environment(PdfRootModel.self) private var root
    @Environment(ListModel.self) private var listModel
    
    @State private var selection = GroupItemSelectionModel()
    
    @State private var showPdf: Bool = false
    
    var body: some View {
        FileDetailEditorView(model: model, editController: root.editController, name: \.name, category: \.category, tags: \.tags, description: \.information, url: \.url, specialCategory: \.specialCategory, fileTypes: FileController.fileTypes) {
            FileImporterView(model: model, editController: root.editController, fileTypes: FileController.fileTypes)
        } background: {
            backgroundHeader
                .overlay(alignment: .bottomTrailing) {
                    GlassButton {
                        showPdf.toggle()
                    } label: {
                        Image(systemName: PdfDataModel.typeId.icon)
                    }
                }
        } editor: {
            if model.specialCategory {
                detailListView
            }
        } bottom: {
            GroupedPhotoView(cacheController: root.cacheController, model: model)
        }
        .environment(selection)
        .overlay {
            if showPdf {
                PdfViewerView(editController: root.editController, model: model, entryId: nil, withoutBookmark: false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
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
    
    var detailListView: some View {
        DetailListView(editController: root.editController, menuController: menuController, listModel: listModel.listModel(for: model.id, parentIsFolder: model.category == .folder), parentModel: model, items: model.subItems, module: PdfDataModel.typeId) { id in
            PdfRoute.detail(id)
        } row: { model in
            MainRowView(model: model)
        }
    }
    
    var menuController: any ItemListContextMenuControllable {
        ContextMenuMultiController(editController: root.editController, itemController: root.itemController, listModel: listModel)
    }
}


#Preview(traits: .mockData) {
    @Previewable @Query var models: [PdfDataModel]
    @Previewable @Environment(\.modelContext) var modelContext
    
    DetailView(model: models[0])
        .environment(CacheItemListModel())
}
