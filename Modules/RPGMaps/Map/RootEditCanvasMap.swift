// @copyright André Trettin

import AndrenalinKit
import RPGPhotos
import SwiftUI

struct RootEditCanvasMap: View {
    let editController: EditController
    var tile: MapEntryModel?
    var isPinEdit: Bool = false

    @Environment(MapRoot.self) private var root

    var body: some View {
        @Bindable var model = editController.model

        GeometryReader { geo in
            root.photoRoot.viewController.photoView(for: model.photoId, useGame: false) { image, photoDegrees in
                MapEditor(editController: editController, image: image, photoDegrees: photoDegrees, map: model, viewMode: .master, tile: tile, isPinEdit: isPinEdit, containerSize: geo.size)
                    .environment(DropPinModel())
            }
        }
    }
}
