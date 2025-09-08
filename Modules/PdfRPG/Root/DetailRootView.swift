// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct DetailRootView: View {
    let selectedId: UUID?
    
    @Environment(\.modelContext) private var modelContext
    @Environment(PdfRootModel.self) private var root
    
    @State private var openFileWindowModel = OpenFileWindowModel(windowId: WindowIdentifier.pdfViewer.rawValue, route: { DetailRoute.viewer($0) })

    var body: some View {
        CoreRPG.DetailRootView(selectedId: selectedId) {
        } editor: {
            if let model = selectedModel {
                GroupedPhotoView(cacheController: root.cacheController, model: model)
            }
        }
        .overlay {
            if openFileWindowModel.showItem {
                root.viewController.viewPdfInline(root: root, with: openFileWindowModel.itemId, withoutBookmark: false) {
                    openFileWindowModel.showItem = false
                }
            }
        }
        .environment(openFileWindowModel)
    }
    
    var selectedModel: ItemDataModel? {
        root.listControllable.selectedModel(for: selectedId, modelContext: modelContext)
    }
}

#Preview(traits: .mockData) {
    DetailRootView(selectedId: MockData.previewId)
}
