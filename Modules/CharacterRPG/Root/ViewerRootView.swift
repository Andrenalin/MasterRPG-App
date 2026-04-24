// @copyright André Trettin

import CoreRPG
import SwiftUI
import PhotoRPG

@MainActor
struct ViewerRootView: View {
    let model: ValueModel
    let configuration: ViewerConfiguration
    let dismissAction: (() -> Void)?
    
    @Environment(CharacterRootModel.self) private var root

    var body: some View {
        TableRootSheet(root: root.rootController, itemId: model.id, module: root.config.module, configuration: configuration, dismissAction: dismissAction)
            .id(model.id)
    }
}

#Preview {
    ViewerRootView(model: .preview, configuration: ViewerConfiguration(), dismissAction: nil)
        .environment(CharacterRootModel.previewWithData)
}
