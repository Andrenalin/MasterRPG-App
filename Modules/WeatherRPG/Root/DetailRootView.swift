// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI
import PhotoRPG

struct DetailRootView: View {
    let selectedId: UUID?
    
    @Environment(\.modelContext) private var modelContext
    @Environment(WeatherRootModel.self) private var root
    
    @State private var openFileWindowModel = OpenFileWindowModel(windowId: NetworkModules.weather.viewerkWindowId, canShow: true, route: { DetailRoute.viewer($0) })
    
    var body: some View {
        ItemDetailRootView(selectedId: selectedId) {
        } editor: {
            if let weatherModel {
                detailEditorView(model: weatherModel)
            }
        } inspector: {
            root.photoRoot.viewController.linkWindow(root: root.photoRoot, isInspector: true)
        }
        .navigationDestination(for: SelectionPhotoRoute.self) { route in
            route
                .environment(root.editController.selectionPhoto)
        }
        .overlay {
            if openFileWindowModel.showItem {
                root.viewController.inlineViewer(root: root, with: openFileWindowModel.itemId) {
                    openFileWindowModel.showItem = false
                }
            }
        }
        .environment(openFileWindowModel)
        .environment(root.listController.cacheListItemModel)
    }
    
    var selectedModel: ItemDataModel? {
        root.listControllable.selectedModel(for: selectedId, modelContext: modelContext)
    }

    var weatherModel: WeatherDataModel? {
        root.itemController.model(for: selectedId ?? root.listControllable.listModel.selectedItemId)
    }

    func detailEditorView(model: WeatherDataModel) -> some View {
        WeatherEditor(model: model)
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [ItemDataModel]
    @Previewable @Environment(WeatherRootModel.self) var root
    
    NavigationStack {
        DetailRootView(selectedId: MockData.previewId)
    }
    .onAppear {
        root.listControllable.update(items: models, parentModel: nil)
        root.listControllable.listModel.set(selectedItemId: models.first!.id)
    }
}
