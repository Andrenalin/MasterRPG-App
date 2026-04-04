// @copyright André Trettin

import SwiftUI

public struct ThumbnailRowPhotoView: View {
    public init(cacheController: any ImageCacheControllable, model: any ItemDataAccessable, entryId: UUID? = nil) {
        self.cacheController = cacheController
        self.model = model
        self.entryId = entryId
    }
    
    let cacheController: ImageCacheControllable
    let model: any ItemDataAccessable
    let entryId: UUID?
    
    @Environment(CacheItemListModel.self) private var cacheItemListModel
    @Environment(ListDisplayModel.self) private var listDisplayModel
    
    @State private var lastFileUrl: FileUrl?
    @State private var isLoading: Bool = false
    
    public var body: some View {
        let _ = Self._printChanges()
        VStack {
            if let image = cachedImage {
                imageView(image: image)
                    .frame(height: imageHeight)
#if os(iOS)
                    .clipShape(
                        .rect(
                            bottomTrailingRadius: listDisplayModel.isPadStyle ? 24 : 0,
                            topTrailingRadius: listDisplayModel.isPadStyle ? 24 : 0,
                            style: .continuous
                        )
                    )
#else
                    .clipShape(
                        .rect(
                            bottomTrailingRadius: 8,
                            topTrailingRadius: 8,
                            style: .continuous
                        )
                    )
#endif
            } else {
                placeHolder(size: CGSize(width: imageHeight, height: imageHeight))
            }
        }
        .task(id: model.fileUrl) {
            initImage()
        }
    }
}

private extension ThumbnailRowPhotoView {
    var imageHeight: CGFloat {
        switch listDisplayModel.displayMode {
        case .compact: 64
        case .medium: 96
        case .regular: 128
        }
    }
    
    var cachedImage: AKImage? {
        cacheItemListModel.imageCache(cacheType: .thumbnail, itemId: entryId ?? model.id)
    }
    
    func imageView(image: AKImage) -> some View {
        Image(akImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
    }
        
    @ViewBuilder
    func placeHolder(size: CGSize) -> some View {
        if isLoading {
            ProgressView()
                .controlSize(.extraLarge)
                .tint(Color.accentColor)
        } else {
            Image(systemName: model.fileUrl == nil ? "photo" : "photo.badge.arrow.down")
                .font(.system(size: 32))
                .frame(width: size.width, height: size.height)
                .overlay {
#if os(iOS)
                    UnevenRoundedRectangle(bottomTrailingRadius: listDisplayModel.isPadStyle ? 24 : 0, topTrailingRadius: listDisplayModel.isPadStyle ? 24 : 0)
                        .fill(Color.accentColor.tertiary)
                        .stroke(Color.accentColor.secondary, lineWidth: 2)
#else
                    UnevenRoundedRectangle(bottomTrailingRadius: 4, topTrailingRadius: 4)
                        .fill(Color.accentColor.tertiary)
                        .stroke(Color.accentColor.secondary, lineWidth: 2)
#endif
                }
        }
    }
    
    func initImage() {
        guard !isLoading && (lastFileUrl != model.fileUrl || cachedImage == nil) else { return }
        isLoading = true
        lastFileUrl = model.fileUrl
        loadImage()
    }
    
    func loadImage() {
        Task(priority: .userInitiated) {
            let fileId = entryId ?? model.id
            await cacheController.thumbnailId(for: fileId, item: model)
            let newImage = await cacheController.thumbnail(for: fileId)
            withAnimation { cacheItemListModel.setImageCache(cacheType: .thumbnail, itemId: fileId, image: newImage) }
            isLoading = false
        }
    }
}
