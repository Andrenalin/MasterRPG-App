// @copyright André Trettin

import SwiftData
import SwiftUI

public struct DetailRootView<Header: View, Editor: View, Inspector: View, Overlay: View>: View {
    public init(selectedId: UUID?, @ViewBuilder header: () -> Header = EmptyView.init, @ViewBuilder editor: () -> Editor = EmptyView.init, @ViewBuilder inspector: () -> Inspector = EmptyView.init, @ViewBuilder overlay: () -> Overlay = EmptyView.init) {
        self.selectedId = selectedId
        self.header = header()
        self.editor = editor()
        self.inspector = inspector()
        self.overlay = overlay()
    }
    
    let selectedId: UUID?
    let header: Header
    let editor: Editor
    let inspector: Inspector
    let overlay: Overlay
    
    @Environment(\.modelContext) private var modelContext
    
    @Environment(CacheItemListModel.self) private var cacheItemListModel
    @Environment(ListDisplayModel.self) private var listDisplayModel
    @Environment(SearchModel.self) private var searchModel
    
    @Environment(ItemRootController.self) private var root
    
    @State private var selection = GroupItemSelectionModel()

    public var body: some View {
        let _ = Self._printChanges()
        
        if let selectedModel {
            ItemDetailEditorView(root: root, model: selectedModel) {
                header
            } editor: {
                editor
            } inspector: {
                inspector
            } overlay: {
                overlay
            }
            .environment(selection)
        }
    }
    
    var selectedModel: ItemDataModel? {
        if let selectedId {
            return ItemDataModel.model(modelContext: modelContext, id: selectedId)
        } else {
            return root.listControllable.listModel.selectedModel
        }
    }
}

//#Preview("Folder", traits: .mockData) {
//    @Previewable @Environment(FakeItemRootController.self) var root
//    @Previewable @Query var models: [ItemDataModel]
//    
//    DetailRootView(model: models.first(where: { $0.id == MockData.folderId })!)
//}
//
//#Preview("Collection", traits: .mockData) {
//    @Previewable @Environment(FakeItemRootController.self) var root
//    @Previewable @Query var models: [ItemDataModel]
//    
//    DetailRootView(model: models.first(where: { $0.id == MockData.playlistId })!)
//}
//
//#Preview("Item", traits: .mockData) {
//    @Previewable @Environment(FakeItemRootController.self) var root
//    @Previewable @Query var models: [ItemDataModel]
//    
//    DetailRootView(model: models.first(where: { $0.id == MockData.previewId })!)
//}
