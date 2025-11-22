// @copyright André Trettin

import AndrenalinKit
import SwiftUI
import os.log

struct AsyncPhotoViewer: View {
    let model: PhotoModel
    let size: CGSize
    let contentMode: ContentMode

    @Environment(PhotoRootModel.self) private var root

    @State private var isLoading: Bool = false
    @State private var imageError: Bool = false

    var body: some View {
        VStack {
            if let image = cachedImage(for: model.id) {
                Image(akImage: image)
                    .resizable()
                    .rotationEffect(Angle(degrees: model.degrees))
                    .applyIf(contentMode == .fit) { content in
                        content
                            .aspectRatio(contentMode: contentMode)
                            .clipShape(.rect(cornerRadius: 16))
                            .frame(width: size.width, height: size.height, alignment: .center)
                    }
            } else if imageError {
                VStack(alignment: .center, spacing: 20) {
                    Spacer()
                    Text("Wait for image ...", bundle: .module)
                        .font(.largeTitle)

                    ProgressView().progressViewStyle(.circular).tint(Color.accentColor)
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .onChange(of: model.fileUrl, initial: true) {
            loadImage()
        }
    }

    private func cachedImage(for itemId: UUID) -> AKImage? {
        cacheItemListModel.imageCache(cacheType: .image, itemId: itemId)
    }

    private var cacheItemListModel: CacheItemListModel {
        root.editController.cacheItemListModel
    }

    private func loadImage() {
        Task { @MainActor in
            let loaderTask = Task.detached(priority: .userInitiated) {
                await root.editController.loadImage(cacheType: .image, itemId: model.id, fileUrl: model.fileUrl)
            }
            _ = await loaderTask.result
            if cachedImage(for: model.id) == nil {
                imageError = true
                Logger.itemController.warning("AsyncPhotoViewer: No image \(model.id, privacy: .public)")
            } else {
                imageError = false
            }
            isLoading = false
        }
    }
}

#Preview {
    AsyncPhotoViewer(model: .preview, size: CGSize(width: 300, height: 300), contentMode: .fit)
        .environment(PhotoRootModel.preview)
}
