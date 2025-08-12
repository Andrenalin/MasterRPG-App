// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct DetailView: View {
    let model: PdfDataModel
    
    @Environment(PdfRootModel.self) private var root
    @Environment(ListModel.self) private var listModel
    
    @State private var selection = GroupItemSelectionModel()
    @State private var openFileWindowModel = OpenFileWindowModel()
    
    var body: some View {
        FileDetailEditorView(model: model, editController: root.editController, menuController: menuController, fileTypes: FileController.fileTypes) {
            PdfRoute.detail($0)
        } importer: {
            FileImporterView(model: model, editController: root.editController, fileTypes: FileController.fileTypes)
        } background: {
            backgroundHeader
        } editor: {
            if !model.specialCategory {
                OpenFileWindowView(model: openFileWindowModel, module: PdfDataModel.typeId, windowId: WindowIdentifier.pdfViewer.rawValue, route: PdfRoute.viewer(selection.selectedItem ?? model.id))
            }
        } row: {
            MainRowView(model: $0)
        } bottom: {
            GroupedPhotoView(cacheController: root.cacheController, model: model)
        }
        .environment(selection)
        .environment(openFileWindowModel)
        .overlay {
            if openFileWindowModel.showItem {
                root.viewController.viewPdfInline(with: selection.selectedItem ?? model.id, withoutBookmark: false) {
                    withAnimation { openFileWindowModel.showItem = false }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.move(edge: .bottom))
            }
        }
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
                Text(PdfDataModel.typeId.localizedTitle)
                    .font(.largeTitle)
            } icon: {
                Image(systemName: PdfDataModel.typeId.icon)
                    .font(.largeTitle)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background {
                    ConcentricRectangle().fill(PdfDataModel.typeId.color.gradient)
                        .ignoresSafeArea(edges: .top)
                        .backgroundExtensionEffect()
                }
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
