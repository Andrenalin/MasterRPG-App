// @copyright André Trettin

import CoreRPG
import SwiftUI

struct RootGameMapViewer: View {
    let root: MapRootModel
    let itemId: UUID
    let mode: MapDisplayMode
    let playerPinId: UUID?
    let image: AKImage
    let degrees: Double
    let containerSize: CGSize

    @Environment(\.networkActions) private var networkActions

    var body: some View {
        MapEditor(
            editController: root.editController,
            image: image,
            photoDegrees: degrees,
            map: mapModel,
            viewMode: mode == .player ? .player : .master,
            containerSize: containerSize,
            mapMode: mode == .player ? .player : .gameMaster,
            playerPinId: playerPinId,
            sendMapUpdates: sendMapUpdates,
            focused: focused
        )
        .id(itemId)
    }

    private var mapModel: MapModel {
        root.gameController.gameItem(for: itemId)
    }

    private func sendMapUpdates() {
        if mode == .master {
            networkActions?.game(root.gameController.networkMapUpdate(for: itemId), .mapState, nil)
        } else if mapModel.pointer.isShown {
            networkActions?.game(root.gameController.networkPin(itemId: itemId, position: mapModel.pointer), .mapPin, nil)
        } else if let pin = mapModel.mapPins.first(where: { $0.id == playerPinId }) {
            networkActions?.game(root.gameController.networkPin(itemId: itemId, position: pin), .mapPin, nil)
        }
    }

    private func focused() {
        networkActions?.game(root.gameController.networkMapUpdate(for: itemId), .mapState, nil)
    }
}

#Preview(traits: .mockData) {
    RootGameMapViewer(
        root: .previewFixture(),
        itemId: MapModel.previewId,
        mode: .master,
        playerPinId: nil,
        image: AKImage(systemName: "photo") ?? AKImage(),
        degrees: 0,
        containerSize: CGSize(width: 600, height: 400)
    )
    .environment(DropPinModel())
}
