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

    var body: some View {
        VStack {
            if let image = cachedImage(for: model.id) {
                ImageViewer(id: model.id, image: image, photoDegrees: model.degrees, containerSize: size, contentMode: contentMode, toolBarModel: toolBarModel)
            } else if isLoading {
                VStack(alignment: .center, spacing: 20) {
                    Spacer()
                    Text("Loading image...", bundle: .module)
                        .font(.largeTitle)

                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(1.5)  // ✅ Scale instead of controlSize
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
        .task(id: model.fileUrl) {
            await loadImage()
        }
    }

    private func cachedImage(for itemId: UUID) -> AKImage? {
        cacheController?.cachedImage(for: itemId)
    }

    private var cacheController: CacheController? {
        root.editController.cacheController
    }

    /// Load full-size image with proper structured concurrency
    private func loadImage() async {
        // Deduplication: skip if already loading or if URL hasn't changed and we have a cached image
        guard !isLoading && (lastFileUrl != model.fileUrl || cachedImage(for: model.id) == nil) else {
            return
        }
        
        let editController = root.editController
        guard let cacheController = editController.cacheController else {
            return
        }
        
        // Mark as loading and track current URL
        isLoading = true
        lastFileUrl = model.fileUrl
        imageError = false
        
        let itemId = model.id
        let fileUrl = model.fileUrl
        
        // Perform image loading with structured concurrency
        await editController.loadImage(cacheType: .image, item: model, itemId: itemId, fileUrl: fileUrl)
        
        // Check if image loaded successfully
        if cacheController.cachedImage(for: itemId) == nil {
            imageError = true
            Logger.itemController.warning("AsyncImageViewer: Failed to load image \(itemId, privacy: .public)")
        } else {
            imageError = false
        }
        
        // Reset loading state
        isLoading = false
    }
}
