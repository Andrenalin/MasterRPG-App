// @copyright André Trettin

import CoreRPG
import SwiftUI
import PhotoRPG

@MainActor
struct ViewerRootView: View {
    let model: ValueModel
    let dismissAction: (() -> Void)?
    
    @Environment(CharacterRootModel.self) private var root

    @State private var sheetModel: SheetModel = SheetModel.empty
    
    var body: some View {
        TableRootSheet(root: root.rootController, model: sheetModel, dismissAction: dismissAction)
            .onChange(of: model, initial: true) {
                resetModels()
            }
    }

    func resetModels() {
        withAnimation {
            sheetModel = SheetController(itemController: root.itemController, linkController: root.linkController).sheet(for: model.id)
        }
    }
}

#Preview {
    ViewerRootView(model: .preview, dismissAction: nil)
        .environment(CharacterRootModel.previewWithData)
}
