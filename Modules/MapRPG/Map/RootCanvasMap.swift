// @copyright André Trettin

import CoreRPG
import SwiftUI
import PhotoRPG

@MainActor @Observable
final class DropPinModel {
    var items: [ItemRowModel] = []
    var point: CGPoint = .zero
    var isTarget: Bool = false
}

struct RootCanvasMap: View {
    init(
        root: MapRootModel,
        itemId: UUID,
        mode: MapDisplayMode,
        playerPinId: UUID? = nil,
        registersGameToolbarSession: Bool = true,
        initialImage: AKImage? = nil,
        initialDegrees: Double = 0,
        loadsImage: Bool = true
    ) {
        self.root = root
        self.itemId = itemId
        self.mode = mode
        self.playerPinId = playerPinId
        self.registersGameToolbarSession = registersGameToolbarSession
        self.loadsImage = loadsImage
        self._image = State(wrappedValue: initialImage)
        self._degrees = State(wrappedValue: initialDegrees)
    }

    let root: MapRootModel
    let itemId: UUID
    let mode: MapDisplayMode
    let playerPinId: UUID?
    let registersGameToolbarSession: Bool
    private let loadsImage: Bool

    @State private var dropPinModel = DropPinModel()
    @State private var image: AKImage?
    @State private var degrees: Double = 0

    var body: some View {
        ZStack {
            if let image {
                RootGameMapViewer(
                    root: root,
                    itemId: itemId,
                    mode: mode,
                    playerPinId: playerPinId,
                    registersGameToolbarSession: registersGameToolbarSession,
                    image: image,
                    degrees: degrees
                )
                .environment(dropPinModel)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: imageLoadIdentity) {
            guard loadsImage else { return }
            await reloadImage(for: imageLoadIdentity)
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

    var photoFileUrl: FileUrl? {
        guard let photoId = mapModel.photoId else { return nil }
        return root.photoRoot.itemControllable.itemSync(for: photoId)?.fileUrl
    }

    var imageLoadIdentity: GameMapImageLoadIdentity {
        GameMapImageLoadIdentity(
            mapId: mapModel.id,
            photoId: mapModel.photoId,
            photoFileUrl: photoFileUrl
        )
    }

    func reloadImage(for identity: GameMapImageLoadIdentity) async {
        let (updateImage, updateDegrees) = await root.photoRoot.fetchPhotoImage(
            for: identity.photoId,
            useGame: true
        ) ?? (nil, 0)
        guard !Task.isCancelled, imageLoadIdentity == identity else { return }
        image = updateImage
        degrees <=> updateDegrees
    }
}

private struct GameMapImageLoadIdentity: Hashable {
    let mapId: UUID
    let photoId: UUID?
    let photoFileUrl: FileUrl?
}

#Preview(traits: .mockData) {
    RootCanvasMap(
        root: .previewFixture(),
        itemId: MapModel.previewId,
        mode: .master,
        playerPinId: nil,
        initialImage: AKImage(),
        loadsImage: false
    )
}
