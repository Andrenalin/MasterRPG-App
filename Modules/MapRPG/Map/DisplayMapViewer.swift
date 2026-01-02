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
            MapViewer(image: image, photoDegrees: 0, map: mapUpdated, toolBarModel: GameToolBarModel(), playerPinId: nil, mapMode: .viewer, containerSize: size, focusedId: nil, sendMapUpdates: sendMapUpdates, focused: focused)
        }
        .frame(width: size.width, height: size.height)
        .onChange(of: root.itemController.itemOrEmpty(for: itemId).entries, initial: false) {
            Task { @MainActor in
                withAnimation { mapUpdated = map }
            }
        }
        .onChange(of: entryId, initial: true) {
            withAnimation { mapUpdated = map }
        }
    }

    private var map: MapModel {
        var map = root.itemController.itemOrEmpty(for: itemId)
        map.entries = map.entries.filter { $0.id == entryId }
        return map
    }

    private func focused() {}
    private func sendMapUpdates() {}
}
