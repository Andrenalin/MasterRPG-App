// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct DetailRootView: View {
    @Environment(PhotoRootModel.self) private var root
    
    var body: some View {
        CoreRPG.DetailRootView {
        } editor: {
            if let model = selectedModel {
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        GroupedPhotoView(cacheController: root.cacheController, model: model)
                            .stretchy()
                    }
                }

                if !model.specialCategory {
//                    OpenFileWindowView(model: openFileWindowModel, module: root.module, windowId: WindowIdentifier.pdfViewer.rawValue, route: DetailRoute.viewer(selection.selectedItem ?? model.id))
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
    @Previewable @Environment(PhotoRootModel.self) var root
    
    DetailRootView().onAppear {
        root.listControllable.listModel.set(selectedItemId: models.first!.id)
    }
}
