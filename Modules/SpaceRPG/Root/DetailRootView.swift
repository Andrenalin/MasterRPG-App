// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct DetailRootView: View {
    let selectedId: UUID?
    
    @Environment(\.modelContext) private var modelContext
    @Environment(SpaceRootModel.self) private var root
    
    var body: some View {
        CoreRPG.DetailRootView(selectedId: selectedId) {
        } editor: {
            if let model = selectedModel {
                SpaceViewer(root: root, model: model)
                    .id(model.id)
                    .frame(minHeight: 800)

                if !model.specialCategory {
                    //                    OpenFileWindowView(model: openFileWindowModel, module: root.module, windowId: WindowIdentifier.pdfViewer.rawValue, route: DetailRoute.viewer(selection.selectedItem ?? model.id))
                }
            }
        }
    }
    
    var selectedModel: ItemDataModel? {
        root.listControllable.selectedModel(for: selectedId, modelContext: modelContext)
    }
}

#Preview(traits: .mockData) {
    DetailRootView(selectedId: MockData.previewId)
}
