// @copyright André Trettin

import CoreRPG
import SwiftUI
import PhotoRPG

@Observable
final class DropPinModel {
    var items: [ItemRowModel] = []
    var point: CGPoint = .zero
    var isTarget: Bool = false
}

struct RootCanvasMap: View {
    init(root: MapRootModel, itemId: UUID, mode: MapDisplayMode, toolBarModel: GameToolBarModel, playerPinId: UUID? = nil) {
        self.root = root
        self.itemId = itemId
        self.mode = mode
        if mode == .player {
            toolBarModel.displayMode = .player
        }
        self.toolBarModel = toolBarModel
        self.playerPinId = playerPinId
    }

    let root: MapRootModel
    let itemId: UUID
    let mode: MapDisplayMode
    let toolBarModel: GameToolBarModel
    let playerPinId: UUID?

    @Environment(\.networkActions) private var networkActions

    @State private var dropPinModel = DropPinModel()
    @State private var image: AKImage?
    @State private var degrees: Double = 0

    var body: some View {
        GeometryReader { geo in
            if let image {
                RootGameMapViewer(root: root, itemId: itemId, mode: mode, toolBarModel: toolBarModel, playerPinId: playerPinId, image: image, degrees: degrees, containerSize: geo.size)
                    .environment(dropPinModel)
            } else {
                Color.clear
            }
        }
        .onChange(of: mapModel.id, initial: true) {
            Task {
                await reloadImage()
            }
        }
        .onChange(of: mapModel.entries, initial: false) {
            guard image == nil else { return }
            Task {
                await reloadImage()
            }
        }
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

private extension RootCanvasMap {
    var mapModel: MapModel {
        root.gameController.gameItem(for: itemId)
    }

    func reloadImage() async {
        let (updateImage, updateDegrees) = await root.photoRoot.fetchPhotoImage(for: mapModel.photoId, useGame: true) ?? (nil, 0)
        Task {
            self.image = updateImage
            self.degrees <=> updateDegrees
        }
    }
}

#Preview {
    RootCanvasMap(root: .previewWithData, itemId: MapModel.previewId, mode: .master, toolBarModel: GameToolBarModel(), playerPinId: nil)
        .environment(MapRootModel.previewWithData)
}


struct RootGameMapViewer: View {
    init(root: MapRootModel, itemId: UUID, mode: MapDisplayMode, toolBarModel: GameToolBarModel, playerPinId: UUID?, image: AKImage, degrees: Double, containerSize: CGSize) {
        self.root = root
        self.itemId = itemId
        self.mode = mode
        self.toolBarModel = toolBarModel
        self.playerPinId = playerPinId
        self.image = image
        self.degrees = degrees
        self.containerSize = containerSize
    }

    let root: MapRootModel
    let itemId: UUID
    let mode: MapDisplayMode
    let toolBarModel: GameToolBarModel
    let playerPinId: UUID?
    let image: AKImage
    let degrees: Double
    let containerSize: CGSize
    
    @Environment(\.networkActions) private var networkActions


    var body: some View {
        MapViewer(image: image, photoDegrees: degrees, map: mapModel, toolBarModel: toolBarModel, playerPinId: playerPinId, mapMode: mode == .player ? .player : .gameMaster, containerSize: containerSize, sendMapUpdates: sendMapUpdates, focused: focused)
            .id(itemId)
    }
}

private extension RootGameMapViewer {
    var mapModel: MapModel {
        root.gameController.gameItem(for: itemId)
    }

    func sendMapUpdates() {
        if mode == .master {
            networkActions?.game(root.gameController.networkMapUpdate(for: itemId), .mapState, nil)
        } else {
            if mapModel.pointer.isShown {
                networkActions?.game(root.gameController.networkPin(itemId: itemId, position: mapModel.pointer), .mapPin, nil)
            } else {
                if let pin = mapModel.mapPins.first(where: { $0.id == playerPinId }) {
                    networkActions?.game(root.gameController.networkPin(itemId: itemId, position: pin), .mapPin, nil)
                }
            }
        }
    }

    func focused() {
        networkActions?.game(root.gameController.networkMapUpdate(for: itemId), .mapState, nil)
    }
}

