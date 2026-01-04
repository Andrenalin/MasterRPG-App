// @copyright André Trettin

import CoreRPG
import SwiftUI
import PhotoRPG

@MainActor
struct ViewerRootView: View {
    let model: ValueModel
    let dismissAction: (() -> Void)?
    
    @Environment(CharacterRootModel.self) private var root

    var body: some View {
        TableRootSheet(root: root.rootController, itemId: model.id, module: root.config.module, dismissAction: dismissAction)
    }
}

#Preview {
    ViewerRootView(model: .preview, dismissAction: nil)
        .environment(CharacterRootModel.previewWithData)
}
