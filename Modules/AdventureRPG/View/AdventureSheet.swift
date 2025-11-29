// @copyright André Trettin

import CoreRPG
import SwiftUI
import PhotoRPG

struct AdventureSheet: View {
    let model: AdventureModel
    let dismissAction: (() -> Void)?

    @Environment(AdventureRootModel.self) private var root

    @State private var sheetModel: SheetModel = SheetModel(id: UUID(), name: "", description: "", groups: [])

    var body: some View {
        TableRootSheet(linkControllable: root.linkControllable, model: sheetModel, showImage: true, dismissAction: dismissAction, imageContent: imageView(size:))
            .onChange(of: model, initial: true) {
                resetModels()
            }
    }

    func resetModels() {
        withAnimation {
            sheetModel = SheetController(itemController: root.itemController).sheet(for: model.id)
        }
    }

    func imageView(size: CGSize) -> some View {
        root.photoRoot.viewController.photoDetailView(root: root.photoRoot, for: model.photoId, useGame: false, size: size) 
    }
}

struct TableGameSheet: View {
    @Environment(AdventureRootModel.self) private var root

    @State private var model: AdventureModel = .empty

    var body: some View {
        AdventureSheet(model: model, dismissAction: nil)
            .padding(32)
            .onChange(of: root.gameController.gameModel.currentItemId) {
                model = root.gameController.currentItem()
            }
    }
}

#Preview {
    TableGameSheet()
        .environment(AdventureRootModel.previewWithData)

}
