// @copyright André Trettin

import SwiftUI

#Preview {
    ThumbnailRowPhotoView(
        cacheController: FakeImageCacheController(),
        model: FakeItemModel(name: "Ancient map"),
        listDisplayModel: ListDisplayModel()
    )
    .padding()
}

public struct ThumbnailRowPhotoView: View {
    public init(cacheController: any ImageCacheControllable, model: any ItemDataAccessable, listDisplayModel: ListDisplayModel, entryId: UUID? = nil) {
        self.cacheController = cacheController
        self.model = model
        self.listDisplayModel = listDisplayModel
        self.entryId = entryId
    }

    let cacheController: ImageCacheControllable
    let model: any ItemDataAccessable
    let listDisplayModel: ListDisplayModel
    let entryId: UUID?

    @State private var isLoading: Bool = false
    
    public var body: some View {
        
        VStack {
            if let image = cachedImage {
                imageView(image: image)
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
                placeHolder(size: CGSize(width: listDisplayModel.imageHeight, height: listDisplayModel.imageHeight))
            }
        }
        .frame(width: listDisplayModel.imageHeight, height: listDisplayModel.imageHeight)
        .task(id: model.fileUrl) {
            await loadImage()
        }
    }
}

private extension ThumbnailRowPhotoView {
    var cachedImage: AKImage? {
        cacheController.cachedThumbnail(for: entryId ?? model.id)
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
                .controlSize(.small)
                .tint(Color.accentColor)
        } else {
            Image(systemName: model.fileUrl == nil ? "photo" : "photo.badge.arrow.down")
                .font(.title2)
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
    
    /// Load thumbnail image with proper structured concurrency
    func loadImage() async {
        guard !isLoading else { return }

        // A newly constructed row can already see the shared observable thumbnail.
        // Selection reconstructs list-row values, but must not start another file
        // load when the shared cache already contains the result.
        if cachedImage != nil {
            return
        }
        
        // Mark as loading; `.task(id:)` owns URL-change cancellation/restart.
        isLoading = true
        
        let fileId = entryId ?? model.id
        
        // Perform async loading with proper task priority inheritance
        await cacheController.thumbnailId(for: fileId, item: model)
        guard !Task.isCancelled else {
            isLoading = false
            return
        }
        let newImage = await cacheController.thumbnail(for: fileId)
        guard !Task.isCancelled else {
            isLoading = false
            return
        }
        
        // A transient read/cancellation must not erase a thumbnail another row or
        // detail task already published for this item.
        if let newImage {
            cacheController.setCachedThumbnail(newImage, for: fileId)
        }
        
        // Reset loading state
        isLoading = false
    }
}
