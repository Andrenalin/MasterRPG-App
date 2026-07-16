// @copyright André Trettin

import CoreRPG
import PhotoRPG
import SwiftUI

struct RootEditCanvasMap: View {
    init(
        itemId: UUID,
        isTileEditor: Bool = false,
        initialImage: AKImage? = nil,
        initialModel: MapModel? = nil,
        loadsImage: Bool = true
    ) {
        self.itemId = itemId
        self.isTileEditor = isTileEditor
        self.loadsImage = loadsImage
        self._image = State(wrappedValue: initialImage)
        self._model = State(wrappedValue: initialModel ?? .empty(itemId))
    }
    
    let itemId: UUID
    let isTileEditor: Bool
    private let loadsImage: Bool

    @Environment(MapRootModel.self) private var root

    @State private var image: AKImage?
    @State private var degrees: Double = 0
    @State private var dropPinModel = DropPinModel()
    @State private var model: MapModel

    var body: some View {
        GeometryReader { geo in
            if let image {
                MapEditor(editController: root.editController, image: image, photoDegrees: degrees, map: model, viewMode: .master, isTileEditor: isTileEditor, containerSize: geo.size)
                        .environment(dropPinModel)
            } else {
                Color.clear
            }
        }
        .onAppear {
#if os(iOS)
            root.editController.editorModel.deactivateEntryEditor = true
#endif
        }
        .onDisappear {
#if os(iOS)
            root.editController.editorModel.deactivateEntryEditor = false
#endif
        }
        .onChange(of: itemId, initial: true) {
            updateModel()
        }
        .onChange(of: root.itemController.itemOrEmpty(for: itemId).entries) {
            updateModel()
        }
        .onChange(of: model.photoId, initial: true) {
            guard loadsImage else { return }
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

#Preview(traits: .mockData) {
    RootEditCanvasMap(
        itemId: MapModel.previewId,
        initialModel: .preview,
        loadsImage: false
    )
}
