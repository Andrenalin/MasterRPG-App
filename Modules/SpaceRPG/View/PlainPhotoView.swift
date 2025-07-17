// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct PlainPhotoView: View {
    enum SizeType {
        case maxWidth
        case maxHeightWidth(CGFloat)
    }

    init(model: SpaceDataModel, size: SizeType = .maxWidth, ratio: ContentMode = .fit, hasRoundedCorners: Bool = false, highResolution: Bool = true) {
        self.model = model
        self.size = size
        self.ratio = ratio
        self.hasRoundedCorners = hasRoundedCorners
        self.highResolution = highResolution
    }

    let model: SpaceDataModel
    let size: SizeType
    let ratio: ContentMode
    let hasRoundedCorners: Bool
    let highResolution: Bool

    @Environment(SpaceRootModel.self) private var rootModel
    @Environment(CacheItemListModel.self) private var cacheItemListModel

    @State private var lastFileUrl: FileUrl?
    @State private var isLoading: Bool = false

    var body: some View {
        VStack {
            if let image = cachedImage {
                switch size {
                    case .maxHeightWidth(let width):
                        GeometryReader { proxy in
                            imageView(image: image)
                                .clipShape(.rect(topLeadingRadius: 24, bottomLeadingRadius: 24))
                        }
                        .frame(width: width)
                    case .maxWidth:
                        imageView(image: image)
                            .clipped()
                            .backgroundExtensionEffect26()
                }
            } else {
                VStack {
                    placeHolder(size: CGSize(width: 96, height: 96))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .onChange(of: model.fileUrl, initial: true) {
            initImage()
        }
    }
}

private extension PlainPhotoView {
    var cachedImage: AKImage? {
        cacheItemListModel.imageCache(cacheType: highResolution ? .image : .thumbnail, itemId: model.id)
    }

    func imageView(image: AKImage) -> some View {
        Image(akImage: image)
            .resizable()
            .aspectRatio(contentMode: ratio)
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
                    if hasRoundedCorners {
                        UnevenRoundedRectangle(topLeadingRadius: 24, bottomLeadingRadius: 24).stroke(Color.accentColor.secondary, lineWidth: 2)
                    } else {
                        RoundedRectangle(cornerRadius: 24).stroke(Color.accentColor.secondary, lineWidth: 2)
                    }
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

#Preview(traits: .mockData) {
    @Previewable @Query var models: [SpaceDataModel]
    @Previewable @Environment(\.modelContext) var modelContext
    
    PlainPhotoView(model: models[0])
        .environment(DetailPhotoSelection())
        .environment(SpaceRootModel(modelContext: modelContext))
        .environment(CacheItemListModel())

}
