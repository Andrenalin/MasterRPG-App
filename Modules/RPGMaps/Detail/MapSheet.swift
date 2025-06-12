// @copyright André Trettin

import AndrenalinKit
import SwiftUI
import RPGPhotos

struct MapSheet: View {
    let model: MapModel
    let showTopImage: Bool
    let dismissAction: (() -> Void)?

    @Environment(MapRoot.self) private var root

    @State private var sheetModel: SheetModel = SheetModel(id: UUID(), name: "", description: "", groups: [])

    var body: some View {
        TableRootSheet(linkControllable: root.rootControllable.linkControllable, model: sheetModel, showImage: showTopImage, dismissAction: dismissAction, imageContent: imageView(size:))
            .onChange(of: model, initial: true) {
                resetModels()
            }
    }

    func resetModels() {
        withAnimation {
            sheetModel = SheetController(root: root).sheet(for: model.id)
        }
    }

    func imageView(size: CGSize) -> some View {
        root.photoRoot.viewController.photoDetailView(for: model.photoId, useGame: false, size: size)
    }
}
