// @copyright André Trettin

import CoreRPG
import SwiftUI

struct RootGameMapViewer: View {
    init(
        root: MapRootModel,
        itemId: UUID,
        mode: MapDisplayMode,
        playerPinId: UUID?,
        registersGameToolbarSession: Bool = true,
        trailingViewportReservation: CGFloat = 0,
        image: AKImage,
        degrees: Double
    ) {
        self.root = root
        self.itemId = itemId
        self.mode = mode
        self.playerPinId = playerPinId
        self.registersGameToolbarSession = registersGameToolbarSession
        self.trailingViewportReservation = trailingViewportReservation
        self.image = image
        self.degrees = degrees
    }

    let root: MapRootModel
    let itemId: UUID
    let mode: MapDisplayMode
    let playerPinId: UUID?
    let registersGameToolbarSession: Bool
    let trailingViewportReservation: CGFloat
    let image: AKImage
    let degrees: Double

    @Environment(\.networkActions) private var networkActions

    var body: some View {
        MapEditor(
            editController: root.editController,
            image: image,
            photoDegrees: degrees,
            map: mapModel,
            trailingViewportReservation: trailingViewportReservation,
            configuration: MapEditorConfiguration(
                mode: mode == .player ? .player : .gameMaster,
                displayMode: mode == .player ? .player : .master,
                playerPinId: playerPinId,
                registersGameToolbarSession: registersGameToolbarSession
            ),
            actions: MapEditorActions(
                sendMapUpdates: sendMapUpdates,
                sendPinUpdate: sendPinUpdate,
                focused: focused
            )
        )
        .id(itemId)
    }

    private var mapModel: MapModel {
        root.gameController.gameItem(for: itemId)
    }

    private func sendMapUpdates() {
        if mode == .master {
            _ = root.mapGameControllable.synchronizeBattleDefenders(itemId: itemId)
            networkActions?.game(root.gameController.networkMapUpdate(for: itemId), .mapState, nil)
        } else if mapModel.pointer.isShown {
            networkActions?.game(root.gameController.networkPin(itemId: itemId, position: mapModel.pointer), .mapPin, nil)
        } else if let pin = mapModel.mapPins.first(where: { $0.id == playerPinId }) {
            networkActions?.game(root.gameController.networkPin(itemId: itemId, position: pin), .mapPin, nil)
        }
    }

    private func sendPinUpdate(_ pinId: UUID) {
        guard mode == .player,
              let update = root.gameController.networkPin(itemId: itemId, pinId: pinId) else { return }
        networkActions?.game(update, .mapPin, nil)
    }

    private func focused() {
        guard mode == .master else { return }
        networkActions?.game(root.gameController.networkMapUpdate(for: itemId), .mapState, nil)
    }
}

#if !os(macOS)
#Preview(traits: .mockData) {
    RootGameMapViewer(
        root: .previewFixture(),
        itemId: MapModel.previewId,
        mode: .master,
        playerPinId: nil,
        registersGameToolbarSession: true,
        image: AKImage(systemName: "photo") ?? AKImage(),
        degrees: 0
    )
    .environment(DropPinModel())
}
#endif
