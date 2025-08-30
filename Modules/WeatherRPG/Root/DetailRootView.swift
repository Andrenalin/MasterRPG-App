// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI
import PhotoRPG

struct DetailRootView: View {
    @Environment(WeatherRootModel.self) private var root
    
    var body: some View {
        CoreRPG.DetailRootView {
        } editor: {
            if let model {
                if let weatherModel {
                    if !model.specialCategory {
                        // OpenFileWindowView(model: openFileWindowModel, module: root.module, windowId: WindowIdentifier.pdfViewer.rawValue, route: DetailRoute.viewer(selection.selectedItem ?? model.id))
                    }
#if os(macOS)
                    ScrollView {
                        detailEditorView(model: weatherModel)
                    }
#else
                    detailEditorView(model: weatherModel)
#endif
                }
            }
        } inspector: {
            root.photoRoot.viewController.linkWindow(isInspector: true)
        }
        .navigationDestination(for: SelectionPhotoRoute.self) { route in
            route
                .environment(root.editController.selectionPhoto)
        }
    }
    
    var model: ItemDataModel? {
        root.listControllable.listModel.selectedModel
    }

    var weatherModel: WeatherDataModel? {
        root.itemController.model(for: model?.id)
    }

    func detailEditorView(model: WeatherDataModel) -> some View {
        Form {
            WeatherEditor(model: model)
        }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [ItemDataModel]
    @Previewable @Environment(WeatherRootModel.self) var root
    
    NavigationStack {
        DetailRootView()
    }
    .onAppear {
        root.listControllable.update(items: models, parentModel: nil)
        root.listControllable.listModel.set(selectedItemId: models.first!.id)
    }
}
