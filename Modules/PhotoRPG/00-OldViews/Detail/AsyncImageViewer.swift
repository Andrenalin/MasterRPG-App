// @copyright André Trettin

import AndrenalinKit
import SwiftUI
import os.log

struct AsyncImageViewer: View {
    let model: PhotoModel
    let size: CGSize
    let toolBarModel: GameToolBarModel

    @Environment(PhotoRootModel.self) private var root

    @Environment(\.dismiss) private var dismiss

    @State private var lastFileUrl: FileUrl?
    @State private var isLoading: Bool = false

    @State private var imageError: Bool = false

    var body: some View {
        let _ = Self._printChanges()
        VStack {
            if let image = cachedImage(for: model.id) {
                ImageViewer(image: image, photoDegrees: model.degrees, containerSize: size, toolBarModel: toolBarModel)
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
        let editController = root.editController
        let cacheItemListModel = editController.cacheItemListModel
        let itemId = model.id
        let fileUrl = model.fileUrl
        Task { @MainActor in
            let loaderTask = Task.detached(priority: .userInitiated) {
                await editController.loadImage(cacheType: .image, itemId: itemId, fileUrl: fileUrl)
            }
            _ = await loaderTask.result
            if cacheItemListModel.imageCache(cacheType: .image, itemId: itemId) == nil {
                imageError = true
                Logger.itemController.warning("AsyncImageViewer: No image \(itemId, privacy: .public)")
            } else {
                imageError = false
            }
            isLoading = false
        }
    }
}
