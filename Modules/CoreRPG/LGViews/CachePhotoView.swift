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

    @Environment(CacheItemListModel.self) private var cacheItemListModel

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
        cacheItemListModel.imageCache(cacheType: highResolution ? .image : .thumbnail, itemId: model.id)
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
                .controlSize(.extraLarge)
                .tint(Color.accentColor)
        } else {
            Image(systemName: model.fileUrl == nil ? "photo" : "photo.badge.arrow.down")
                .font(.system(size: 32))
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
        Task { @MainActor in
            let fileId = model.id
            let loaderTask = Task.detached(priority: .userInitiated) {
                if highResolution {
                    await cacheController.photoId(for: fileId, item: model, shouldDownload: false)
                } else {
                    await cacheController.thumbnailId(for: fileId, item: model)
                }
            }
            _ = await loaderTask.result
            let newImage = highResolution ? await cacheController.photo(for: fileId) : await cacheController.thumbnail(for: fileId)
            withAnimation { cacheItemListModel.setImageCache(cacheType: highResolution ? .image : .thumbnail, itemId: fileId, image: newImage) }
            isLoading = false
        }
    }
}

#Preview {
    CachePhotoView(cacheController: FakeImageCacheController(), model: FakeItemModel(name: "Test"), highResolution: false)
        .environment(CacheItemListModel())
        .tint(NetworkModules.space.tint)
        .accentColor(NetworkModules.space.tint)
}
