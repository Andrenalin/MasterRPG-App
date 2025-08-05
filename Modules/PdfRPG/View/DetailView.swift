// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct DetailView: View {
    let model: PdfDataModel
    
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif
    @Environment(PdfRootModel.self) private var root
    @Environment(ListModel.self) private var listModel

    @State private var selection = GroupItemSelectionModel()

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear

            FileDetailEditorView(model: model, editController: root.editController, name: \.name, category: \.category, tags: \.tags, description: \.information, url: \.url, specialCategory: \.specialCategory, fileTypes: FileController.fileTypes) {
                FileImporterView(model: model, editController: root.editController, fileTypes: FileController.fileTypes)
            } editor: {
                if model.specialCategory {
                    playlistView
                }
            }

            VStack {
                if !model.specialCategory {
                    carouselView
                        .padding(.bottom)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
#if !os(tvOS)
        .toolbar(removing: .title)
#endif
    }
}

private extension DetailView {
    var shouldShowBottomBar: Bool {
#if os(iOS)
        return horizontalSizeClass != .compact
#else
        return true
#endif
    }

    var playlistView: some View {
        DetailListView(editController: root.editController, menuController: menuController, listModel: listModel.listModel(for: model.id, parentIsFolder: model.category == .folder), parentModel: model, items: model.subItems, module: PdfDataModel.typeId) { id in
            PdfRoute.detail(id)
        } row: { model in
            MainRowView(model: model)
        }
    }

    private var menuController: any ItemListContextMenuControllable {
        ContextMenuMultiController(editController: root.editController, itemController: root.itemController, listModel: listModel)
    }

    @ViewBuilder
    var carouselView: some View {
        if model.url != nil {
            CarouselItemView(model: model, editController: root.editController, selection: selection) {
                GroupItemView(model: model)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .transition(.move(edge: .bottom))
        }
    }
}


#Preview(traits: .mockData) {
    @Previewable @Query var models: [PdfDataModel]
    @Previewable @Environment(\.modelContext) var modelContext

    DetailView(model: models[0])
        .environment(CacheItemListModel())
}
