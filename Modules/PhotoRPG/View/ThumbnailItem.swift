// @copyright André Trettin

import CoreRPG
import SwiftUI

struct ThumbnailItem: View {
    static let thumbnailSize: CGSize = CGSize(width: 64, height: 64)
    init(model: PhotoDataModel, size: CGSize = Self.thumbnailSize, radius: CGFloat = CGFloat(8), ratio: ContentMode = .fill, highResolution: Bool = false) {
        self.model = model
        self.size = size
        self.radius = radius
        self.ratio = ratio
        self.highResolution = highResolution
    }
    
    let model: PhotoDataModel
    let size: CGSize
    let radius: CGFloat
    let ratio: ContentMode
    let highResolution: Bool

    @Environment(PhotoRootModel.self) private var rootModel
    @Environment(CacheItemListModel.self) private var cacheItemListModel

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

    func loadImage() {
        Task { @MainActor in
            let fileId = model.id
            let fileUrl = model.fileUrl
            let loaderTask = Task.detached(priority: .userInitiated) {
                if highResolution {
                    await rootModel.cacheController.photoId(for: fileId, with: fileUrl)
                } else {
                    await rootModel.cacheController.thumbnailId(for: fileId, with: fileUrl)
                }
            }
            _ = await loaderTask.result
            let newImage = highResolution ? await rootModel.cacheController.image(for: fileId) : await rootModel.cacheController.thumbnail(for: fileId)
            withAnimation { cacheItemListModel.setImageCache(cacheType: highResolution ? .image : .thumbnail, itemId: fileId, image: newImage) }
            isLoading = false
        }
    }
}

#Preview {
    //ThumbnailItem(model: .preview)
        Text("Need Mock Traits")
}
