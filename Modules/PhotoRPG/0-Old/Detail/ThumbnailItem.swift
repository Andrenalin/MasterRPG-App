// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct ThumbnailItem: View {
    init(root: PhotoRootModel, model: PhotoModel, size: CGSize = PhotoRootModel.thumbnailSize, radius: CGFloat = CGFloat(8), ratio: ContentMode = .fill, highResolution: Bool = false) {
        self.root = root
        self.model = model
        self.size = size
        self.radius = radius
        self.ratio = ratio
        self.highResolution = highResolution
    }
    
    let root: PhotoRootModel
    let model: PhotoModel
    let size: CGSize
    let radius: CGFloat
    let ratio: ContentMode
    let highResolution: Bool
    
    @State private var lastFileUrl: FileUrl?
    @State private var isLoading: Bool = false
    
    var body: some View {
        VStack {
            if let image = cachedImage {
                Image(akImage: image)
                    .resizable()
                    .aspectRatio(contentMode: ratio)
                    .frame(width: size.width, height: size.height)
                    .rotationEffect(Angle(degrees: model.degrees))
                    .cornerRadius(radius)
            } else {
                Image(systemName: model.fileUrl == nil ? "photo" : "photo.badge.arrow.down")
                    .font(.system(size: 32))
                    .frame(width: size.width - radius / 2, height: size.width - radius / 2)
                    .border(Color.secondary, width: radius / 2)
                    .cornerRadius(radius / 2)
            }
        }
        .onChange(of: model.fileUrl, initial: true) {
            guard !isLoading && (lastFileUrl != model.fileUrl || cachedImage == nil) else { return }
            isLoading = true
            lastFileUrl = model.fileUrl
            loadImage()
        }
        .animation(.bouncy, value: model.degrees)
    }
    
    private var cachedImage: AKImage? {
        cacheItemListModel.imageCache(cacheType: highResolution ? .image : .thumbnail, itemId: model.id)
    }
    
    private var cacheItemListModel: CacheItemListModel {
        // image cache
        root.editController.cacheItemListModel
    }

    func loadImage() {
        Task { @MainActor in
            let loaderTask = Task.detached(priority: .userInitiated) {
                if highResolution {
                    await root.cacheController?.photoId(for: model.id, item: model)
                } else {
                    await root.cacheController?.thumbnailId(for: model.id, item: model)
                }
            }
            _ = await loaderTask.result
            let newImage = highResolution ? await root.cacheController?.photo(for: model.id) : await root.cacheController?.thumbnail(for: model.id)
            withAnimation { cacheItemListModel.setImageCache(cacheType: highResolution ? .image : .thumbnail, itemId: model.id, image: newImage) }
            isLoading = false
        }
    }
}

#Preview {
    ThumbnailItem(root: PhotoRootModel.preview, model: .preview)
}
