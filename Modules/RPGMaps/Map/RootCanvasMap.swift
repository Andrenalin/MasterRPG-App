// @copyright André Trettin

import AndrenalinKit
import SwiftUI

@Observable
final class DropPinModel {
    var items: [ItemRowModel] = []
    var point: CGPoint = .zero
    var isTarget: Bool = false
}

struct RootCanvasMap: View {
    init(root: MapRoot, itemId: UUID, mode: MapDisplayMode, toolBarModel: GameToolBarModel, playerPinId: UUID? = nil) {
        self.root = root
        self.itemId = itemId
        self.mode = mode
        if mode == .player {
            toolBarModel.displayMode = .player
        }
        self.toolBarModel = toolBarModel
        self.playerPinId = playerPinId
    }

    let root: MapRoot
    let itemId: UUID
    let mode: MapDisplayMode
    let toolBarModel: GameToolBarModel
    let playerPinId: UUID?

    @Environment(\.networkActions) private var networkActions

    @State private var dropPinModel = DropPinModel()

    var body: some View {
        GeometryReader { geo in
            root.photoRoot.viewController.photoView(for: mapModel.photoId, useGame: true) { image, photoDegrees in
                MapViewer(image: image, photoDegrees: photoDegrees, map: mapModel, toolBarModel: toolBarModel, playerPinId: playerPinId, mapMode: mode == .player ? .player : .gameMaster, containerSize: geo.size, sendMapUpdates: sendMapUpdates, focused: focused)
                    .id(itemId)
                    .environment(dropPinModel)
            }
            .id(itemId)
#if !os(tvOS)
            .dropDestination(for: LinkData.self) { items, point in
                let dropItems = items.filter { $0.module == .value && $0.entryId == nil }.map { ItemRowModel(itemId: $0.itemId, typeId: $0.module )}
                guard !dropItems.isEmpty else { return false }
                dropPinModel.point = point
                dropPinModel.items = dropItems
                return true
            } isTargeted: { inDropArea in
                dropPinModel.isTarget = inDropArea
            }
#endif
        }
    }
}

private extension RootCanvasMap {
    var mapModel: MapModel {
        root.gameController.gameItem(for: itemId)
    }

    func sendMapUpdates() {
        if mode == .master {
            networkActions?.game(root.gameController.networkMapUpdate(for: itemId), .mapState)
        } else {
            if mapModel.pointer.isShown {
                networkActions?.game(root.gameController.networkPin(itemId: itemId, position: mapModel.pointer), .mapPin)
            } else {
                if let pin = mapModel.mapPins.first(where: { $0.id == playerPinId }) {
                    networkActions?.game(root.gameController.networkPin(itemId: itemId, position: pin), .mapPin)
                }
            }
        }
    }

    func focused() {
        networkActions?.game(root.gameController.networkMapUpdate(for: itemId), .mapState)
    }
}

#Preview {
    RootCanvasMap(root: .previewWithData, itemId: MapModel.previewId, mode: .master, toolBarModel: GameToolBarModel(), playerPinId: nil)
        .environment(MapRoot.previewWithData)
}
