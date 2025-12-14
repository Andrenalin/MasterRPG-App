// @copyright André Trettin

import CoreRPG
import SwiftUI
import os.log

struct AsyncHeaderPhoto: View {
    let model: PhotoModel
    let id: UUID?
    let size: CGSize
    let topMargin: CGFloat

    @Environment(PhotoRootModel.self) private var root

    @Environment(\.dismiss) private var dismiss

    @State private var lastFileUrl: FileUrl?
    @State private var isLoading: Bool = false

    @State private var imageError: Bool = false

    var body: some View {
        let _ = Self._printChanges()
        Group {
            if let id, let image = cachedImage(for: id) {
                HeaderPhotoView(model: model, image: image, degrees: model.degrees, size: size, topMargin: topMargin)
            } else {
                HeaderPhotoView(model: model, image: nil, degrees: 0, size: size, topMargin: topMargin)
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
                await editController.loadImage(cacheType: .image, item: model, itemId: itemId, fileUrl: fileUrl)
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
