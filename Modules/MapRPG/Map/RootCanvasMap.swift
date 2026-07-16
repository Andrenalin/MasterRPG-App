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
        initialImage: AKImage? = nil,
        initialDegrees: Double = 0,
        loadsImage: Bool = true
    ) {
        self.root = root
        self.itemId = itemId
        self.mode = mode
        self.playerPinId = playerPinId
        self.loadsImage = loadsImage
        self._image = State(wrappedValue: initialImage)
        self._degrees = State(wrappedValue: initialDegrees)
    }

    let root: MapRootModel
    let itemId: UUID
    let mode: MapDisplayMode
    let playerPinId: UUID?
    private let loadsImage: Bool

    @Environment(\.networkActions) private var networkActions

    @State private var dropPinModel = DropPinModel()
    @State private var image: AKImage?
    @State private var degrees: Double = 0

    var body: some View {
        GeometryReader { geo in
            if let image {
                RootGameMapViewer(root: root, itemId: itemId, mode: mode, playerPinId: playerPinId, image: image, degrees: degrees, containerSize: geo.size)
                    .environment(dropPinModel)
            } else {
                Color.clear
            }
        }
        .onChange(of: mapModel.id, initial: true) {
            guard loadsImage else { return }
            Task { await reloadImage() }
        }
        .onChange(of: mapModel.entries, initial: false) {
            guard loadsImage, image == nil else { return }
            Task { await reloadImage() }
        }
        .onChange(of: photoFileUrl, initial: false) {
            guard loadsImage else { return }
            // The background photo can arrive after the map (game re-request) —
            // reload when its file lands or changes, or the map stays black.
            Task { await reloadImage() }
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

    func reloadImage() async {
        let (updateImage, updateDegrees) = await root.photoRoot.fetchPhotoImage(for: mapModel.photoId, useGame: true) ?? (nil, 0)
        Task {
            self.image = updateImage
            self.degrees <=> updateDegrees
        }
    }
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
