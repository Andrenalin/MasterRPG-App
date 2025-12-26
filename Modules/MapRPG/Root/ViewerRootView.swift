// @copyright André Trettin

import CoreRPG
import SwiftUI
import PhotoRPG

struct ViewerRootView: View {
    let model: MapModel
    var dismissAction: (() -> Void)? = nil

    @Environment(MapRootModel.self) private var root

    @State private var sheetModel: SheetModel = SheetModel.empty

    var body: some View {
        TableRootSheet(root: root.rootController, model: sheetModel, dismissAction: dismissAction, imageContent: imageView(size:))
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

#Preview(traits: .mockData) {
    @Previewable @Environment(MapRootModel.self) var root
    ManagedNavigationStack {
        ViewerRootView(model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? MapModel.previewId))
            .preferredColorScheme(.dark)
    }
}
