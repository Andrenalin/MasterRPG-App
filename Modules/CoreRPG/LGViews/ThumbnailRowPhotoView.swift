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
        VStack {
            if let image = cachedImage {
                GeometryReader { proxy in
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
                }
                .frame(width: width)
            } else {
                VStack {
                    placeHolder(size: CGSize(width: widthPlaceHolder, height: heightPlaceHolder))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .onChange(of: model.fileUrl, initial: true) {
            initImage()
        }
    }
}

private extension ThumbnailRowPhotoView {
    var width: CGFloat {
        switch listDisplayModel.displayMode {
            case .compact: 160
            case .medium: 128
            case .regular: 96
            @unknown default: 96
        }
    }
    
    var cachedImage: AKImage? {
        cacheItemListModel.imageCache(cacheType: .thumbnail, itemId: entryId ?? model.id)
    }

    func imageView(image: AKImage) -> some View {
        Image(akImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
    }

    var heightPlaceHolder: CGFloat {
        width == 96 ? 96 : 64
    }

    var widthPlaceHolder: CGFloat {
        width
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
        Task { @MainActor in
            let fileId = entryId ?? model.id
            let loaderTask = Task.detached(priority: .userInitiated) {
                await cacheController.thumbnailId(for: fileId, item: model)
            }
            _ = await loaderTask.result
            let newImage = await cacheController.thumbnail(for: fileId)
            withAnimation { cacheItemListModel.setImageCache(cacheType: .thumbnail, itemId: fileId, image: newImage) }
            isLoading = false
        }
    }
}
