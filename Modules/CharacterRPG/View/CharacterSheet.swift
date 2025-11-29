// @copyright André Trettin

import CoreRPG
import SwiftUI
import PhotoRPG

@MainActor
struct CharacterSheet: View {
    let model: ValueModel
    let showTopImage: Bool
    let dismissAction: (() -> Void)?
    
    @Environment(CharacterRootModel.self) private var root

    @State private var sheetModel: SheetModel = SheetModel(id: UUID(), name: "", description: "", groups: [])
    
    var body: some View {
        TableRootSheet(linkControllable: root.rootControllable.linkControllable, model: sheetModel, showImage: showTopImage, dismissAction: dismissAction, imageContent: imageView(size:))
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

private extension CharacterSheet {
    func imageView(size: CGSize) -> some View {
        root.photoRoot.viewController.photoDetailView(root: root.photoRoot, for: model.photoId, useGame: false, size: size)
    }
}

#Preview {
    CharacterSheet(model: .preview, showTopImage: false, dismissAction: nil)
        .environment(CharacterRootModel.previewWithData)
}
