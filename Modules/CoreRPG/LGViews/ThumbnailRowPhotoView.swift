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
    public init(cacheController: any ImageCacheControllable, model: any ItemDataAccessible, listDisplayModel: ListDisplayModel, entryId: UUID? = nil) {
        self.cacheController = cacheController
        self.model = model
        self.listDisplayModel = listDisplayModel
        self.entryId = entryId
    }

    let cacheController: ImageCacheControllable
    let model: any ItemDataAccessible
    let listDisplayModel: ListDisplayModel
    let entryId: UUID?

    @State private var isLoading: Bool = false
    /// Identifies the load that owns `isLoading`, so a cancelled load that finishes late cannot
    /// clear the spinner of the load that replaced it (as in `CachePhotoView`).
    @State private var loadToken = UUID()

    public var body: some View {
        
        VStack {
            if let image = cachedImage {
                imageView(image: image)
                    .clipShape(.rect(cornerRadius: 12, style: .continuous))
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
    
    /// Load thumbnail image with proper structured concurrency.
    ///
    /// `.task(id:)` cancels the previous load when the file changes and starts this one at once, so
    /// there is no re-entrancy guard: an `isLoading` guard would make the replacement return
    /// immediately while the cancelled load still held the flag. See CODE_AUDIT §3.2.
    func loadImage() async {
        // A newly constructed row can already see the shared observable thumbnail.
        // Selection reconstructs list-row values, but must not start another file
        // load when the shared cache already contains the result.
        if cachedImage != nil {
            return
        }

        let token = UUID()
        loadToken = token
        isLoading = true
        defer {
            if loadToken == token { isLoading = false }
        }

        let fileId = entryId ?? model.id

        await cacheController.thumbnailId(for: fileId, item: model)
        guard !Task.isCancelled else { return }
        let newImage = await cacheController.thumbnail(for: fileId)
        guard !Task.isCancelled else { return }

        // A transient read/cancellation must not erase a thumbnail another row or
        // detail task already published for this item.
        if let newImage {
            cacheController.setCachedThumbnail(newImage, for: fileId)
        }
    }
}
