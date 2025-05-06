// @copyright André Trettin

import AndrenalinKit
import SwiftUI
import RPGPhotos

struct DisplayMapViewer: View {
    let editController: EditController
    let itemId: UUID
    @Binding var entryId: UUID
    let size: CGSize

    @Environment(MapRoot.self) private var root
    @State private var mapUpdated: MapModel = .empty

    var body: some View {
        @Bindable var model = editController.model
        VStack {
            root.photoRoot.viewController.photoView(for: model.photoId, useGame: false) { image, photoDegrees in
                MapViewer(image: image, photoDegrees: photoDegrees, map: mapUpdated, toolBarModel: GameToolBarModel(), playerPinId: nil, mapMode: .viewer, containerSize: size, focusedId: nil, sendMapUpdates: sendMapUpdates, focused: focused)
            }
        }
        .frame(width: size.width, height: size.height)
        .onChange(of: model, initial: false) {
            Task { @MainActor in
                withAnimation { mapUpdated = map }
            }
        }
        .onChange(of: entryId, initial: true) {
            withAnimation { mapUpdated = map }
        }
    }

    private var map: MapModel {
        let map = editController.model.copy()
        map.entries = map.entries.filter { $0.id == entryId }
        return map
    }

    private func focused() {}
    private func sendMapUpdates() {}
}
