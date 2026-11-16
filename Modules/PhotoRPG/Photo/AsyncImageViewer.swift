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
                ImageViewer(
                    id: model.id,
                    image: image,
                    photoDegrees: model.degrees,
                    containerSize: size,
                    contentMode: contentMode,
                    accessibilityLabel: model.name.isEmpty
                        ? String(localized: "Photo", bundle: .module)
                        : model.name,
                    accessibilityHint: model.description.isEmpty ? nil : model.description,
                    toolBarModel: toolBarModel
                )
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
                        .font(.largeTitle)
                        .imageScale(.large)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    
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

    private var loadKey: PhotoImageLoadKey {
        PhotoImageLoadKey(model: model)
    }

    private func cachedImage(for itemId: UUID) -> AKImage? {
        cacheController?.cachedImage(for: itemId)
    }

    private var cacheController: CacheController? {
        root.editController.cacheController
    }

    /// Load full-size image with proper structured concurrency
    private func loadImage() async {
        // Deduplication: skip once this URL already has an observable cached image.
        guard lastFileUrl != model.fileUrl || cachedImage(for: model.id) == nil else {
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
        _ = await editController.loadImage(cacheType: .image, item: model, itemId: itemId, fileUrl: fileUrl)
        
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

#Preview(traits: .mockData) {
    AsyncImageViewer(
        model: .preview,
        size: CGSize(width: 320, height: 240),
        toolBarModel: nil
    )
}
