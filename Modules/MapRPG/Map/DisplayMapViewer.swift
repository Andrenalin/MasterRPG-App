// @copyright André Trettin

import CoreRPG
import SwiftUI
import PhotoRPG

struct DisplayMapViewer: View {
    let image: AKImage
    let itemId: UUID
    @Binding var entryId: UUID
    let size: CGSize

    @Environment(MapRootModel.self) private var root
    @State private var mapUpdated: MapModel = .empty

    var body: some View {
        VStack {
            MapEditor(editController: root.editController, image: image, photoDegrees: 0, map: mapUpdated, viewMode: .master, containerSize: size, mapMode: .viewer, sendMapUpdates: sendMapUpdates, focused: focused)
        }
        .frame(width: size.width, height: size.height)
        .onChange(of: root.itemController.itemOrEmpty(for: itemId).entries, initial: false) {
            Task {
                withAnimation { mapUpdated = map }
            }
        }
        .onChange(of: entryId, initial: true) {
            withAnimation { mapUpdated = map }
        }
    }

    private var map: MapModel {
        let map = root.itemController.itemOrEmpty(for: itemId)
        map.entries = map.entries.filter { $0.id == entryId }
        return map
    }

    private func focused() {}
    private func sendMapUpdates() {}
}
