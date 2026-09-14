// @copyright André Trettin

import CoreRPG
import SwiftUI

struct AsyncThumbnail: View {
    let itemId: UUID?
    let size: CGSize
    let color: Color

    @Environment(PhotoRootModel.self) private var root

    @State private var renderedImage: AKImage?
    @State private var renderedImageKey: AsyncThumbnailLoadKey?
    @State private var lastLoadKey: AsyncThumbnailLoadKey?
    @State private var isLoading: Bool = false

    var body: some View {
        Group {
            if let itemId {
                let model = root.gameController.gameItem(for: itemId)
                let key = loadKey(for: model)
                Group {
                    if renderedImageKey == key, let renderedImage {
                        Image(akImage: renderedImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        AsyncThumbnailPlaceholderView(isLoading: isLoading, color: color)
                    }
                }
                .task(id: key) {
                    await initImage(for: model, key: key)
                }
            } else {
                AsyncThumbnailPlaceholderView(isLoading: isLoading, color: color)
            }
        }
        .onChange(of: itemId) { _, newItemId in
            guard newItemId == nil else { return }
            renderedImage = nil
            renderedImageKey = nil
            lastLoadKey = nil
            isLoading = false
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

extension AsyncThumbnail {
    nonisolated static let fullImageMinimumSide: CGFloat = 160

    nonisolated static func shouldUseFullImage(for size: CGSize) -> Bool {
        max(size.width, size.height) >= fullImageMinimumSide
    }
}

private extension AsyncThumbnail {
    /// Zoomed map pins need more than the shared 64-point list thumbnail.
    /// Reuse the full-photo cache only for those large presentations; ordinary
    /// pins stay on the cheaper thumbnail path.
    var usesFullImage: Bool {
        Self.shouldUseFullImage(for: size)
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
    
    /// Initialize image loading with deduplication
    func initImage(for model: PhotoModel, key: AsyncThumbnailLoadKey) async {
        if let cachedImage = cachedImage(for: model.id) {
            guard !Task.isCancelled else { return }
            renderedImage = cachedImage
            renderedImageKey = key
            lastLoadKey = key
            isLoading = false
            return
        }

        guard model.fileUrl != nil else {
            renderedImage = nil
            renderedImageKey = nil
            lastLoadKey = key
            isLoading = false
            return
        }
        guard lastLoadKey != key || renderedImageKey != key else {
            isLoading = false
            return
        }

        renderedImage = nil
        renderedImageKey = nil
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
        renderedImage = newImage
        renderedImageKey = newImage == nil ? nil : key
        isLoading = false
    }
}

// MARK: - Extracted subviews (CODE_AUDIT §8.3)
//
// Gives SwiftUI its own diffing boundary, instead of the previous computed
// `some View` property on `AsyncThumbnail` itself.

private struct AsyncThumbnailPlaceholderView: View {
    let isLoading: Bool
    let color: Color

    @ViewBuilder
    var body: some View {
        if isLoading {
            ProgressView()
                .tint(color)
        } else {
            color
        }
    }
}

#Preview {
    AsyncThumbnail(itemId: PhotoModel.preview.id, size: CGSize(width: 128, height: 128), color: .gray)
        .environment(PhotoRootModel.preview)
        .frame(width: 256, height: 256)
}
