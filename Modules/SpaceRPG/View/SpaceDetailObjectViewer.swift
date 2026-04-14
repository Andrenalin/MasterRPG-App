// @copyright André Trettin

import CoreRPG
import SwiftUI

struct SpaceDetailObjectViewer: View {
    let editController: EditController
    let model: SpaceModel
    
    @Environment(SpaceRootModel.self) private var root
    @Environment(GroupItemSelectionModel.self) private var selection
    
    var body: some View {
        ViewerRootView(model: selectedModel, configuration: ViewerConfiguration(closeButton: false, addToolbar: false, isGame: false))
            .id(selectedModel.id)
    }
    
    private var selectedModel: SpaceModel {
        guard let itemId = selection.selectedItem else { return model }
        return root.itemController.itemOrEmpty(for: itemId)
    }
}
