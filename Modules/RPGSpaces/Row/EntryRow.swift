// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct EntryRow: View {
    let item: ItemRowTreeModel
    let isSelected: Bool
    
    @Environment(SpaceRoot.self) private var root
    
    @Environment(\.gameModus) private var gameModus
    
    @State private var showImage = false
    @State private var showItem: Bool = false
    
    @State private var lastFileUrl: FileUrl?
    @State private var isLoading: Bool = false
    
    var itemId: UUID {
        item.model.entryId ?? item.model.itemId
    }
    
    var body: some View {
        @Bindable var model = root.itemController.itemOrEmpty(for: itemId)
        
        VStack(alignment: .leading) {
            showAndShareView
            
            RotatePhotoView(image: cachedImage, degrees: model.degrees)
        }
        .transition(.push(from: .leading))
        .animation(.linear, value: cachedImage)
        .onChange(of: model.fileUrl, initial: true) {
            guard !isLoading && (lastFileUrl != model.fileUrl || cachedImage == nil) else { return }
            isLoading = true
            lastFileUrl = model.fileUrl
            loadImage()
        }
    }
    
    private var cachedImage: AKImage? {
        cacheItemListModel.imageCache(cacheType: .image, itemId: itemId)
    }

    private var cacheItemListModel: CacheItemListModel {
        root.editController(type: .main).cacheItemListModel
    }
    
    private func loadImage() {
        Task { @MainActor in
            let loaderTask = Task.detached(priority: .userInitiated) {
                await root.cacheController?.thumbnailId(for: itemId, with: root.itemController.itemOrEmpty(for: itemId).fileUrl)
            }
            _ = await loaderTask.result
            let newImage = await root.cacheController?.thumbnail(for: itemId)
            withAnimation { cacheItemListModel.setImageCache(cacheType: .image, itemId: itemId, image: newImage) }
            isLoading = false
        }
    }
    
    private var showAndShareView: some View {
        SpaceQuickLook(root: root, item: ItemSelection(itemId: itemId, entryId: nil), startLoading: false, gameMode: false, dismiss: nil)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

#Preview {
    EntryRow(item: .preview, isSelected: true)
        .environment(SpaceRoot.preview)
}
