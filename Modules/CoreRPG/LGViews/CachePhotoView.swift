// @copyright André Trettin

import SwiftUI

public struct CachePhotoView: View {
    public init(cacheController: any ImageCacheControllable, model: any ItemDataAccessible, highResolution: Bool = true) {
        self.cacheController = cacheController
        self.model = model
        self.highResolution = highResolution
    }

    let cacheController: ImageCacheControllable
    let model: any ItemDataAccessible
    let highResolution: Bool

    @State private var lastFileUrl: FileUrl?
    @State private var isLoading: Bool = false
    /// Identifies the load that owns `isLoading`, so a cancelled load that finishes late cannot
    /// clear the spinner of the load that replaced it.
    @State private var loadToken = UUID()

    public var body: some View {
        VStack {
            if let image = cachedImage {
                imageView(image: image)
            } else {
                VStack {
                    placeHolder(size: CGSize(width: 105, height: 105))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        // Structured: cancelled with the view and restarted when the file changes, like
        // `ThumbnailRowPhotoView`. See CODE_AUDIT_26 §5.13.
        .task(id: model.fileUrl) {
            await loadImage()
        }
    }
}

private extension CachePhotoView {
    var cachedImage: AKImage? {
        highResolution 
            ? cacheController.cachedImage(for: model.id)
            : cacheController.cachedThumbnail(for: model.id)
    }

    func imageView(image: AKImage) -> some View {
        Image(akImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(.rect(cornerRadius: 24, style: .continuous))
            .frame(minWidth: 0, minHeight: 0, maxHeight: .infinity)
    }

    @ViewBuilder
    func placeHolder(size: CGSize) -> some View {
        if isLoading {
            ProgressView()
                .scaleEffect(2.0)
                .tint(Color.accentColor)
        } else {
            Image(systemName: model.fileUrl == nil ? "photo" : "photo.badge.arrow.down")
                .font(.title2)
                .frame(width: size.width, height: size.height)
                .overlay {
                    RoundedRectangle(cornerRadius: 20).stroke(Color.accentColor.secondary, lineWidth: 2)
                }
        }
    }

    func loadImage() async {
        guard lastFileUrl != model.fileUrl || cachedImage == nil else { return }
        let token = UUID()
        loadToken = token
        isLoading = true
        defer {
            if loadToken == token { isLoading = false }
        }
        let fileId = model.id
        let fileUrl = model.fileUrl
        if highResolution {
            await cacheController.photoId(for: fileId, item: model, shouldDownload: false)
        } else {
            await cacheController.thumbnailId(for: fileId, item: model)
        }
        guard !Task.isCancelled else { return }
        let newImage = highResolution ? await cacheController.photo(for: fileId) : await cacheController.thumbnail(for: fileId)
        guard !Task.isCancelled else { return }
        // A transient read failure must not erase an image that is already cached.
        guard let newImage else { return }
        if highResolution {
            cacheController.setCachedImage(newImage, for: fileId)
        } else {
            cacheController.setCachedThumbnail(newImage, for: fileId)
        }
        lastFileUrl = fileUrl
    }
}

#Preview("CachePhotoView · Adventure") {
    let fixture = PreviewAssetFixture.cachePhotoViewFixture(.adventure)
    CachePhotoView(
        cacheController: fixture.cacheController,
        model: fixture.model
    )
    .moduleTint(.space)
}

#Preview("CachePhotoView · Paladin") {
    let fixture = PreviewAssetFixture.cachePhotoViewFixture(.paladin)
    CachePhotoView(
        cacheController: fixture.cacheController,
        model: fixture.model
    )
    .moduleTint(.space)
}

#Preview("CachePhotoView · Wizard") {
    let fixture = PreviewAssetFixture.cachePhotoViewFixture(.wizard)
    CachePhotoView(
        cacheController: fixture.cacheController,
        model: fixture.model
    )
    .moduleTint(.space)
}
