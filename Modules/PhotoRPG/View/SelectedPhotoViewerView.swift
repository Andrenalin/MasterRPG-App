// @copyright André Trettin

import CoreRPG
import SwiftUI

struct SelectedPhotoViewerView: View {
    let model: PhotoModel
    
    @Environment(PhotoRootModel.self) var root
    @Environment(GroupItemSelectionModel.self) var selection
    
    var body: some View {
        ViewerRootView(model: selectedModel, externalViewer: false)
            .id(selection.selectedItem ?? model.id)
    }
    
    var selectedModel: PhotoModel {
        item ?? model
    }
    
    var item: PhotoModel? {
        guard let id = selection.selectedItem else { return nil }
        return root.itemController.itemSync(for: id)
    }
}
