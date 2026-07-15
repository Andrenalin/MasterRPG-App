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

    @State private var lastFileUrl: FileUrl?
    @State private var isLoading: Bool = true
    @State private var imageError: Bool = false

    var body: some View {
        Group {
            if let image = cachedImage(for: model.id) {
                ImageViewer(id: model.id, image: image, photoDegrees: model.degrees, containerSize: size, contentMode: contentMode, toolBarModel: toolBarModel)
            } else if isLoading {
                VStack(alignment: .center, spacing: 20) {
                    Spacer()
                    Text("Loading image...", bundle: .module)
                        .font(.largeTitle)

                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.large)
                        .tint(Color.accentColor)
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .center)
            } else if imageError {
                VStack(alignment: .center, spacing: 20) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 64))
                        .foregroundStyle(.secondary)

                    Text("Failed to load image", bundle: .module)
                        .font(.title2)

                    Text("The image could not be loaded or is unavailable.", bundle: .module)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .task(id: loadKey) {
            await loadImage()
        }
    }

    private var loadKey: AsyncImageViewerLoadKey {
        AsyncImageViewerLoadKey(
            itemId: model.id,
            fileUrl: model.fileUrl,
            hasInlineData: model.fileUrl?.data != nil
        )
    }

    private func cachedImage(for itemId: UUID) -> AKImage? {
        cacheController?.cachedImage(for: itemId)
    }

    private var cacheController: CacheController? {
        root.editController.cacheController
    }

    private func loadImage() async {
        guard lastFileUrl != model.fileUrl || cachedImage(for: model.id) == nil else {
            isLoading = false
            return
        }

        let editController = root.editController
        guard let cacheController = editController.cacheController else {
            isLoading = false
            imageError = true
            return
        }

        isLoading = true
        lastFileUrl = model.fileUrl
        imageError = false

        let itemId = model.id
        let fileUrl = model.fileUrl

        _ = await editController.loadImage(cacheType: .image, item: model, itemId: itemId, fileUrl: fileUrl)

        guard !Task.isCancelled else { return }

        if cacheController.cachedImage(for: itemId) == nil {
            imageError = true
            Logger.itemController.warning("AsyncImageViewer: Failed to load image \(itemId, privacy: .public)")
        } else {
            imageError = false
        }

        isLoading = false
    }
}

private struct AsyncImageViewerLoadKey: Equatable {
    let itemId: UUID
    let fileUrl: FileUrl?
    let hasInlineData: Bool
}

#Preview(traits: .mockData) {
    AsyncImageViewer(
        model: .preview,
        size: CGSize(width: 320, height: 240),
        toolBarModel: nil
    )
}
