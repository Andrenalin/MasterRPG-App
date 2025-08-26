// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct DetailRootView: View {
    @Environment(SpaceRootModel.self) private var root
    
    var body: some View {
        CoreRPG.DetailRootView {
        } editor: {
            if let model = selectedModel {
                GeometryReader { geometry in
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            VStack {
                                SpaceViewer(root: root, model: model)
                                    .id(model.id)
                                    .frame(minHeight: 600)
                            }
                        }
                        .frame(height: geometry.size.height)
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
    @Previewable @Environment(SpaceRootModel.self) var root
    
    DetailRootView().onAppear {
        root.listControllable.listModel.set(selectedItemId: models.first!.id)
    }
}
