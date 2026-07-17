// @copyright André Trettin

import CoreRPG
import SwiftUI

struct AsyncThumbnail: View {
    let itemId: UUID?
    let size: CGSize
    let color: Color

    @Environment(PhotoRootModel.self) private var root

    @State private var lastLoadKey: AsyncThumbnailLoadKey?
    @State private var isLoading: Bool = false

    var body: some View {
        if let itemId {
            let model = root.gameController.gameItem(for: itemId)
            let key = loadKey(for: model)
            Group {
                if let image = cachedImage(for: model.id) {
                    Image(akImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    placeholderView
                }
            }
            .task(id: key) {
                await initImage(for: model, key: key)
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
    let usesFullImage: Bool
    let version: Int
}

private extension AsyncThumbnail {
    /// Zoomed map pins need more than the shared 64-point list thumbnail.
    /// Reuse the full-photo cache only for those large presentations; ordinary
    /// pins stay on the cheaper thumbnail path.
    var usesFullImage: Bool {
        max(size.width, size.height) > 64
    }

    /// Synchronously access the appropriate observable cache.
    func cachedImage(for itemId: UUID) -> AKImage? {
        guard let cacheController = root.itemController.cacheController else { return nil }
        return usesFullImage
            ? cacheController.cachedImage(for: itemId)
            : cacheController.cachedThumbnail(for: itemId)
    }

    func loadKey(for model: PhotoModel) -> AsyncThumbnailLoadKey {
        AsyncThumbnailLoadKey(
            itemId: model.id,
            fileUrl: model.fileUrl,
            hasInlineData: model.fileUrl?.data != nil,
            usesFullImage: usesFullImage,
            version: model.version
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
    func initImage(for model: PhotoModel, key: AsyncThumbnailLoadKey) async {
        guard model.fileUrl != nil else {
            lastLoadKey = key
            isLoading = false
            return
        }
        // Avoid redundant loads once this exact image/version/quality request
        // already has an observable cached image.
        guard lastLoadKey != key || cachedImage(for: model.id) == nil else {
            isLoading = false
            return
        }
        
        isLoading = true
        lastLoadKey = key
        await loadImage(for: model, key: key)
    }
    
    /// Load the thumbnail asynchronously and update the observable cache
    func loadImage(for model: PhotoModel, key: AsyncThumbnailLoadKey) async {
        guard let cacheController = root.itemController.cacheController else {
            if lastLoadKey == key { isLoading = false }
            return
        }
        
        let id = model.id
        
        let newImage: AKImage?
        if key.usesFullImage {
            await cacheController.photoId(for: id, item: model)
            newImage = await cacheController.photo(for: id)
        } else {
            await cacheController.thumbnailId(for: id, item: model)
            newImage = await cacheController.thumbnail(for: id)
        }
        
        guard !Task.isCancelled, lastLoadKey == key else { return }

        // Update the observable cache so all views can access it. Checking the
        // task generation above prevents an older item/size request from
        // clearing the current request's loading state.
        if key.usesFullImage {
            cacheController.setCachedImage(newImage, for: id)
        } else {
            cacheController.setCachedThumbnail(newImage, for: id)
        }
        isLoading = false
    }
}

#Preview {
    AsyncThumbnail(itemId: PhotoModel.preview.id, size: CGSize(width: 128, height: 128), color: .gray)
        .environment(PhotoRootModel.preview)
        .frame(width: 256, height: 256)
}
