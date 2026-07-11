// @copyright André Trettin

import CoreRPG
import SwiftUI

struct AsyncThumbnail: View {
    let itemId: UUID?
    let size: CGSize
    let color: Color

    @Environment(PhotoRootModel.self) private var root

    @State private var lastFileUrl: FileUrl?
    @State private var isLoading: Bool = false

    var body: some View {
        if let itemId {
            let model = root.gameController.gameItem(for: itemId)
            Group {
                if let image = cachedImage(for: model.id) {
                    Image(akImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    placeholderView
                }
            }
            .task(id: loadKey(for: model)) {
                await initImage(for: model)
            }
        } else {
            placeholderView
        }
    }
}

// MARK: - Private Helpers

private struct AsyncThumbnailLoadKey: Equatable {
    let itemId: UUID
    let fileUrl: FileUrl?
    let hasInlineData: Bool
}

private extension AsyncThumbnail {
    /// Synchronously access the cached thumbnail from the observable cache
    func cachedImage(for itemId: UUID) -> AKImage? {
        root.itemController.cacheController?.cachedThumbnail(for: itemId)
    }

    func loadKey(for model: PhotoModel) -> AsyncThumbnailLoadKey {
        AsyncThumbnailLoadKey(
            itemId: model.id,
            fileUrl: model.fileUrl,
            hasInlineData: model.fileUrl?.data != nil
        )
    }
    
    @ViewBuilder
    var placeholderView: some View {
        if isLoading {
            ProgressView()
                .tint(color)
        } else {
            color
        }
    }
    
    /// Initialize image loading with deduplication
    func initImage(for model: PhotoModel) async {
        guard model.fileUrl != nil else { return }
        // Avoid redundant loads once this URL already has an observable cached image.
        guard lastFileUrl != model.fileUrl || cachedImage(for: model.id) == nil else { return }
        
        isLoading = true
        lastFileUrl = model.fileUrl
        await loadImage(for: model)
    }
    
    /// Load the thumbnail asynchronously and update the observable cache
    func loadImage(for model: PhotoModel) async {
        guard let cacheController = root.itemController.cacheController else {
            isLoading = false
            return
        }
        
        let id = model.id
        
        // Trigger thumbnail creation if needed
        await cacheController.thumbnailId(for: id, item: model)
        
        // Retrieve the thumbnail
        let newImage = await cacheController.thumbnail(for: id)
        
        // Update the observable cache so all views can access it
        await MainActor.run {
            cacheController.setCachedThumbnail(newImage, for: id)
            isLoading = false
        }
    }
}

#Preview {
    AsyncThumbnail(itemId: PhotoModel.preview.id, size: CGSize(width: 128, height: 128), color: .gray)
        .environment(PhotoRootModel.preview)
        .frame(width: 256, height: 256)
}
