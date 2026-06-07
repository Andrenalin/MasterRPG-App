// @copyright André Trettin

import CoreRPG
import SwiftUI

struct AsyncThumbnail: View {
    let model: PhotoModel
    let size: CGSize
    let color: Color

    @Environment(PhotoRootModel.self) private var root

    @State private var lastFileUrl: FileUrl?
    @State private var isLoading: Bool = false

    var body: some View {
        @Bindable var model = model
        Group {
            if let image = cachedImage {
                Image(akImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholderView
            }
        }
        .task(id: model.fileUrl) {
            await initImage()
        }
    }
}

// MARK: - Private Helpers

private extension AsyncThumbnail {
    /// Synchronously access the cached thumbnail from the observable cache
    var cachedImage: AKImage? {
        root.itemController.cacheController?.cachedThumbnail(for: model.id)
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
    func initImage() async {
        // Avoid redundant loads if already loading or if the URL hasn't changed and we have a cached image
        guard !isLoading && (lastFileUrl != model.fileUrl || cachedImage == nil) else { return }
        
        isLoading = true
        lastFileUrl = model.fileUrl
        await loadImage()
    }
    
    /// Load the thumbnail asynchronously and update the observable cache
    func loadImage() async {
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
    AsyncThumbnail(model: .preview, size: CGSize(width: 128, height: 128), color: .gray)
        .environment(PhotoRootModel.preview)
        .frame(width: 256, height: 256)
}
