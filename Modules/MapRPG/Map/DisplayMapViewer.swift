// @copyright André Trettin

import AndrenalinKit
import SwiftUI
import PhotoRPG

struct DisplayMapViewer: View {
    let editController: EditController
    let image: AKImage
    let itemId: UUID
    @Binding var entryId: UUID
    let size: CGSize

    @Environment(MapRootModel.self) private var root
    @State private var mapUpdated: MapModel = .empty

    var body: some View {
        @Bindable var model = editController.model
        VStack {
            MapViewer(image: image, photoDegrees: 0, map: mapUpdated, toolBarModel: GameToolBarModel(), playerPinId: nil, mapMode: .viewer, containerSize: size, focusedId: nil, sendMapUpdates: sendMapUpdates, focused: focused)
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
