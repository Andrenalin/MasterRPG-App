// @copyright André Trettin

import CoreRPG
import PhotoRPG
import SwiftUI

struct RootEditCanvasMap: View {
    init(itemId: UUID, tile: MapEntryModel? = nil, isPinEdit: Bool = false) {
        self.itemId = itemId
        self.tile = tile
        self.isPinEdit = isPinEdit
    }
    
    let itemId: UUID
    var tile: MapEntryModel?
    var isPinEdit: Bool = false

    @Environment(MapRootModel.self) private var root

    @State private var image: AKImage?
    @State private var degrees: Double = 0
    @State private var dropPinModel = DropPinModel()
    @State private var model: MapModel = .empty

    var body: some View {
        GeometryReader { geo in
            if let image {
                MapEditor(editController: root.editController, image: image, photoDegrees: degrees, map: model, viewMode: .master, tile: tile, isPinEdit: isPinEdit, containerSize: geo.size)
                        .environment(dropPinModel)
            } else {
                Color.clear
            }
        }
        .onChange(of: itemId, initial: true) {
            updateModel()
        }
        .onChange(of: root.itemController.itemOrEmpty(for: itemId).entries) {
            updateModel()
        }
        .onChange(of: model.photoId, initial: true) {
            Task {
                await reloadImage()
            }
        }
#if !os(tvOS)
        .dropDestination(for: LinkCharacterData.self) { items, point in
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
    
    func updateModel() {
        let updatedModel = root.itemController.itemOrEmpty(for: itemId)
        if model.id != updatedModel.id || !model.isSame(updatedModel) {
            withAnimation {
                model = updatedModel
            }
        }
    }

    func reloadImage() async {
        let (updateImage, updateDegrees) = await root.photoRoot.fetchPhotoImage(for: model.photoId, useGame: false) ?? (nil, 0)
        Task {
            self.image = updateImage
            self.degrees <=> updateDegrees
        }
    }
}
