// @copyright André Trettin

import AndrenalinKit
import RPGPhotos
import SwiftUI

struct RootEditCanvasMap: View {
    let editController: EditController
    var tile: MapEntryModel?
    var isPinEdit: Bool = false

    @Environment(MapRootModel.self) private var root

    @State private var image: AKImage?
    @State private var degrees: Double = 0
    @State private var dropPinModel = DropPinModel()

    var body: some View {
        @Bindable var model = editController.model

        GeometryReader { geo in
            if let image {
                MapEditor(editController: editController, image: image, photoDegrees: degrees, map: model, viewMode: .master, tile: tile, isPinEdit: isPinEdit, containerSize: geo.size)
                        .environment(dropPinModel)
            } else {
                Color.clear
            }
        }
        .onChange(of: model.photoId, initial: true) {
            Task {
                await reloadImage()
            }
        }
    }

    func reloadImage() async {
        let (updateImage, updateDegrees) = await root.photoRoot.fetchPhotoImage(for: editController.model.photoId, useGame: false) ?? (nil, 0)
        Task { @MainActor in
            self.image = updateImage
            self.degrees <=> updateDegrees
        }
    }
}
