// @copyright André Trettin

import CoreRPG
import SwiftUI
import os.log

struct AsyncImageViewer: View {
    let model: PhotoModel
    let size: CGSize
    var contentMode: ContentMode = .fit
    let toolBarModel: GameToolBarModel?

    @Environment(PhotoRootModel.self) private var root

    @Environment(\.dismiss) private var dismiss

    @State private var lastFileUrl: FileUrl?
    @State private var isLoading: Bool = false

    @State private var imageError: Bool = false
    @State private var isLoadedId: UUID = UUID()

    var body: some View {
        VStack {
            if let image = cachedImage(for: model.id) {
                ImageViewer(id: model.id, image: image, photoDegrees: model.degrees, containerSize: size, contentMode: contentMode, toolBarModel: toolBarModel)
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
        .id(isLoadedId)
        .onChange(of: model.fileUrl, initial: true) {
            loadImage()
        }
    }

    private func cachedImage(for itemId: UUID) -> AKImage? {
        cacheController?.cachedImage(for: itemId)
    }

    private var cacheController: CacheController? {
        root.editController.cacheController
    }

    private func loadImage() {
        let editController = root.editController
        guard let cacheController = editController.cacheController else { return }
        let itemId = model.id
        let fileUrl = model.fileUrl
        Task {
            let loaderTask = Task(priority: .userInitiated) {
                await editController.loadImage(cacheType: .image, item: model, itemId: itemId, fileUrl: fileUrl)
            }
            _ = await loaderTask.result
            if cacheController.cachedImage(for: itemId) == nil {
                imageError = true
                Logger.itemController.warning("AsyncImageViewer: No image \(itemId, privacy: .public)")
            } else {
                imageError = false
            }
            isLoading = false
            isLoadedId = UUID()
        }
    }
}
