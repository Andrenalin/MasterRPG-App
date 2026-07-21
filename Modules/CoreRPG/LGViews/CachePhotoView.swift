// @copyright André Trettin

import SwiftUI

public struct CachePhotoView: View {
    public init(cacheController: any ImageCacheControllable, model: any ItemDataAccessable, highResolution: Bool = true) {
        self.cacheController = cacheController
        self.model = model
        self.highResolution = highResolution
    }

    let cacheController: ImageCacheControllable
    let model: any ItemDataAccessable
    let highResolution: Bool

    @State private var lastFileUrl: FileUrl?
    @State private var isLoading: Bool = false

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
        .onChange(of: model.fileUrl, initial: true) {
            initImage()
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
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
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

    func initImage() {
        guard !isLoading && (lastFileUrl != model.fileUrl || cachedImage == nil) else { return }
        isLoading = true
        lastFileUrl = model.fileUrl
        loadImage()
    }

    func loadImage() {
        Task(priority: .userInitiated) {
            let fileId = model.id
            if highResolution {
                await cacheController.photoId(for: fileId, item: model, shouldDownload: false)
            } else {
                await cacheController.thumbnailId(for: fileId, item: model)
            }
            let newImage = highResolution ? await cacheController.photo(for: fileId) : await cacheController.thumbnail(for: fileId)
            if highResolution {
                cacheController.setCachedImage(newImage, for: fileId)
            } else {
                cacheController.setCachedThumbnail(newImage, for: fileId)
            }
            isLoading = false
        }
    }
}

#Preview("CachePhotoView · Adventure") {
    let fixture = PreviewAssetFixture.cachePhotoViewFixture(.adventure)
    CachePhotoView(
        cacheController: fixture.cacheController,
        model: fixture.model
    )
    .tint(NetworkModules.space.tint)
}

#Preview("CachePhotoView · Paladin") {
    let fixture = PreviewAssetFixture.cachePhotoViewFixture(.paladin)
    CachePhotoView(
        cacheController: fixture.cacheController,
        model: fixture.model
    )
    .tint(NetworkModules.space.tint)
}

#Preview("CachePhotoView · Wizard") {
    let fixture = PreviewAssetFixture.cachePhotoViewFixture(.wizard)
    CachePhotoView(
        cacheController: fixture.cacheController,
        model: fixture.model
    )
    .tint(NetworkModules.space.tint)
}
