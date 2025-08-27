// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct DetailRootView: View {
    @Environment(WeatherRootModel.self) private var root
    
    var body: some View {
        CoreRPG.DetailRootView {
        } editor: {
            if let model = selectedModel {
                if !model.specialCategory {
                    // OpenFileWindowView(model: openFileWindowModel, module: root.module, windowId: WindowIdentifier.pdfViewer.rawValue, route: DetailRoute.viewer(selection.selectedItem ?? model.id))
                }
            }
        }
    }
    
    var selectedModel: ItemDataModel? {
        root.listControllable.listModel.selectedModel
    }

}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [ItemDataModel]
    @Previewable @Environment(WeatherRootModel.self) var root
    
    DetailRootView().onAppear {
        root.listControllable.listModel.set(selectedItemId: models.first!.id)
    }
}
