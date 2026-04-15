// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailRootView: View {
    let root: PhotoRootModel
    let model: PhotoModel
    
    @Environment(AppWindowSizeModel.self) private var appSizeModel
    
    var body: some View {
        DetailListView(root: root, model: model)
            .detailInspectorModifier()
            .applyIf(appSizeModel.mode == .regular) {
                $0.task(id: model.id) {
                    root.navigationModel.folderItems = []
                    root.navigationModel.folderModels = [:]
                }
            }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(PhotoRootModel.self) var root
    
    ManagedNavigationStack {
        DetailRootView(root: root, model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? PhotoRootModel.previewPhotoId))
            .preferredColorScheme(.dark)
    }
}
