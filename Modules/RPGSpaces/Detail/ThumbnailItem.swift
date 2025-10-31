// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct ThumbnailItem: View {
    let model: SpaceModel
    var size = SpaceRoot.thumbnailSize
    var radius = CGFloat(8)
    var ratio: ContentMode = .fill

    @Environment(SpaceRoot.self) private var root

    @State private var lastFileUrl: FileUrl?
    @State private var isLoading: Bool = false

    var body: some View {
        VStack {
            if let thumbnail = cachedImage {
                Image(akImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: ratio)
                    .frame(width: size.width, height: size.height)
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
    }

    private var cachedImage: AKImage? {
        cacheItemListModel.imageCache(cacheType: .thumbnail, itemId: model.id)
    }
    
    private var cacheItemListModel: CacheItemListModel {
        // here we want always the image cache - that should be only 1
        root.editController(type: .main).cacheItemListModel
    }

    func loadImage() {
        Task { @MainActor in
            let loaderTask = Task.detached(priority: .userInitiated) {
                await root.cacheController?.thumbnailId(for: model.id, with: model.fileUrl)
            }
            _ = await loaderTask.result
            let newImage = await root.cacheController?.thumbnail(for: model.id)
            withAnimation { cacheItemListModel.setImageCache(cacheType: .thumbnail, itemId: model.id, image: newImage) }
            isLoading = false
        }
    }
}

#Preview {
    ThumbnailItem(model: .preview)
        .environment(SpaceRoot.preview)
}
